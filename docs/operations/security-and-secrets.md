# 보안과 비밀 관리

우리사이는 정확히 두 사람이 사용하는 private application이고 네 자리 PIN 기반 Basic 인증을
의도적으로 선택한다. 이는 낮은 사용자 수와 단순한 운영을 위한 제한된 threat model이지 공개
사용자 인증의 일반 해법이 아니다. 사용자 범위가 넓어지면 account recovery, brute-force 방어,
rate limiting과 session/token 전략을 이 문서와 API·시스템 아키텍처에서 다시 설계한다.

전체 backend 경계는 [시스템 아키텍처](../architecture/system-architecture.md), client 경계는
[iOS architecture](../architecture/ios-architecture.md)를 따른다.

## 비밀과 민감 정보

다음 값은 source, fixture, screenshot, issue, 문서, shell history, build artifact와 일반 log에
넣지 않는다.

- Participant PIN 원문과 PIN hash
- PostgreSQL URL, username과 password
- R2 endpoint/bucket identifier, access key/secret, object key와 presigned URL
- Firebase Admin/service account, FID, provider message/error identifier와 APNs private key/token
- Railway/API token과 실제 environment value
- Signing key, certificate password와 실제 `.env`
- Production backup과 private user content

Firebase Apple client plist는 app이 Firebase project를 찾기 위한 배포 가능한 client
configuration이며 Firebase Admin service account와 구분한다. Bundle에는 필요할 수 있지만 source,
일반 log와 문서에는 넣지 않고 protected release input으로 주입한다. Release archive는 별도
관리한 realm digest와 bundle ID가 일치할 때만 이를 포함한다. Server service account와 APNs
private key는 app bundle에 절대 넣지 않는다.

문서에는 variable 이름과 명백한 placeholder만 기록한다. Secret rotation은 owner, 영향,
rollback과 확인 절차를 가진 별도 승인 작업이다.

## Env와 CI secret 경계

Backend와 iOS는 각각 ignored `.env.local`과 `.env.production`을 local operator 입력으로 사용할 수
있다. 실제 파일은 mode `0600`으로 유지하고 backup, password manager 또는 provider secret store의
대체 정본으로 간주하지 않는다. Commit되는 `.env.local.example`/`.env.production.example`에는 key
이름, 설명과 안전한 placeholder만 둔다.

- Backend production runtime 값의 정본은 Railway variable/secret store다.
- iOS `.env.production`은 production API host, Firebase Apple plist와 App Store Connect API key의
  보호된 파일 경로 및 realm assertion을 가진다. PIN, Firebase Admin service account, APNs private
  key와 Railway token을 넣지 않는다.
- GitHub TestFlight job은 protected input을 runner 임시 directory에 mode `0600`으로 복원하고 종료
  시 삭제한다. PR workflow에는 production secret을 전달하지 않는다.
- Dotenv는 shell code가 아니다. Allowlist validator로 읽고 `source`/`eval`하지 않으며 unknown,
  duplicate와 malformed key를 거부한다.
- CI repository hygiene는 high-risk tracked filename, private-key/token signature,
  `pull_request_target`과 unpinned external action을 차단한다. 검사는 matching value나 line을 log에
  출력하지 않는다.

Repository visibility는 secret store의 대체 수단이 아니다. Product access가 private여도 source
repository는 public이므로 tracked content, public ref와 GitHub Actions log는 누구나 볼 수 있다고
가정한다. Public history는 secret-scanned current tree에서 시작하고 이전 private history ref를
push하지 않는다. 새 ref를 게시하기 전 high-risk filename과 secret signature를 검사하며, 의심
credential이 발견되면 공개보다 rotation과 history 격리를 먼저 수행한다.

## Basic authentication

- 보호 API는 HTTPS의 매 요청 `Authorization: Basic`을 검증한다.
- Username은 participant slot `1` 또는 `2`, password는 ASCII 숫자 네 자리 PIN이다.
- Basic encoding은 암호화가 아니므로 edge에서 application까지 TLS trust boundary를 검증하고
  HTTP origin을 제공하지 않는다.
- Server는 `participant_credential.pin_hash`만 저장하고 Spring `DelegatingPasswordEncoder`의
  `{bcrypt}` 형식을 사용한다.
- PIN을 body, query, URL, metric label, trace baggage와 SecurityContext에 복제하지 않는다.
- Invalid slot/PIN은 participant 존재를 구분하지 않는 같은 401 Problem이다.
- Canonical pair나 credential store failure는 mismatch로 감추지 않고 generic 503이다.
- `GET /health`, `GET /api/v2/auth/login-options`만 공개한다.
- Login options는 slot/display name만 반환하고 participant PK나 credential 상태를 노출하지
  않는다.

Server login/logout, PIN 변경/reset, access/refresh token과 custom rate bucket endpoint는 없다.
PIN hash 입력이나 교체는 build/startup/deploy에 섞지 않고 승인된 production data operation으로
수행한다.

## HTTP와 Spring Security

- Security는 stateless이며 server session, request cache, form login/logout을 사용하지 않는다.
- Cookie auth가 없으므로 API CSRF는 비활성화한다. Web/cookie client를 추가하려면 CORS/CSRF
  threat review를 먼저 수행한다.
- Public 두 GET 외 `/api/v2/**`는 authenticated participant를 요구하고 다른 path는 deny한다.
- Actuator는 health만 expose한다.
- Authentication/authorization response는 `Cache-Control: no-store`이고 internal exception,
  SQL과 provider detail을 노출하지 않는다.
- Unknown JSON field, unsafe scalar coercion과 잘못된 content type을 거부한다.
- Proxy와 application access log에서 Authorization, Cookie와 presigned query를 수집하지 않거나
  redact한다.
- URLSession은 Basic header를 다른 host, redirect target이나 R2 URL에 전달하지 않는다.

## iOS credential과 local privacy

- Slot/PIN은 process memory에서 Basic header를 만들 때만 사용한다.
- 지속 저장 요구가 승인되면 device-only, non-synchronizing Keychain을 사용하고
  UserDefaults/file/cache에는 넣지 않는다.
- Screenshot, pasteboard, analytics, crash report와 UI test artifact에 실제 PIN을 넣지 않는다.
- Local sign-out은 credential, private cache와 navigation state를 지우는 client action이다.
- FID unregister는 credential 삭제 전에 제한시간 내 best effort로 수행하지만 실패가 local
  credential 삭제를 영구 차단하지 않는다.
- Realm 전환은 진행 upload/FID를 정리하고 credential/cache namespace를 분리한다.
- App이 inactive/background가 되면 private detail과 preview를 neutral privacy cover로 가린다.

## Media

- R2 bucket은 public access를 끄고 application principal에 필요한 private object action만 준다.
- Server가 UUID 기반 key를 만들며 filename을 object key로 사용하지 않는다.
- Presigned URL은 짧고 `Cache-Control: no-store`이며 URL/query/header를 log와 telemetry에서
  제외한다.
- Presigned PUT에는 지정 content type/size만 보내고 API Basic header를 보내지 않는다.
- Initiate와 complete에서 kind/content type/size를 검증하고 object signature도 검사한다.
- R2 configuration object를 logger에 전달하지 않고 public error에서 endpoint, bucket, key와
  credential을 숨긴다.
- Best-effort delete failure는 private orphan으로 남을 수 있다. Public fallback을 만들거나
  committed business write를 rollback하지 않는다.
- Automatic cleanup을 이유로 runtime에 broad list/delete permission을 추가하지 않는다.

## Notification privacy

- Push title/body/data에 participant, slot, score, reason, 사용자 content, filename, media URL을
  넣지 않는다.
- Payload는 generic body와 route용 `eventType`/`resourceId`만 가진다.
- FID, service account, provider message/error detail을 일반 log와 public error에 넣지 않는다.
- Invalid FID 삭제와 upsert는 raw FID를 message나 metric에 남기지 않는다.
- App은 route ID를 신뢰하지 않고 Basic API로 resource와 권한을 다시 확인한다.
- Provider 실패는 핵심 write를 rollback하지 않으며 outstanding publication에도 사용자 본문을
  추가 저장하지 않는다.

## Logging과 관찰성

허용되는 log는 stable event/failure category, 필요 최소한의 internal aggregate ID, correlation
ID와 count다. 다음 값은 message, structured field와 metric label에 넣지 않는다.

- Authorization/Cookie와 PIN
- 사용자 content와 reason
- Filename, object key와 presigned URL
- FID, Firebase/APNs target과 provider response
- DB URL, credential와 raw SQL parameter

DTO의 `toString()`은 보안 경계가 아니다. Production에서 request/response value TRACE를 켜지
않고 logger에 request/response, credential, provider configuration 객체를 직접 넘기지 않는다.
Tracing exporter가 header/body/query를 자동 수집하지 않는지 배포마다 확인한다. Public Problem과
internal stack trace를 분리한다.

## 운영 원칙

- Production migration, PIN 변경, backfill/reconcile, secret rotation과 deploy는 대상, backup,
  rollback과 owner를 확인한 승인 작업이다.
- Staging/review는 synthetic data와 production과 분리한 DB/R2/Firebase credential을 사용한다.
- Backup은 암호화하고 최소 권한, 접근 audit, retention과 restore verification을 갖춘다.
- Secret이나 presigned URL 노출이 의심되면 값을 응답이나 문서에 재출력하지 않고 즉시
  revoke/rotate와 log retention 범위를 결정한다.
- Credential은 최소 권한으로 발급하고 environment와 provider 사이에 공유하지 않는다.
