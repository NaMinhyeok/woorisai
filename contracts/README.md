# API 계약

Spring backend와 SwiftUI iOS 앱의 공개 wire contract 정본은
[`openapi-v2.yaml`](openapi-v2.yaml)이다. OpenAPI 3.1을 사용하며 Spring controller와 iOS
adapter가 구현할 operation을 기술한다.

## 선택 근거

Spring backend와 native iOS client를 독립적으로 구현하면서도 인증, 권한, 오류와 domain 의미를
함께 검토하려면 server framework type과 분리된 계약이 필요하다. 그래서 Django의 browser
session/envelope를 복제하거나 server code에서 schema를 사후 생성하지 않고, 사람이 검토할 수
있는 OpenAPI를 먼저 정본으로 둔다. 현재처럼 고정된 business operation과 하나의 client가 있는
규모에서는 GraphQL의 별도 schema/runtime/cache 복잡성도 이점보다 크다.

Contract-first 방식은 backend와 iOS의 drift를 일찍 드러내는 대신 공개 schema 변경 때 server
conformance와 generated client 호환성을 함께 검토해야 한다. `/api/v2` prefix는 wire 경계를
명시하지만, 동시에 지원하는 app version이 늘면 prefix만으로 호환 기간을 해결할 수 없다.

## 인증 경계

정확히 두 operation만 public이다.

- `GET /health`
- `GET /api/v2/auth/login-options`

그 밖의 모든 `/api/v2/**` operation은 다음 HTTP Basic credential을 매 요청 검증한다.

```text
Authorization: Basic base64("<slot>:<4-digit PIN>")
```

Slot은 `1` 또는 `2`이고 PIN은 ASCII 숫자 네 자리다. Login/logout, access·refresh token,
session, rate bucket, credential bootstrap과 PIN 변경 operation은 계약에 없다.

`login-options`는 PIN 입력 전에 participant slot을 선택해야 하므로 public이다. 응답은 정확한
두 slot의 `slot`과 `displayName`만 노출하고 participant 구성이 불완전하면 임의 보정 없이
service unavailable로 실패한다. 이 조회는 인증 성공을 뜻하지 않으며 첫 보호 요청이 실제 PIN을
검증한다.

## Operation 묶음

| Tag | Operation |
| --- | --- |
| Operations | database-backed health |
| Identity | canonical login options |
| Media | initiate, complete, discard, attached download URL |
| Relationship | score pair, history, score change, thread, comment create |
| Diary | entry list/create/detail/update/delete, comment create/update/delete |
| Notification | FID register/unregister |

정확한 method, path, request/response와 상태는 OpenAPI file만 정본으로 관리한다.

## 계약 원칙

- 공개 JSON field는 camelCase이고 unknown request field와 암묵적 scalar coercion을 거절한다.
- 모든 operation에 안정적인 `operationId`와 명시적 success/Problem Detail response를 둔다.
- 보호 operation은 global `BasicAuth` requirement를 상속하고 public GET만 `security: []`로
  해제한다.
- 인증·business response와 presigned URL response는 `Cache-Control: no-store`다.
- Identifier는 실제 bigint/UUID에 맞춰 `int64` 또는 `uuid`로 표현한다.
- Actor와 작성자는 request body가 아니라 검증된 Basic principal에서 결정한다.
- Create operation은 idempotency key를 제공하지 않는다. Relationship/diary mutation은 transport
  failure나 409에서 자동 재시도하지 않고 최신 resource를 다시 읽는다.
- Media initiate는 새 `PENDING` intent를 만드는 non-idempotent operation이다. Complete는 이미
  `READY`인 같은 upload의 결과를 재생하고 discard와 FID unregister는 absent row에도 성공한다.
- Generated OpenAPI type은 iOS API adapter 밖으로 노출하지 않는다.
- Swift OpenAPI generator가 object-level `oneOf`/`anyOf`와 일부 부정 제약을 안정적으로
  모델링하지 못하므로, 다음 교차 field 불변식은 schema description과 server command
  validation을 정본으로 삼는다: score 변경의 `delta`/`targetScore` 정확히 하나와 non-zero
  `delta`, score comment의 content-or-media, diary update의 non-empty patch. Backend HTTP test와
  iOS app-owned request validation으로 이 경계를 함께 검증한다.

## 검증

```bash
cd backend
./gradlew openApiValidate
./gradlew check
```

iOS generator는 OpenAPI에 포함된 operation을 생성한다. 앱은 generated type을 API adapter
내부에 격리하고, same-origin HTTPS 요청에만 memory-only Basic credential을 주입하며, public
operation과 redirect에서는 Authorization을 제거한다. 각 business 화면의 연결·device 검증은
[iOS release runbook](../docs/operations/ios-release.md)의 반복 가능한 gate로 확인한다.

## 재검토 조건

동시에 지원할 app version이나 외부 client가 늘어나면 호환 기간, deprecation과 API versioning
정책을 이 문서와 OpenAPI에 함께 정한다. 오래된 화면의 덮어쓰기가 실제 제품 문제로 확인되면
ETag, `If-Match` 또는 domain revision을 client UX와 함께 검토한다.
