# 시스템 아키텍처

우리사이는 정확히 두 사람이 관계 점수, 댓글, 공유 일기와 비공개 미디어를 나누는 작은
private application이다. 이 제품 조건에 맞춰 backend는 하나의 modular monolith로 유지하고,
iOS는 native client로 제공한다. 분산 시스템의 복구 복잡도보다 명확한 소유권과 단일 DB
transaction을 우선한다.

이 문서는 repository와 deployable, persistence와 외부 provider를 가로지르는 선택 근거를
소유한다. 세부 의존 방향은 [module 경계](module-boundaries.md), client 선택은
[iOS 아키텍처](ios-architecture.md), 공개 wire는 [API 계약 안내](../../contracts/README.md),
제품·동시성 규칙은 [도메인 불변식](../domain/invariants.md)이 소유한다.

## 시스템 경계

```text
SwiftUI iOS
  |-- HTTPS + per-request Basic --> Spring Boot API
  |-- short-lived presigned PUT/GET --> private R2 bucket
  `-- APNs notification <-- Firebase FCM <-- notification listener

Spring Boot API
  |-- JPA/Flyway --> PostgreSQL schema woorisai
  |-- S3-compatible SDK --> Cloudflare R2
  `-- Firebase Admin SDK --> FCM
```

Spring과 PostgreSQL `woorisai` schema가 business data의 owner다. Application은 다른 schema나
별도 writer를 정상 동작의 전제로 삼지 않는다. R2는 object bytes, PostgreSQL은 attachment
metadata와 business 연결의 정본이다.

## 선택과 근거

| 영역 | 선택 | 근거 |
| --- | --- | --- |
| Repository | Backend, iOS와 OpenAPI를 함께 두는 monorepo | 한 사용자 기능의 계약과 양쪽 구현을 같은 변경에서 검토한다. |
| Backend | Java, Spring Boot MVC/Security/Data JPA | 작은 팀이 하나의 deployable과 transaction 경계를 운영하기 쉽다. |
| Module | Spring Modulith package module | 독립 service 비용 없이 소유권과 dependency 방향을 검증한다. |
| Database | PostgreSQL + Flyway, Hibernate validate-only | DDL을 versioned migration 한 곳에서 관리하고 production dialect를 직접 검증한다. |
| API | OpenAPI 3.1 + Problem Detail | Backend와 iOS가 같은 wire contract를 따른다. |
| Client | SwiftUI + Swift OpenAPI Generator + URLSession | Apple platform 기능과 signing/push/media lifecycle을 native하게 다룬다. |
| Media | Private R2 + presigned URL | 큰 payload가 API process를 통과하지 않으면서 object는 공개되지 않는다. |
| Push | Spring Modulith publication registry + Firebase | 핵심 write와 event 기록은 원자적으로 하고 provider side effect는 commit 뒤 처리한다. |
| Deploy | Railway API + PostgreSQL | API와 DB만 운영하고 별도 worker/scheduler를 두지 않는다. |

WebFlux, Kafka, Redis, Spring Session, OAuth server, Android/PWA와 별도 worker service는 제품
요구가 생기기 전에는 추가하지 않는다.

## Repository와 deployable 경계

`backend/`, `apps/ios/`, `contracts/`와 `docs/`는 하나의 repository에 두되 backend와 iOS의
build·release는 독립적으로 수행한다. 이렇게 하면 OpenAPI 변경의 server/client 영향을 한
diff에서 검토하면서도 두 artifact를 항상 함께 배포하지 않아도 된다.

Backend는 하나의 Spring Boot deployable이고 module은 Java package와 Spring Modulith로
검증한다. 현재 module 크기에서 같은 경계를 Gradle subproject로 다시 표현하거나 service로
분리하면 build 설정, network failure와 분산 transaction 비용만 늘어난다. 대신 공용 계약과
root 설정은 병렬 변경의 충돌 지점이므로 단일 owner가 필요하다.

정확히 두 명이 한 instance를 쓰는 현재 규모에서는 token lifecycle, custom queue/ledger,
cleanup lease와 reconciliation state보다 framework가 관리하는 transaction, migration과 event
publication을 우선한다. 그 대가로 낮은 PIN entropy와 custom cooldown 부재, private media
orphan, notification 중복 가능성을 수용한다. 각 위험의 한계와 재검토 조건은
[보안](../operations/security-and-secrets.md), [media lifecycle](../domain/media-lifecycle.md),
[notification 계약](../domain/notification-contract.md)이 소유한다.

## Backend 구성

Backend는 `participant`, `identity`, `media`, `relationship`, `diary`, `notification` 여섯
module이다. 일반 request는 owning module 안에서
`Controller → Service → Spring Data JPA Repository`로 흐른다.

Module 간 협업은 다음 두 방식만 허용한다.

- 즉시 결과가 필요한 조회·변경은 provider module의 좁은 public port를 호출한다.
- Commit 이후 side effect는 producer가 소유한 past-tense event를 발행한다.

Entity와 repository는 module 밖으로 노출하지 않는다. R2와 Firebase adapter도 각각 `media`,
`notification` 내부에 둔다. 상세 방향은 [module 경계](module-boundaries.md)를 따른다.

## Persistence와 transaction

- Flyway가 `woorisai` schema와 constraint를 소유한다.
- Hibernate는 `ddl-auto=validate`, `default_schema=woorisai`, open-in-view off로 mapping만
  검증한다.
- SQL init과 application-generated DDL은 사용하지 않는다.
- 일반 persistence feedback에는 H2를 사용할 수 있지만 schema, constraint, lock, isolation과
  PostgreSQL dialect 주장은 Testcontainers PostgreSQL로 검증한다.
- Spring Modulith JPA publication registry는 producer transaction 안에서 event publication을
  기록하고 commit 이후 listener를 실행한다.

`woorisai`는 legacy framework table을 baseline한 schema가 아니라 현재 Spring domain을 위한
clean schema다. Django의 명명과 auth/session table을 현재 model에 영구 결합하지 않기 위한
선택이다. 정확히 두 participant의 bounded dataset에는 장기 CDC나 dual-write보다 writer를
멈춘 한 번의 소유권 이전이 단순하고 검증 가능했다. 현재 결과로 legacy schema는 recovery
source가 아니며 copy tool을 다시 실행하지 않는다.

Relationship score와 diary entry/comment는 내부 JPA `@Version`으로 겹친 transaction을
감지한다. API에 persistence version, ETag이나 `If-Match`를 노출하지 않으므로 이미 commit된
화면의 stale write까지 막는 계약은 아니다. Media complete/discard/attach/replace의
`PESSIMISTIC_WRITE`는 single-use upload와 외부 object side effect를 직렬화하기 위한 예외다.

## 요청 흐름

### 인증과 공개 endpoint

`GET /health`와 `GET /api/v2/auth/login-options`만 공개다. 보호 API는 매 요청
`Authorization: Basic`의 `slot:PIN`을 검증하고 canonical participant ID를 domain에 전달한다.
Session, server login/logout과 access token은 없다. 이 단순화는 두 명이 사용하는 private
product라는 현재 조건에 한정되며 public user model로 확장할 때 다시 결정한다.

### 관계와 일기

Score write는 현재 점수, immutable history, optional media 연결과 event publication을 한
transaction에 둔다. Diary entry/comment도 작성자 권한, content, media와 event를 owning
transaction에서 검증한다. Optimistic conflict는 자동 재시도하지 않고 domain-specific 409로
반환해 client가 최신 상태를 다시 읽게 한다.

### 미디어

1. API가 `PENDING` metadata와 짧은 staging PUT URL을 만든다.
2. iOS가 R2에 직접 업로드한다.
3. Complete가 size, content type과 signature를 확인하고 final object로 copy한 뒤 `READY`로
   전환한다.
4. Relationship 또는 diary write가 parentless `READY`를 자신의 transaction에서 연결한다.
5. Parented `READY`만 attachment와 download URL로 노출한다.

자동 cleanup state machine은 두지 않는다. Object delete는 DB commit 뒤 best effort이며,
orphan이 실제 운영 문제로 확인되면 별도 정책과 권한 모델을 설계한다.

### 알림

Relationship/diary event는 recipient와 route resource ID만 담는다. Listener는 commit 뒤
Firebase에 generic payload를 보내고 형식이 잘못 저장됐거나 provider가 `UNREGISTERED`로 확인한
FID만 제거한다. 그 밖의 provider failure는 privacy-safe category로 관찰하고 official
publication을 outstanding으로 남긴다. Custom queue나 per-device delivery ledger는 현재 작은
fan-out에 비해 복잡도가 크므로 두지 않는다.

## 공개 계약과 운영 경계

- 공개 계약의 관리 원칙은 [API 계약 안내](../../contracts/README.md), wire contract의 정본은
  [OpenAPI](../../contracts/openapi-v2.yaml)다.
- Domain 규칙은 [불변식](../domain/invariants.md)과 각 domain 문서가 소유한다.
- Production topology, health와 recovery는 [Railway 운영](../operations/railway.md)이 소유한다.
- Credential과 private data 취급은 [보안 문서](../operations/security-and-secrets.md)가
  소유한다.
- iOS binary의 검증과 승격은 [iOS release runbook](../operations/ios-release.md)이 소유한다.

## 결정이 필요한 확장

다음 요구는 기존 구조에 암묵적으로 덧붙이지 않고 해당 영역의 정본에 선택 근거, 비용과 실패
의미를 먼저 정리한다.

- 참가자 수 확대나 public account model
- Module별 독립 팀·배포·확장, 규제 격리 또는 monorepo/build 병목
- Wire-level stale-write 보호 또는 offline merge
- Durable media cleanup/reconciliation
- Per-target notification retry, poison isolation이나 broker
- Online schema transition, CDC 또는 dual-write
- Web/Android client와 cookie/session 인증
