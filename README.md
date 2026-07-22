# 우리 사이

정확히 두 명이 함께 쓰는 private iOS application이다. Backend는 Spring Boot modular
monolith, client는 SwiftUI이며 OpenAPI 3.1 계약을 함께 관리한다.

현재 구조와 선택 근거는 영역별 정본이 함께 소유한다.

- [시스템 아키텍처](docs/architecture/system-architecture.md): monorepo, modular monolith,
  clean schema와 운영 복잡도 경계
- [iOS 아키텍처](docs/architecture/ios-architecture.md): native SwiftUI와 client 보안 경계
- [API 계약 안내](contracts/README.md): contract-first API와 인증·오류 의미
- [도메인 불변식](docs/domain/invariants.md): 제품 규칙과 동시성 선택
- [Module 경계](docs/architecture/module-boundaries.md): 상태 소유권과 의존 방향

## 현재 시스템

```text
iOS -- HTTPS + Basic --> Spring Boot API --> PostgreSQL / woorisai
 |                              |                     |
 +------ presigned PUT/GET ----> R2                  +--> event_publication
                                |
                                +--> Firebase FCM --> APNs
```

- Backend는 Java 25, Spring Boot 4.1, Spring Modulith와 Spring Data JPA를 사용한다.
- Flyway가 별도 PostgreSQL `woorisai` schema의 V1/V2를 소유하고 Hibernate는
  `ddl-auto=validate`만 사용한다.
- Production business data의 유일한 owner/writer는 Spring과 `woorisai`다. Legacy Django와
  PostgreSQL `public` data는 runtime 또는 rollback source가 아니다.
- 보호 API는 매 요청 `Authorization: Basic`의 `slot:4자리 PIN`을 검증한다. Session,
  access/refresh token, login/logout과 custom rate bucket은 없다.
- R2 bucket은 private이고 iOS는 API가 발급한 짧은 presigned URL로 직접 전송한다.
- Notification은 privacy-safe domain event를 commit 이후 Firebase FID로 전달한다. 공식
  Spring Modulith publication registry를 사용하며 custom queue/worker는 두지 않는다.
- iOS의 PIN은 process memory에만 유지한다. 영속 저장이 제품 요구가 되면 Keychain 사용을
  별도 결정한다.

## Module 경계

| Module | 책임 | 직접 의존성 |
| --- | --- | --- |
| `participant` | slot 1/2 participant directory | 없음 |
| `identity` | PIN hash와 Basic 인증 | `participant` |
| `media` | upload metadata, R2와 attachment 규칙 | 없음 |
| `relationship` | 방향 점수, 불변 이력과 점수 댓글 | `participant`, `media` |
| `diary` | 공유 일기와 일기 댓글 | `participant`, `media` |
| `notification` | FID와 commit-after notification listener | `relationship`, `diary` |

Module 간에는 scalar ID, provider가 소유한 공개 port와 past-tense event만 사용한다. JPA
association이나 공용 `shared` module로 경계를 우회하지 않는다. 상세 계약은
[module boundary](docs/architecture/module-boundaries.md)에 있다.

## 공개 API

Wire contract의 정본은 [OpenAPI](contracts/openapi-v2.yaml)다. Public endpoint는
`GET /health`와 `GET /api/v2/auth/login-options`뿐이며 나머지 `/api/v2/**`는 Basic 인증이
필요하다. Operation 묶음, 오류와 retry 의미는 [API 계약 안내](contracts/README.md)를 따른다.

Persistence version, ETag과 `If-Match`는 wire에 노출하지 않는다. Relationship/diary의 내부
`@Version`은 겹친 transaction만 감지하며 충돌 loser는 자동 재시도 없이 409를 받는다.
Media complete/discard/attach/replace는 single-use upload와 외부 R2 side effect 때문에
`PESSIMISTIC_WRITE`를 유지한다.

## Repository

```text
woorisai/
├── backend/                 # Spring Boot modular monolith
├── apps/ios/                # SwiftUI app
├── contracts/               # OpenAPI public contract
├── docs/                    # decisions, current contracts and repeatable runbooks
├── AGENTS.md
└── README.md
```

## 검증

```bash
cd backend
./gradlew test
./gradlew postgresTest
./gradlew openApiValidate
./gradlew bootJar
./gradlew check
```

`postgresTest`는 PostgreSQL schema, constraint, dialect와 concurrency 의미를 검증하므로 Docker가
필요하다. Docker가 없을 때 H2로 대체하거나 skip하지 않는다.

iOS의 현재 simulator/build 명령은 [apps/ios/README.md](apps/ios/README.md)에 둔다. 실제 기기의
Basic read/write, R2 media와 Firebase/APNs 검증 및 public release 조건은
[iOS release runbook](docs/operations/ios-release.md)을 따른다.

## CI/CD

- Pull request와 `main`은 GitHub Actions의 repository hygiene, backend/PostgreSQL/container와
  두 iPhone simulator gate를 통과한다.
- Railway production은 GitHub `main`을 source로 사용하고 `Wait for CI` 뒤 root
  `railway.json`/`Dockerfile`을 배포한다.
- iOS는 검증된 `main` revision만 수동 승인형 workflow로 같은 archive를 TestFlight에 올린다.
  App Store 공개 승격은 signed-device와 review gate 뒤 App Store Connect에서 수동으로 수행한다.
- 실제 local/production 값은 backend와 iOS 각각의 ignored `.env.local`/`.env.production`에서
  작업할 수 있고, commit되는 `.example`은 key schema만 소유한다.

구체적인 secret 경계와 반복 절차는 [보안](docs/operations/security-and-secrets.md),
[Railway](docs/operations/railway.md), [iOS release](docs/operations/ios-release.md) runbook을 따른다.

## 문서 원칙

Repository에는 현재 결정 근거, 현재 계약과 반복 가능한 절차만 둔다. Phase별 작업 결과,
deployment ID, row count, 일회성 migration/retirement 실행 기록은 Git/CI/외부 operator record가
보존하며 canonical 문서에 복제하지 않는다. 문서 지도는 [docs/README.md](docs/README.md)다.
