# 에이전트 작업 계약

이 저장소의 목표는 정확히 두 명이 사용하는 private Spring API와 SwiftUI iOS 앱을 안전하게
유지하는 것이다. 작업 기록을 늘리는 것보다 현재 공개 계약, 도메인 불변식과 운영 경계를
작은 변경으로 보존하는 것을 우선한다.

## 먼저 읽을 것

- 모든 작업: `README.md`, `git status`, `docs/README.md`, 변경 대상과 인접 test
- Backend 구조: `docs/architecture/system-architecture.md`,
  `docs/architecture/module-boundaries.md`
- 동시성: `docs/domain/invariants.md`, `docs/domain/data-model.md`,
  `docs/domain/media-lifecycle.md`
- Domain/DB: `docs/domain/invariants.md`, `docs/domain/data-model.md`, 적용된 Flyway
- API: `contracts/README.md`, `contracts/openapi-v2.yaml`
- iOS: `docs/architecture/ios-architecture.md`, `docs/operations/ios-release.md`
- Media/notification: `docs/domain/media-lifecycle.md`, `docs/domain/notification-contract.md`
- 배포·보안: `docs/operations/railway.md`, `docs/operations/security-and-secrets.md`
- 협업·검증: `docs/agent/strategy.md`, `docs/agent/work-template.md`,
  `docs/agent/verification-matrix.md`

문서만으로 동작을 추측하지 않는다. Code, migration, OpenAPI와 test가 다르면 실행 가능한 계약을
확인하고 같은 변경에서 canonical 문서를 고친다.

## Repository 경계

- `backend/`: 하나의 Spring Boot application. Module은 Gradle subproject가 아니라 Java package다.
- `apps/ios/`: SwiftUI app. Generated OpenAPI type은 API adapter 밖으로 노출하지 않는다.
- `contracts/`: backend와 iOS가 함께 따르는 공개 wire 계약.
- `docs/`: 현재 결정 근거, 현재 계약과 반복 가능한 runbook.

Business module은 `identity`, `participant`, `relationship`, `diary`, `media`,
`notification`이다. Module 간 참조는 scalar ID, provider가 소유한 공개 interface 또는
past-tense event만 사용한다. `shared`, `common`, `infrastructure`, 별도 `operations` business
module을 우회 통로로 만들지 않는다.

## 반드시 보존할 계약

- Participant는 slot 1과 2의 정확히 두 명이다.
- Relationship score는 방향성이 있고 0~100이며 participant는 자신의 outgoing score만 바꾼다.
- Score 현재값, 불변 이력, media 연결과 event publication은 한 transaction이다.
- Score comment와 diary comment는 두 participant의 평평한 시간순 대화다.
- Diary는 두 participant가 읽고 작성자만 수정·삭제한다. 게시 시각은 server가 결정한다.
- `relationship_score`, `diary_entry`, `diary_entry_comment`의 겹친 transaction은 JPA
  `@Version`으로 감지하고 각각 `409 RELATIONSHIP_CONFLICT`, `409 DIARY_CONFLICT`로 반환한다.
- API에 persistence version, ETag과 `If-Match`를 노출하지 않는다. 이미 commit된 변경보다
  오래된 화면 수정은 현재 optimistic contract가 감지하지 못한다.
- Media purpose/kind/size/owner/status와 attachment cardinality를 보존한다. Complete/discard/
  attach/replace의 `PESSIMISTIC_WRITE`는 single-use upload와 R2 side effect를 직렬화하는 예외다.
- Push는 commit 이후 처리하고 실패가 핵심 write를 rollback하지 않는다. Payload와 lock-screen
  문구에 participant, 점수, 이유, 댓글·일기 본문 또는 media URL을 넣지 않는다.
- `/health`는 Actuator DB readiness이며 DB 장애 시 503을 반환한다.

상세 의미는 `docs/domain/invariants.md`가 정본이다.

## Database와 production 안전

- Production business data의 유일한 owner/writer는 Spring과 PostgreSQL `woorisai` schema다.
- Legacy Django와 `public` data를 runtime, fallback writer 또는 최신 recovery source로 되살리지
  않는다.
- Flyway V1/V2, `hibernate.default_schema=woorisai`, `ddl-auto=validate`를 유지한다.
- 적용된 Flyway migration을 수정·삭제하지 않는다. Schema 변경은 새 forward migration이다.
- One-time cutover copy tool을 production에서 다시 실행하거나 legacy data로 target을 덮어쓰지
  않는다. CDC, incremental sync, dual-write와 production shadow write도 만들지 않는다.
- PostgreSQL schema, constraint, sequence, lock, isolation이나 concurrency 의미는 PostgreSQL
  Testcontainers로 검증한다. Docker가 없을 때 H2로 대체하거나 skip하지 않는다.
- 운영 DB write, migration, backfill, reconcile, restore, deploy와 object 삭제는 사용자의 명시적
  승인 없이 수행하지 않는다.

## 인증·비밀

- Public endpoint는 `GET /health`와 `GET /api/v2/auth/login-options`뿐이다.
- 나머지 `/api/v2/**`는 stateless `Authorization: Basic`의 `slot:4자리 PIN`을 매 요청 검증한다.
- Cookie/session, access/refresh token, login/logout, custom rate bucket, credential bootstrap과
  PIN 변경 endpoint를 추가하지 않는다.
- PIN 원문, password/hash dump, DB URL, R2 key, Firebase service account, APNs key, 실제 `.env`,
  FID와 presigned URL을 열거나 출력하거나 문서·fixture·log·Git에 넣지 않는다.
- HTTPS, Authorization redaction, 권한·입력 제한과 `Cache-Control: no-store`를 유지한다.
- 외부 I/O는 owning module의 adapter 뒤에 두고 deterministic test double과 실제 provider
  smoke를 구분한다.

## 작업 방식

1. 요청을 관찰 가능한 동작, 보존할 불변식, 비목표와 exit criteria로 바꾼다.
2. 한 작업은 하나의 module 또는 하나의 schema/API 경계를 주로 소유한다.
3. OpenAPI, migration, root build 설정, Xcode project와 공용 문서는 한 시점에 한 owner만
   수정한다.
4. 구현 전 가장 낮은 안정된 공개 경계에서 누락된 계약을 test로 만든다. Framework 기본 동작만
   구성하는 scaffold에는 의미 없는 test를 추가하지 않는다.
5. 관련 없는 refactor, dependency와 schema 변경을 같은 작업에 섞지 않는다.
6. 마지막에 전체 diff를 읽어 데이터 손실, 비밀 노출, 누락 migration, API drift와 불필요한
   생성물을 확인한다.
7. 실제 실행한 검사와 실패·skip·검증 공백만 보고한다.

작업 packet과 종료 보고는 `docs/agent/work-template.md`의 항목을 사용하되, 일회성 task/handoff
Markdown 파일을 repository에 쌓지 않는다. 장기 보존이 필요한 선택은 그 영역을 소유하는
architecture/domain/contract/runbook에 반영하고, 실행 결과는 PR/CI/외부 operator record에 둔다.

## 검증 진입점

```bash
# backend
cd backend && ./gradlew test
cd backend && ./gradlew postgresTest
cd backend && ./gradlew openApiValidate
cd backend && ./gradlew bootJar
cd backend && ./gradlew check

# iOS
cd apps/ios && xcodebuild test -project Woorisai.xcodeproj -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=26.5' \
  -skipPackagePluginValidation
cd apps/ios && xcodebuild test -project Woorisai.xcodeproj -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro,OS=26.5' \
  -skipPackagePluginValidation
cd apps/ios && xcodebuild build -project Woorisai.xcodeproj -scheme Woorisai \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation
```

Risk별 최소 gate는 `docs/agent/verification-matrix.md`를 따른다. 문서만 바꾼 작업은 내부 링크,
정본 간 모순, 비밀·dynamic execution snapshot 유입 여부와 전체 diff를 검토한다.

## 문서 정책

- Architecture/domain/contract 문서는 현재 구조와 불변식뿐 아니라 자신이 소유하는 선택의
  문제, 이유, 대안, trade-off와 재검토 조건을 함께 설명한다.
- Runbook은 지금 반복할 수 있는 절차, 중단 조건과 recovery 기준만 설명한다.
- 날짜별 진행 상황, commit/deployment ID, row count, phase별 변경 파일과 당시 test 결과를
  canonical 문서에 추가하지 않는다.
- 완료된 실행의 증거는 Git/CI/App Store Connect/Railway/private operator record에서 찾는다.
- 과거 설계를 보존하기 위한 `archive`, 별도 결정 기록 또는 handoff 문서를 새로 만들지 않는다.
- 기존 문서가 소유하지 않는 새 주제만 별도 문서로 만들고 `docs/README.md`에 연결한다.

## 완료 조건

- 요청한 동작과 보존 계약이 code/schema/OpenAPI/test에서 일치한다.
- 필요한 현재 문서만 갱신되고 실행 일지는 추가되지 않았다.
- 관련 검증이 실제로 통과했으며 실행하지 못한 gate와 남은 위험이 보고됐다.
- 요청받지 않은 commit, push, PR, deploy와 운영 data 변경을 하지 않았다.
