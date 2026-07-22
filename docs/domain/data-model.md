# Data model

Business data는 PostgreSQL `woorisai` schema에 있고 각 table은 하나의 Spring Modulith module이
소유한다. Schema는 Flyway가 변경하고 JPA는 mapping을 검증한다. Module 간 JPA association을
피하고 scalar ID와 public port를 사용하는 이유는 persistence 편의가 business dependency를
역전시키지 않게 하기 위해서다.

Clean schema와 단일 writer를 선택한 근거는
[시스템 아키텍처](../architecture/system-architecture.md), business·동시성 규칙은
[불변식](invariants.md)을 따른다.

## Table 소유권

| Module | Table | 책임 |
| --- | --- | --- |
| `participant` | `participant` | Slot 1/2의 ID와 표시 이름 |
| `identity` | `participant_credential` | Participant별 PIN hash |
| `relationship` | `relationship_score` | Source에서 target으로 향하는 현재 점수 |
| `relationship` | `score_change` | 수정하지 않는 점수 변경 이력 |
| `relationship` | `score_change_comment` | 점수 변경의 평평한 시간순 댓글 |
| `diary` | `diary_entry` | 공유 일기 본문과 작성자 |
| `diary` | `diary_entry_comment` | 일기의 평평한 시간순 댓글 |
| `media` | `media_attachment` | Upload와 attachment metadata, parent와 순서 |
| `notification` | `notification_fid` | Participant가 등록한 Firebase Installation ID |
| Spring Modulith | `event_publication` | Commit 이후 listener를 위한 publication registry |

Flyway schema history도 `woorisai` schema에 둔다.

## Participant와 identity

`participant`는 bigint identity PK, unique `slot`, unique `display_name`과 server timestamp를
가진다. DB는 slot이 1 또는 2인 것을 강제하고 application은 두 slot이 각각 정확히 한 행인
canonical pair를 요구한다.

`participant_credential`은 `participant_id`를 PK/FK로 사용하고 `pin_hash`, `updated_at`만
저장한다. PIN 원문, session, access token, login attempt와 rate bucket을 저장하지 않는다.

## Relationship

`relationship_score`는 `source_participant_id → target_participant_id` 방향의 현재 점수다.
Source와 target은 각각 unique이고 서로 달라야 하므로 canonical pair에는 반대 방향 두 행이
있다. `current_score`는 0~100이고 `version`은 내부 JPA `@Version`이다.

`score_change`는 relationship과 actor를 함께 참조한다. Composite FK가 actor와 source
participant가 같은 관계임을 DB에서도 보존한다. `delta`는 -100~100의 0이 아닌 값이고
`resulting_score`는 0~100이다. `reason`은 없으면 `NULL`, 있으면 trim 뒤 nonblank 최대 200자다.
이력은 생성 이후 수정하거나 삭제하지 않는다.

`score_change_comment`는 parent change, author, nullable content와 server timestamp를 가진다.
Media-only comment는 빈 문자열 대신 `NULL`을 저장한다. Thread 순서는
`created_at ASC, id ASC`다.

## Diary

`diary_entry`는 author, trim 뒤 nonblank 최대 1000자 content, server timestamps와 내부 JPA
`@Version`을 가진다. 목록 정렬은 `created_at DESC, id DESC`다.

`diary_entry_comment`는 parent entry, author, trim 뒤 nonblank 최대 500자 content, server
timestamps와 내부 JPA `@Version`을 가진다. Thread 정렬은 `created_at ASC, id ASC`다. Entry
delete는 comment를 cascade로 삭제한다. Participant, score와 history에는 accidental cascade를
허용하지 않는다.

Persistence version은 public JSON, ETag이나 `If-Match`로 노출하지 않는다.

## Media attachment

`media_attachment`의 UUID는 upload와 attachment를 식별하는 stable ID다. Table은 다음 metadata를
소유한다.

- Uploader와 `SCORE_CHANGE`/`SCORE_CHANGE_COMMENT`/`DIARY_ENTRY` purpose
- `IMAGE`/`VIDEO` kind, 원본 이름, normalized content type, expected/actual size
- Private R2 object key, `PENDING`/`READY` status와 timestamps
- Purpose별 nullable parent FK와 parent 안의 zero-based `position`

`PENDING`은 parent, actual size와 ready time이 없고 position 0이다. `READY`는 actual size가
expected size와 같고 ready time이 있으며, parent가 없거나 purpose와 맞는 parent 하나를 가진다.
Parented `READY`가 attachment이며 별도 `ATTACHED` 상태는 없다. Partial unique index가 score
image 한 개와 parent별 position 중복 금지를 보조한다.

R2 SDK/client는 `media.internal` adapter다. Media가 별도 business module인 이유는 저장소
연결보다 uploader 권한, purpose/kind/size, 상태 전이와 attachment cardinality를 소유하기
때문이다. 상세 상태 계약은 [media lifecycle](media-lifecycle.md)을 따른다.

## Notification

`notification_fid`는 bigint identity PK, participant FK, globally unique FID와 등록 시각을
가진다. 같은 FID를 다시 등록하면 현재 participant에게 원자적으로 재배정한다. App installation
UUID, user agent, active flag나 provider token 사본은 저장하지 않는다.

`event_publication`은 Spring Modulith가 관리한다. Producer transaction과 publication을
원자적으로 묶고 listener 완료 뒤 row를 제거한다. Custom outbox, fan-out, delivery, poll/lease
table은 두지 않는다. 상세 의미는 [notification 계약](notification-contract.md)을 따른다.

## Mapping과 schema 원칙

- 모든 entity와 repository는 owning module의 `internal` package에 둔다.
- Flyway가 table, constraint, index와 schema history를 소유한다. 적용된 migration은 수정하지
  않고 새 변경은 additive migration으로 표현한다.
- Runtime은 `hibernate.default_schema=woorisai`, `ddl-auto=validate`, `generate-ddl=false`,
  `open-in-view=false`다.
- Relationship score와 diary entry/comment만 JPA `@Version`을 사용한다.
- PostgreSQL constraint, partial index, identity sequence와 lock 의미는 `postgresTest`로
  검증한다. H2 결과만으로 production dialect 계약을 주장하지 않는다.

## 의도적으로 없는 model

- Session, access/refresh token, rate bucket과 credential history
- Custom request idempotency ledger
- Media cleanup/lease/CAS/tombstone table
- Custom notification fan-out/delivery/retry table
- CDC, shadow copy와 dual-write metadata
