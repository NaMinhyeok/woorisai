# Notification 계약

`notification` module은 FID ownership, privacy-safe message mapping과 commit-after delivery를
소유한다. Firebase client는 module-internal adapter이고 durability는 Spring Modulith JPA event
publication registry가 담당한다. 작은 recipient 집합에 custom queue/fan-out/delivery system을
운영하는 비용이 더 크므로 별도 worker와 scheduler는 두지 않는다.

## Event와 recipient

| Producer event | Recipient | `eventType` | `resourceId` | 일반 body |
| --- | --- | --- | --- | --- |
| `RelationshipScoreChanged` | Relationship target participant | `relationshipScoreChanged` | Score change ID | 새로운 마음 기록이 도착했어요 |
| `ScoreChangeCommentCreated` | 댓글 작성자의 상대 participant | `scoreChangeCommentCreated` | Parent score change ID | 새로운 댓글이 도착했어요 |
| `DiaryEntryCommentCreated` | 댓글 작성자의 상대 participant | `diaryEntryCommentCreated` | Parent diary entry ID | 새로운 댓글이 도착했어요 |

Diary entry create/update/delete와 comment update/delete는 event를 만들지 않는다. Event에는
recipient participant ID와 route resource ID만 있다. Producer는 notification type이나 Firebase를
import하지 않는다.

Listener ID는 outstanding publication과 rollout의 durable compatibility contract다.

- `notification.relationship-score-changed`
- `notification.score-change-comment-created`
- `notification.diary-entry-comment-created`

Listener ID나 event class shape를 바꾸려면 기존 publication을 어떻게 읽고 완료할지 먼저
결정한다.

## Privacy-safe payload

Firebase message는 다음 값만 사용한다.

- Title: `우리 사이`
- Body: 위 표의 generic 문구
- Data: `eventType`, 양수 `resourceId`

FCM의 FID target field를 사용하며 registration-token fallback은 없다. Payload와 log에는
participant 정보, 점수와 reason, 사용자 content, media 정보, FID와 provider response detail을
넣지 않는다. iOS는 notification tap 뒤 Basic API로 resource를 다시 읽어 권한과 존재 여부를
확인한다.

## Transaction과 delivery

Producer는 domain transaction 안에서 Spring `ApplicationEventPublisher`로 event를 발행한다.
Spring Modulith는 같은 transaction의 `event_publication`에 listener publication을 저장하고
`@ApplicationModuleListener`는 commit 뒤 별도 transaction으로 실행된다.

- Publication 저장 실패는 producer write를 rollback한다.
- Firebase, FID store나 configuration 실패는 이미 commit된 domain write를 rollback하지 않는다.
- Listener 성공 시 publication row를 제거한다.
- 저장된 값이 FID 형식 검증을 통과하지 못하거나 FCM이 `UNREGISTERED`로 확인한 경우에만 row를
  삭제하고 다른 target 처리를 계속한다.
- `INVALID_ARGUMENT`을 포함한 그 밖의 provider failure는 listener를 실패시켜 publication을
  outstanding으로 남긴다. Request/payload/configuration 오류를 target 폐기로 오인하지 않는다.
- Restart에서 outstanding publication을 다시 시도한다.
- Provider acknowledgement 경계 때문에 드물게 중복될 수 있으며 app route는 중복에 안전해야
  한다.

한 participant의 여러 FID는 등록 ID 순서로 전송한다. 하나의 transient failure가 listener
전체를 실패시키면 restart에서 앞선 target에도 다시 전송될 수 있다. 현재 작은 fan-out에서는
per-target delivery ledger 대신 이 단순한 at-least-once 성격을 수용한다.

## FID lifecycle

`POST /api/v2/notification-fids`와 `DELETE /api/v2/notification-fids`는 Basic actor를
participant로 사용하고 `Cache-Control: no-store`로 204를 반환한다.

- FID는 정확히 22자의 ASCII base64url 문자(`[A-Za-z0-9_-]{22}`)다.
- FID는 globally unique다.
- Register는 PostgreSQL upsert 한 문장으로 새 row를 만들거나 현재 participant에게 원자적으로
  재배정하고 등록 시각을 갱신한다.
- Unregister는 같은 participant 소유 FID만 삭제한다. Missing이나 다른 participant 소유 값도
  정보 노출 없이 성공 no-op이다.
- Participant별 device cap, installation UUID, generation, active flag, user agent와 custom retry
  metadata는 없다.

Target identifier는 FID 하나로 통일한다. Apple client가 설치 lifecycle에서 관찰·회전하는
식별자와 Firebase Admin SDK `Message.setFid`가 소비하는 식별자를 같게 두면 별도
registration-token mapping과 두 target의 회전 상태가 필요 없다. 그래서 registration-token
fallback을 두지 않는다.

## Runtime switch와 보안

`FIREBASE_NOTIFICATIONS_ENABLED=false`이면 listener는 unavailable로 실패하고 publication을
outstanding으로 남긴다. `true`일 때 `FIREBASE_PROJECT_ID`와
`FIREBASE_SERVICE_ACCOUNT_JSON_BASE64`가 모두 유효해야 startup한다.

Service account JSON, decoded bytes, FID, provider message/error detail과 provider message ID를
log하지 않는다. 실패는 APNs authentication, Firebase project/authentication, quota, transient,
unknown처럼 안정적인 privacy-safe category만 남긴다. Provider integration은 production과
분리한 Firebase project와 test device로 검증한다.

## 확장 조건

실제 device 수, duplicate 영향, provider outage와 restart recovery가 이 계약을 감당하지 못할
때만 custom delivery row, per-target retry/backoff, poison isolation이나 broker를 검토한다. 이때
이 문서에 선택 근거와 실패 의미를 갱신하고 schema, observability와 replay test를 함께
설계한다.
