# 검증 매트릭스

- 상태: 적용

검증 범위는 과거 구현 Phase가 아니라 현재 변경이 만드는 위험으로 선택한다. 테스트 개수나
명령 실행 자체보다 공개 동작, 데이터 불변식과 실패 의미를 실제 환경에 맞게 증명하는 것이
목적이다. 실행하지 못한 gate는 성공으로 간주하지 않고 이유와 남은 위험을 보고한다.

## Gate

| Gate | 검증 대상 | 대표 증거 |
| --- | --- | --- |
| G0 | 범위, 결정과 문서 일관성 | 설계 근거·계약·코드 대조, 내부 link, 비목표 확인 |
| G1 | 정적 품질과 build 가능성 | format/lint/static analysis, compile, artifact 생성 |
| G2 | Domain·application·portable persistence 동작 | public seam의 unit/module/H2 test, rollback과 오류 의미 |
| G3 | 공개 API와 보안 경계 | OpenAPI validation, HTTP black-box, 인증·권한·redaction |
| G4 | PostgreSQL 고유 의미 | Flyway, schema/constraint/sequence, lock/isolation/concurrency test |
| G5 | iOS 소비 계약과 앱 동작 | generated client, Swift test, simulator/device, Release build |
| G6 | 운영·외부 provider·복구 | config/startup/readiness, R2/FCM smoke, deploy/rollback/restore |
| G7 | 최종 통합 안전성 | 전체 diff, secret·불필요 생성물, 독립 검토와 미검증 공백 |

G0과 G7은 모든 변경에 적용한다. G1~G6은 아래 위험 범주에서 선택하며, 하나의 변경이 여러
범주에 걸치면 gate를 합친다.

## 위험 범주별 최소 검증

| 변경 위험 | 최소 Gate | 반드시 확인할 내용 |
| --- | --- | --- |
| 문서·결정 | G0, G7 | 현재 정본과 근거, 내부 link, 상충 또는 실행 기록성 서술, diff |
| Domain 규칙·module 경계 | G1, G2, G7 | 불변식 경계값, 공개 application seam, `ApplicationModules.verify()`, 의존 방향 |
| OpenAPI 또는 HTTP | G0, G1, G3, G7 | breaking 여부, strict request/response/status, server conformance, 오류 계약 |
| 인증·권한·private data | G1, G3, G6, G7 | 401/403, actor ownership, no session/cookie, header·payload·log redaction |
| 일반 JPA mapping/query | G1, G2, G7 | H2 mapping과 공개 조회/명령 동작, transaction rollback |
| Flyway·schema·PostgreSQL SQL | G0, G1, G2, G4, G6, G7 | fresh V1→current migrate, JPA validate, constraint/FK/sequence, 재실행 no-op |
| Transaction·lock·동시성 | G1, G2, G4, G7 | one-winner/failure 의미, 전체 rollback, isolation과 실제 겹친 transaction |
| R2·Firebase adapter | G1, G2, G6, G7 | deterministic provider-shaped test, timeout/failure 분류, 실제 smoke 공백 |
| Notification | G1, G2, G4, G6, G7 | commit 이후 처리, publication 복구, 중복·재시도, privacy-safe payload |
| iOS feature 또는 client | G1, G3, G5, G7 | app model 경계, state/error/cancel, 두 지원 화면, accessibility와 Release build |
| OpenAPI의 backend+iOS 변경 | G0, G1, G3, G5, G7 | breaking diff, server conformance, client 재생성·compile과 앱 소비 |
| Railway·runtime config | G0, G1, G3, G4, G6, G7 | Java/runtime image, `PORT`, startup Flyway+JPA validate, `/health`, env fail-fast |
| Production data·destructive 작업 | G0~G7 중 영향 범위 전체 | 명시적 승인, exact target, encrypted backup·restore, owner/writer, post-check·복구 |

## 환경 선택 원칙

- DB가 필요 없는 정책은 가장 낮은 안정된 public application seam의 deterministic test로
  검증한다.
- 일반 persistence는 H2를 사용할 수 있지만 PostgreSQL schema, dialect, constraint, sequence,
  lock, isolation과 concurrency 의미는 PostgreSQL Testcontainers로 검증한다.
- Docker가 없을 때 G4 test를 H2로 대체하거나 skip하지 않는다. 실행하지 못한 G4로 보고한다.
- 동시성은 순차 호출이나 mock으로 대체하지 않고 실제로 겹친 transaction을 만든다.
- DB 직접 조회는 persisted outcome과 schema를 증명할 때만 사용한다. 공개 동작 검증의
  시작점은 HTTP 또는 module public API다.
- R2와 Firebase는 deterministic adapter test와 실제 provider smoke를 구분한다. Credential이
  없거나 운영 승인이 없으면 smoke를 생략한 이유와 위험을 남긴다.
- 실제 device가 필요한 signing, APNs와 foreground/background lifecycle은 simulator로
  증명하지 않는다.
- UI는 accessibility/state assertion과 framebuffer 검토를 구분한다.
- Production write, migration, deploy, data copy와 object 삭제는 build나 일반 test에 섞지
  않고 별도 승인·복구 절차로 실행한다.

## 현재 표준 명령

변경 위험에 필요한 명령만 실행하되 `check`가 개별 결과의 의미를 대신하지 않게 실제 task
결과를 확인한다.

```bash
# Backend
cd backend && ./gradlew compileJava
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

## 완료 판단

완료 보고에는 선택한 gate와 위험의 대응 관계, 실제 명령·결과, 검증이 증명한 범위,
실패·skip과 환경 공백을 함께 적는다. 현재 코드와 계약에서 다시 확인할 수 없는 과거 실행
결과를 완료 근거로 사용하지 않는다. 결과 양식은 [작업 정의 및 완료 보고](work-template.md)를
사용한다.
