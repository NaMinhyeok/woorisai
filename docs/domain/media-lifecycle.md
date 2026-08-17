# 비공개 미디어 lifecycle

`media`는 Cloudflare R2 연결 자체보다 upload가 어떤 business object에 어떤 규칙으로 붙을 수
있는지를 소유하는 얇은 business module이다. R2 SDK/client와 presign, inspect, copy, delete는
`media.internal` adapter에 둔다. API 정본은 [OpenAPI](../../contracts/openapi-v2.yaml), 전체
business rule은 [불변식](invariants.md)을 따른다.

## 정책

| Purpose | 허용 kind/type | 개별 최대 | Parent 제한 |
| --- | --- | --- | --- |
| `SCORE_CHANGE` | JPEG, PNG, WebP image | 10 MiB | Image 0~1개 |
| `SCORE_CHANGE_COMMENT` | 위 image 또는 MP4, WebM, QuickTime video | Image 10 MiB, video 100 MiB | 합계 0~4개, 그중 video 최대 1개 |
| `DIARY_ENTRY` | 위 image 또는 MP4, WebM, QuickTime video | Image 10 MiB, video 100 MiB | 합계 0~4개, 그중 video 최대 1개 |

Image와 video는 한 group에 함께 붙을 수 있다. Kind가 아니라 개수가 상한이며, video만 따로
1개로 제한한다. Video는 image의 열 배 크기라 group 하나가 client preview cache 상한을 넘기지
않도록 묶어 두는 값이고, 이 상한을 올린다면 `PrivateMediaPreviewStore`의 cache 예산을 같은
작업에서 함께 조정해야 한다. 이 group 규칙의 정본은 `MediaAttachmentGroupPolicy`이며 write와
read 양쪽이 같은 gate를 통과한다 — 규칙을 좁히면 이미 저장된 group이 읽히지 않는다.

Filename은 path를 제거한 nonblank 최대 255 code point이고 control character를 허용하지 않는다.
Content type parameter는 제거하고 lowercase로 normalize한다. Expected size는 1 이상이며 complete
뒤 actual size와 정확히 같아야 한다.

기본 upload URL TTL은 900초, download URL TTL은 300초다. 설정 허용 범위는 60~3600초다.
Presigned URL과 signature query는 credential이므로 cache와 log에 남기지 않는다.

## 상태 model

```mermaid
stateDiagram-v2
    [*] --> PENDING: initiate
    PENDING --> READY: complete and verify
    READY --> READY: attach parent in domain transaction
    PENDING --> [*]: discard metadata
    READY --> [*]: discard unattached metadata
    READY --> [*]: diary replacement or cascade
```

상태는 `PENDING`, `READY` 둘뿐이다.

- `PENDING`: Parent, actual size와 ready time이 없고 position은 0
- Parentless `READY`: Object 검증은 끝났지만 business parent에 붙지 않은 상태
- Parented `READY`: Attachment. Parent FK와 position이 연결을 표현

별도 finalizing/attached/deleting 상태, expiry column, claim token, cleanup lease와 tombstone은
두지 않는다. 작은 private workload에서 durable cleanup state machine의 비용보다 orphan을
private하게 수용하는 편이 단순하기 때문이다.

Complete, discard, attach와 replace는 같은 upload row에 비관적 락을 사용한다. Upload가
single-use이고 complete에 R2 inspect/copy가 포함돼 version mismatch 뒤 외부 side effect를
안전하게 되돌릴 수 없기 때문이다. Provider workflow가 idempotent하거나 명시적 보상으로 이
경계를 분리할 수 있게 되면 락 범위를 다시 검토한다.

## Initiate

`POST /api/v2/media-uploads`는 Basic actor를 uploader로 사용한다.

1. Purpose, kind, filename, content type과 expected size를 검증한다.
2. UUID와 private staging object key를 만들고 `PENDING` row를 저장한다.
3. Exact content type/size용 short-lived PUT URL을 발급한다.

Media provider가 꺼져 있거나 signing/storage가 실패하면 성공으로 보이지 않는다. 각 initiate는
새 UUID를 만들며 quota/idempotency ledger는 없다. Client는 R2 PUT에 API Basic header를 보내지
않는다.

## Complete

`POST /api/v2/media-uploads/{id}/complete`는 uploader만 호출한다.

1. Row를 `FOR UPDATE`로 잠그고 owner, parentless `PENDING`과 purpose를 검증한다.
2. Staging object의 존재, size, content type과 leading-byte signature를 검사한다.
3. Private final key로 copy한다.
4. Final object를 다시 inspect한다.
5. 같은 transaction에서 object key, actual size, ready time과 `READY`를 저장한다.
6. Commit 뒤 staging object 삭제를 best effort로 시도한다.

검사, copy 또는 DB transaction이 실패하면 metadata는 `PENDING`으로 남아 retry할 수 있다.
Copy 결과가 불명확한 뒤 DB commit이 실패하면 참조되지 않는 final object가 남을 수 있다.
Attachment 정본은 DB이며 이 상황을 보완하려 custom CAS/lease/reconciliation을 추가하지 않는다.

## Attach와 replace

`MediaAttachmentMutation`은 relationship/diary caller transaction에
`Propagation.MANDATORY`로 참여한다.

- UUID row를 잠그고 중복, uploader, purpose, parentless `READY`, kind mix와 count를 다시
  검증한다.
- Purpose와 parent 열의 대응은 `MediaAttachment`가 소유한다. `attachScoreChange`,
  `attachScoreComment`와 `attachDiaryEntry`는 자신의 purpose가 아닌 upload를 거부하므로,
  service 검증을 우회한 경로도 조회 불가능한 parented row를 만들 수 없다.
- Score change는 image 하나를 position 0에 붙인다.
- Score comment는 request 순서대로 image 최대 네 개 또는 video 하나를 붙인다.
- Diary create는 exact list를 붙인다.
- Diary update에서 `mediaUploadIds`가 생략되면 기존 list를 유지하고, 빈 list면 모두 제거하며,
  값이 있으면 request order가 final list다.
- 같은 diary에 붙은 row는 유지할 수 있고 빠진 row는 DB에서 삭제한다.
- Parent write, attachment FK/position과 event publication은 함께 commit하거나 rollback한다.

DB row 삭제는 R2 object 삭제를 보장하지 않는다. Read API는 parented `READY`만 신뢰하므로
남은 object가 application data로 다시 나타나지는 않는다.

## Read와 download

Business response는 parent ID와 uploader까지 검증된 parented `READY` metadata만 반환한다.
Position은 0부터 연속이어야 하며 kind/count/type/size가 stored policy와 다르면 부분 결과 대신
service unavailable로 취급한다.

`GET /api/v2/media-attachments/{id}/download-url`은 canonical participant가 parented `READY`
attachment를 요청할 때만 private GET URL을 발급한다. Parentless upload나 불일치 topology를
노출하지 않는다. Response는 `Cache-Control: no-store`다.

Grant를 받은 client가 object를 기기에 영구 보관하는 것은 막지 않는다. iOS는 viewer에서 사진 앱
저장을 제공하며 그 경계와 근거는 [iOS 아키텍처](../architecture/ios-architecture.md)가
소유한다. Server는 발급 시점의 권한만 판단하고 이미 내려간 사본을 회수하지 않는다. 서로의 미디어를
이미 볼 수 있는 두 participant 사이에서 회수 가능한 반출 통제는 지키는 위협이 없고, 구현하려면
DRM 수준의 복잡도를 감수해야 한다. `no-store`와 짧은 TTL은 여전히 URL 자체가 credential이기
때문에 유지한다.

## Discard와 orphan

`DELETE /api/v2/media-uploads/{id}`는 uploader 소유의 parentless `PENDING` 또는 `READY` row를
삭제한다. Missing/repeated discard는 성공 no-op이고 parented attachment는 discard할 수 없다.
DB commit 뒤 staging/final object 삭제를 best effort로 수행한다.

다음 private orphan은 허용한다.

- 오래된 parentless `PENDING` 또는 `READY`
- DB transaction 뒤 삭제에 실패한 staging/final object
- Diary replacement/delete 뒤 남은 final object

Diary entry delete는 soft delete이므로 `media_attachment` 행 자체가 남는다. Parent 행이 살아
있어 `ON DELETE CASCADE`가 동작하지 않기 때문이고, 그만큼 R2 object도 물리 삭제 때보다 오래
남는다. 삭제 표시된 entry는 조회에서 제외되어 attachment도 노출되지 않으므로 이를 accepted
orphan으로 다룬다. Attachment까지 삭제 표시로 바꾸려면 `(diary_entry_id, position)` 부분 유니크
인덱스가 slot을 영구 점유하지 않도록 `AND deleted_at IS NULL`을 함께 넣어야 한다.

Bucket 규모, 비용이나 privacy 위험이 이 선택을 감당하지 못한다는 증거가 생기면 이 문서와
관련 schema·운영 문서에 retention, list/delete 권한, idempotency, recovery와 observability의
선택 근거를 함께 정리한다.

## 검증

- H2: Policy, owner/purpose/state/count/order, transaction rollback과 storage test double
- PostgreSQL Testcontainers: Constraint, partial unique index, row lock과 transaction 의미
- Staging R2: Presign, PUT, inspect/signature, copy, download와 best-effort delete

Docker가 없을 때 PostgreSQL 의미를 H2로 대체하거나 관련 test를 skip하지 않는다.
