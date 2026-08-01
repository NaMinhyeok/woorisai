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

### 예외: `support` 기술 지원 module

`support`는 business module이 아니라 기술 지원 module이다. Business module 목록
(`identity`, `participant`, `relationship`, `diary`, `media`, `notification`)에 포함되지 않고
domain 상태나 business 규칙을 소유하지 않는다.

**문제.** 어느 business module도 소유하지 않으면서 모든 module이 같은 모양으로 지켜야 하는
HTTP 표현 계약이 있다. Module마다 조립을 두면 코드가 module 수만큼 복제되고 계약이 조용히
갈라진다.

- 오류 응답은 RFC 7807 `ProblemDetail`에 `status`, `title`, `detail`, `instance`와 `errorCode`를
  실어 `application/problem+json` + `Cache-Control: no-store`로 반환한다.
- 페이지 응답은 `{ results, paging }`이며 `paging`은 `pageNumber`, `pageSize`, `hasNext`,
  `totalCount`다. 한쪽만 평평하게 두면 client가 페이징을 두 벌로 해석해야 한다.

**선택.** 표현 계약만 `support`에 두고 module은 자신의 오류 의미와 결과 type만 소유한다.
`support`는 다음 세 장치로 우회 통로가 되는 것을 구조적으로 막는다.

- `allowedDependencies = {}` — `support`는 어떤 business module도 참조할 수 없다.
  경유 참조가 성립하지 않는다.
- `@NamedInterface` — 노출 package만 공개하고 나머지 하위 package는 비공개다.
- 사용 module의 `allowedDependencies = {"support::<interface>"}` — 암묵적 전역 접근이 아니라
  module별 명시 opt-in이다.

세 장치는 `com.woorisai.ModularityTests`가 build 시점에 검증한다.

현재 노출 interface는 `support::error`와 `support::paging` 둘이다. `support::paging`의
`PageResponse<T>`와 `Paging`은 결과 type을 모르는 봉투이며 business 규칙을 담지 않는다.
Page 크기는 각 service가 자신의 상수로 정하고 `Paging`은 그 결과를 전달만 한다. Diary와 score
이력이 지금 같은 값을 쓰는 것은 우연이므로 공용 상수로 묶지 않는다.

**대안과 trade-off.** Module마다 handler를 유지하면 `support` 없이도 경계가 가장 좁지만
동일한 조립 코드가 복제되고 계약 drift를 test로만 막는다. 반대로 root package에 utility를
두면 module 선언 없이 전역 접근이 열려 `allowedDependencies` 검사를 우회한다. `support`는
공유 범위를 명시 선언으로 좁히는 중간 선택이며, 대가는 module 목록에 business가 아닌
항목이 하나 늘어나는 것이다.

**금지.** Business 지식, domain 규칙, entity, module 간 참조를 `support`에 두지 않는다.
Module 하나만 쓰는 코드를 `support`로 올리지 않는다. `support`가 business module을
참조해야 하는 상황은 경계 설계가 틀렸다는 신호다.

**재검토 조건.** `support`의 `allowedDependencies`를 비울 수 없게 되거나, `@NamedInterface`가
아닌 경로로 접근이 필요해지거나, 노출 interface가 계속 늘어나면 이 선택을 다시 판단한다.

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
- Generic utility package를 통한 dependency 우회 (`support`는 `allowedDependencies = {}`와
  `@NamedInterface`로 이 우회가 불가능하다)
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
