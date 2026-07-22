# Spring Modulith module 경계

Backend는 하나의 Spring Boot application이고 Java package를 business module 경계로 사용한다.
별도 service로 나누지 않아도 소유 상태, dependency 방향과 transaction 책임을 명시적으로
검증하기 위한 선택이다. Spring Modulith는 명시적으로 선언한 module만 탐지하고
`com.woorisai.ModularityTests`가 구조를 검증한다.

Repository와 단일 deployable을 선택한 근거는 [시스템 아키텍처](system-architecture.md),
상태·동시성 규칙은 [도메인 불변식](../domain/invariants.md)과
[data model](../domain/data-model.md)이 소유한다.

## 소유권과 의존성

| Module | 소유 상태·규칙 | 공개 계약 | 직접 의존성 |
| --- | --- | --- | --- |
| `participant` | 정확한 slot 1/2 participant directory | `ParticipantDirectory`, `CanonicalParticipantPair`, `ParticipantReference` | 없음 |
| `identity` | PIN hash, Basic 인증, login options | 공개 Java API 없음; HTTP adapter는 internal | `participant` |
| `media` | Upload metadata, object lifecycle, attachment 규칙 | Attachment query/mutation port와 immutable metadata | 없음 |
| `relationship` | 방향 점수, immutable history, score comment | Privacy-safe score/comment event | `participant`, `media` |
| `diary` | Entry/comment와 작성자 권한 | Privacy-safe diary-comment event | `participant`, `media` |
| `notification` | FID 소유권, event listener, Firebase delivery | 공개 Java API 없음; provider와 HTTP adapter는 internal | `relationship`, `diary` |

```text
participant  <----- identity
     ^  ^
     |  |
relationship -----> media <----- diary
     ^                           ^
     |                           |
     +-------- notification -----+
```

Event의 runtime 흐름은 producer에서 notification으로 향하지만, event type은 producer가
소유한다. 따라서 `notification`이 producer package에 compile-time으로 의존하며 producer는
notification이나 Firebase를 알지 않는다.

`operations`, `shared`, `common`, `infrastructure` business module은 만들지 않는다.
Readiness와 metric은 Actuator 기술 설정이다. 여러 module이 쓰는 코드라는 이유만으로
business vocabulary를 generic package로 옮기지 않는다.

## Module 계약

### `participant`

`participant` table과 canonical pair 판정은 이 module만 소유한다. Public directory는 slot 1과
2의 정확한 두 participant를 immutable value로 반환한다. 누락, 중복이나 잘못된 topology를
consumer가 보정하지 않고 provider가 fail closed한다. Participant provisioning/CRUD API는
없다.

### `identity`

Slot을 canonical participant ID로 해석하고 `participant_credential`의 PIN hash를 검증한다.
Spring Security principal은 canonical participant ID scalar다. Credential entity/repository,
`PasswordEncoder`, security handler와 controller는 internal이다.

### `media`

다른 domain은 다음 좁은 port만 사용한다.

- `AttachedMediaQuery`: parent ID와 expected uploader에 맞는 parented `READY` metadata 조회
- `MediaAttachmentMutation`: caller transaction 안에서 upload를 parent에 연결·교체

Command와 result는 scalar ID, UUID와 immutable value만 전달한다. R2 SDK/client, JPA
entity/repository, presign request와 HTTP DTO는 internal이다. Media row는 다른 module entity를
연결하지 않고 scalar parent ID를 저장한다.

### `relationship`

Participant directory와 media port만 호출한다. Current score, immutable change history와 score
comment를 소유한다. Public event인 `RelationshipScoreChanged`와
`ScoreChangeCommentCreated`는 recipient와 route resource ID만 가진다.

### `diary`

Participant directory와 media port만 호출한다. Entry/comment entity, repository, HTTP DTO와
authorization failure는 internal이다. `DiaryEntryCommentCreated`만 notification용 public
event다.

### `notification`

Producer-owned event를 안정적인 listener ID로 소비한다. FID entity/repository, Firebase
sender와 FID controller는 internal이다. Provider failure handling도 이 module이 소유한다.

## Persistence와 transaction 경계

- Entity와 repository는 owning module의 `internal` package에 둔다.
- Cross-module 관계는 JPA association 대신 scalar ID와 public port로 표현한다.
- Table owner와 constraint는 [data model](../domain/data-model.md)에 고정한다.
- Relationship score와 diary entry/comment는 module-internal JPA `@Version`으로 겹친
  transaction을 감지한다.
- Relationship/diary write는 owned row, media mutation과 event publication을 한 transaction에
  둔다.
- `MediaAttachmentMutation`은 caller transaction이 없으면 실행하지 않는다.
- Media complete/discard/attach/replace만 single-use 상태와 object side effect 때문에
  pessimistic row lock을 사용한다.
- Spring Modulith publication registry는 producer transaction에 참여하고 listener는 commit
  뒤 별도 transaction에서 provider side effect를 수행한다.

Object deletion은 DB commit 뒤 best effort다. 삭제 실패 때문에 committed business state를
되돌리지 않는다.

## 금지되는 우회

- Module 밖 entity, repository 또는 `internal` package import
- Producer에서 notification service나 Firebase 직접 호출
- Consumer 편의를 위한 broad service/repository 공개
- Generic utility package를 통한 dependency 우회
- Custom outbox, delivery ledger, cleanup scheduler, lease나 business CAS state machine 도입
- 근거 없이 `allowedDependencies`를 넓혀 구조 검사를 통과시키는 변경

## 변경 검증

```bash
cd backend
./gradlew test --tests 'com.woorisai.ModularityTests'
./gradlew test
./gradlew postgresTest
```

Public type, event shape, listener ID 또는 `package-info.java`를 바꾸면 direct import graph,
outstanding event compatibility와 transaction boundary를 함께 검토한다.
