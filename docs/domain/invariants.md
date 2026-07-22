# 도메인·운영 불변식

이 문서는 구현, [OpenAPI](../../contracts/openapi-v2.yaml), schema와 운영 절차가 함께 지켜야
할 최소 제품 계약과 동시성 선택 근거를 소유한다. 전체 구조의 복잡도 경계는
[시스템 아키텍처](../architecture/system-architecture.md), persistence shape는
[data model](data-model.md)을 따른다.

## 참가자

- 참가자는 정확히 두 명이며 slot 1과 slot 2가 각각 한 명이다.
- Slot, participant ID 또는 display name topology가 불완전하면 일부 결과로 보정하지 않고
  service unavailable로 취급한다.
- `participant` module이 `CanonicalParticipantPair`를 보장하고 consumer는 actor 권한만
  판정한다.
- Runtime participant provisioning/CRUD API는 없다.

## 인증과 권한

- 보호 API는 매 요청 `Authorization: Basic`을 검증한다.
- Username은 정확히 `1` 또는 `2`, password는 ASCII 숫자 네 자리 PIN이다.
- PIN은 `participant_credential.pin_hash`에 one-way hash로만 저장한다.
- `GET /health`, `GET /api/v2/auth/login-options`만 공개다. 나머지 `/api/v2/**`는 인증이
  필요하고 다른 경로는 거부한다.
- 인증은 stateless다. Cookie/session, server login/logout, access token, refresh/revoke와
  custom rate bucket은 없다.
- Canonical pair나 credential store가 불완전한 경우와 잘못된 credential을 구분한다. 전자는
  unavailable, 후자는 participant 존재를 드러내지 않는 동일한 401이다.
- Production Basic 요청은 HTTPS만 허용한다. Header와 PIN은 log, telemetry, fixture, 문서와
  error body에 남기지 않는다.

이 모델은 두 사람이 쓰는 private application이라는 제품 조건에서만 의도적으로 단순하다.
사용자 범위가 넓어지면 credential lifecycle, brute-force 방어와 session/token 전략을 별도
결정한다.

## 관계 점수와 이력

- 두 참가자 사이에는 반대 방향의 score row 두 개가 있다.
- 점수는 0~100의 방향 값이며 actor는 자신의 outgoing score만 바꾼다.
- 변경 요청은 `delta` 또는 `targetScore` 중 정확히 하나를 사용한다.
- Delta는 0이 아니어야 한다. 결과가 범위를 벗어나거나 target이 현재 값과 같으면 conflict다.
- 한 transaction에서 current score의 optimistic version update, immutable change history,
  optional score image와 event publication을 함께 commit하거나 rollback한다.
- 겹친 write의 loser는 history, attachment와 event를 남기지 않고
  `409 RELATIONSHIP_CONFLICT`를 받는다. Server는 delta나 target write를 자동 재시도하지 않는다.
- Change actor는 relationship source participant와 같아야 한다.
- History는 양방향을 합쳐 `created_at DESC, id DESC`, page size 20으로 읽는다.
- Server가 timestamp와 resulting score를 결정한다.

## 점수 댓글

- 두 참가자 모두 모든 score change를 읽고 댓글을 만들 수 있다.
- 댓글은 reply nesting 없는 `created_at ASC, id ASC`의 평평한 대화다.
- Content는 trim 후 최대 500 code point이며 text-only, media-only 또는 둘 다 가능하다.
- Media-only content는 빈 문자열이 아니라 `NULL`이다.
- 생성, ordered attachment와 상대 participant 대상 event는 한 transaction이다.
- Update/delete API는 없다.

## 공유 일기

- 두 참가자 모두 일기를 읽고 쓸 수 있고 entry 작성자만 자신의 entry를 수정·삭제한다.
- Entry content는 trim 후 nonblank 최대 1000 code point다.
- 목록은 `created_at DESC, id DESC`, page size 20이다.
- Comment thread는 `created_at ASC, id ASC`의 평평한 대화다.
- 두 참가자 모두 comment를 만들 수 있고 작성자만 수정·삭제한다.
- Comment content는 trim 후 nonblank 최대 500 code point다.
- Server가 게시·수정 시각을 결정한다.
- Entry/comment update와 delete는 JPA `@Version`으로 겹친 transaction을 감지한다.
- Optimistic loser와 comment create 중 parent가 먼저 삭제된 FK race는
  `409 DIARY_CONFLICT`다. 실패한 transaction은 content, attachment와 event를 모두
  rollback하며 자동 재시도하지 않는다.
- 같은 entry에 독립적인 comment create는 parent version을 갱신하지 않아 함께 commit될 수
  있다.
- Diary comment 생성만 상대 participant 대상 event를 만든다.

### 내부 optimistic version의 범위

- API는 persistence version, ETag과 `If-Match`를 노출하지 않는다.
- `@Version`은 실행 시간이 겹친 DB transaction을 감지한다.
- 이미 commit된 변경 이후 시작한 stale-screen request는 최신 version을 다시 읽기 때문에
  stale 화면 자체를 conflict로 식별하지 못한다.
- SQL update 시 PostgreSQL row lock에서 잠시 대기한 loser가 version mismatch를 받는 것은
  정상 동작이다.

### 동시성 선택 근거

Relationship score와 diary entry/comment의 겹친 수정은 드물다. 일반 read부터 비관적 write
lock을 얻으면 충돌하지 않는 작업과 같은 entry의 독립 comment create까지 불필요하게
직렬화하므로 내부 `@Version`을 우선한다. 충돌 요청을 자동 재시도하지 않는 이유는 delta,
target score 또는 content를 새 상태에 다시 적용하면 사용자가 처음 보낸 의도를 바꿀 수 있기
때문이다.

Persistence version을 wire에 노출하지 않아 client는 단순하지만 이미 commit된 변경보다 오래된
화면의 overwrite는 식별하지 못한다. 반대로 media upload는 single-use 상태와 R2 side effect를
version check만으로 되돌릴 수 없어 비관적 락을 유지한다.

## 미디어

- Bucket과 object는 private이며 API가 짧은 presigned URL만 발급한다.
- Image는 JPEG/PNG/WebP, video는 MP4/WebM/QuickTime을 지원한다.
- Image 최대 크기는 10 MiB, video는 100 MiB다.
- Score change는 image 0~1개다.
- Score comment와 diary entry는 image 0~4개 또는 video 정확히 1개다. 혼합하지 않는다.
- Upload UUID는 unique하고 request 순서를 `position=0..n-1`로 보존한다.
- Uploader, purpose와 kind는 parent write와 일치해야 한다.
- Attachment mutation은 caller transaction에 mandatory로 참여한다.
- Upload 상태는 `PENDING`, `READY`뿐이고 parented `READY`가 attachment다.
- Complete는 staging과 final object의 size, content type과 signature를 확인한다.
- Object delete는 DB commit 뒤 best effort다. 실패로 committed business write를 rollback하지
  않는다.
- Expired parentless upload와 DB가 참조하지 않는 R2 object는 accepted orphan이다. 자동
  scheduler, lease, CAS와 reconciliation state machine은 없다.
- Complete/discard/attach/replace는 single-use upload와 외부 side effect 때문에
  `PESSIMISTIC_WRITE`를 사용하는 명시적 예외다.

상세 상태와 실패 의미는 [media lifecycle](media-lifecycle.md)을 따른다.

## Notification

- Score change, score comment create와 diary comment create가 상대 participant용 event를
  만든다.
- Event는 recipient participant ID와 route resource ID만 운반한다.
- 잠금 화면 payload에는 participant, score, reason, 사용자 content와 media 정보를 넣지 않는다.
- Producer write와 event publication은 같은 transaction이다. Listener는 commit 뒤 실행된다.
- 저장된 값이 FID 형식 검증을 통과하지 못하거나 FCM이 `UNREGISTERED`로 확인한 경우에만
  삭제한다. `INVALID_ARGUMENT`, transient와 configuration failure는 publication을
  outstanding으로 남긴다.
- Restart republish와 provider acknowledgement 경계 때문에 push는 중복될 수 있으며 app은
  route 처리를 중복 안전하게 한다.
- Custom queue, fan-out/delivery row, poller와 retry scheduler는 없다.

상세 계약은 [notification contract](notification-contract.md)을 따른다.

## Database와 runtime

- Spring은 PostgreSQL `woorisai` schema의 유일한 business writer다.
- Flyway가 schema를 소유하고 runtime JPA는 `ddl-auto=validate`만 사용한다.
- Build/startup/deploy hook에서 PIN을 입력하거나 data copy/backfill/reconcile을 실행하지 않는다.
- CDC, incremental sync, dual-write와 shadow writer를 만들지 않는다.
- `/health`는 Actuator readiness이며 production DataSource가 사용할 수 없으면 503이다.
- R2/Firebase provider failure는 DB readiness 의미를 바꾸지 않는다.
- Presigned URL, Authorization header, PIN, FID와 provider credential을 log하지 않는다.

## 변경 gate

다음 변경은 구현보다 먼저 제품/아키텍처 결정을 요구한다.

- 참가자 수 또는 slot model 확대
- Public launch와 인증/session/token/rate limiting 도입
- Score/history 삭제 정책 변경
- 새 media kind/purpose/size/count 또는 durable cleanup 도입
- Notification payload에 개인 내용 추가
- Custom delivery guarantee, queue나 broker 도입
- Online schema transition, CDC 또는 dual-write 도입
- Wire-level stale-write 보호 도입
- Relationship/diary conflict rate나 DB lock 대기 증가로 transaction·lock granularity 재측정
