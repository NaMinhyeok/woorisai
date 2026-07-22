# SwiftUI iOS 앱 아키텍처

iOS 앱은 native SwiftUI client이며 공개 API 계약은
[OpenAPI](../../contracts/openapi-v2.yaml)에서 생성한다. Generated transport type을 feature에
퍼뜨리지 않고 인증, privacy와 provider lifecycle을 app-owned adapter에서 통제하는 것이 핵심
원칙이다. API와 인증 의미는 [API 계약 안내](../../contracts/README.md), private data 취급은
[보안 문서](../operations/security-and-secrets.md)를 따른다.

## 선택 근거와 trade-off

지원 대상은 iOS이고 재사용할 web UI가 없다. PhotosPicker, APNs,
foreground/background lifecycle과 credential 취급을 platform API로 직접 다루는 편이 PWA나
JavaScript bridge보다 단순하고 검증 가능하므로 SwiftUI native client를 선택했다. Android
동시 출시 요구가 없는 상태에서 cross-platform framework를 먼저 도입하지 않으며, 현재 화면과
상태 흐름에는 UIKit과 SwiftUI를 함께 운영할 이유도 없다.

Native 선택은 Apple platform 기능을 직접 통제하는 대신 Android client를 자동으로 제공하지
않고 Xcode signing·release 역량을 요구한다. Generated OpenAPI type을 adapter에 가두는 것은
wire 변경의 영향을 한 경계에서 흡수하기 위한 선택이다.

## Layer와 composition

```text
App / Navigation
  -> Feature View + @Observable model
    -> feature-owned protocol/use case
      -> Core/API adapter
        -> generated OpenAPI client + URLSession transport
```

- Generated `Operations`/`Components` type은 `Core/API` 밖의 public signature에 노출하지 않는다.
- Feature는 app이 소유한 immutable model과 error만 사용한다.
- Runtime realm, credential, URLSession transport, media와 Firebase adapter는 composition root에서
  조립한다.
- `project.yml`과 lock된 package version이 project structure와 dependency의 정본이다.
- Generated source와 DerivedData는 repository에 넣거나 손으로 수정하지 않는다.

## 인증

보호 요청은 선택한 slot과 네 자리 PIN으로 매번 다음 header를 만든다.

```text
Authorization: Basic base64("<slot>:<4-digit PIN>")
```

- Login options는 표시 선택지일 뿐 identity proof가 아니다. 첫 보호 요청의 2xx/401이 인증
  결과를 결정한다.
- Middleware는 승인된 same-origin HTTPS API host에만 header를 주입한다. Redirect target과
  presigned R2 request에는 전달하지 않는다.
- 401은 local credential을 제거하고 PIN 재입력을 요구한다. Server login/logout call은 없다.
- Credential은 process memory에만 둔다. 지속 보존 요구가 생기면 password credential로
  분류해 device-only, non-synchronizing Keychain 정책을 별도 결정한다.
- Local sign-out은 credential, private cache와 navigation state를 지우는 client 동작이다.

Memory-only credential은 device 저장소 노출 범위를 줄이는 대신 app을 다시 실행할 때마다 PIN을
재입력하게 한다. 현재 두 명이 사용하는 private app에서는 이 불편을 수용한다.

## State와 error

Async feature는 `idle/loading/success/recoverable failure`를 명시하고 model이 network task를
소유한다. 새 request나 화면 종료 시 이전 task를 취소하며 stale response가 최신 state를
덮지 못하게 한다. View가 HTTP status나 generated response를 직접 해석하지 않는다.

Adapter는 `401`, domain `400/403/404/409`, provider/DB `503`을 feature error로 변환한다.
Undocumented response는 success로 추정하지 않는다. Relationship create처럼 wire-level
idempotency가 없는 write는 transport outcome이 불명확하거나 409인 경우 자동 재시도하지 않고
사용자에게 reload/retry를 분리해 제시한다.

## Media

1. API에서 upload URL과 UUID를 받는다.
2. R2에 content type/length를 맞춰 직접 PUT한다.
3. API complete를 호출한다.
4. 완료된 UUID를 relationship/diary write에 전달한다.
5. Parented `READY` metadata와 짧은 download URL로 private preview를 표시한다.

API Basic header는 R2 요청에 보내지 않는다. Presigned URL과 response는 장기 cache하지 않는다.
Upload 취소나 확정 실패에서는 가능한 경우 discard를 호출한다. Parent write 결과가 불명확한
upload는 성공했을 가능성이 있으므로 자동 discard하지 않는다. 성공 응답 뒤에만 local model에서
consume한다.

Private preview는 ephemeral session과 전용 protected temporary directory를 사용한다. Cache
eviction과 인증 session 종료 시 파일을 삭제하고 다음 launch에서 앱이 소유한 directory만
purge한다. Scene이 inactive 또는 background가 되면 neutral privacy cover로 detail과 preview를
가린다.

인증 session마다 하나의 preview store가 download grant 발급부터 R2 GET까지 attachment ID로
합치고 최대 세 건만 동시에 실행한다. Presigned URL은 저장하지 않으며, 성공한 파일만 크기가
제한된 session LRU로 전용 protected directory에서 재사용한다. Video도 전체 `Data`로 올리지
않고 download task의 임시 파일을 이 directory로 옮긴다. Sign-out과 PIN 재입력 전에는 feature
state를 먼저 비우고 새 preview load를 막은 뒤 진행 중 작업, cache와 전용 directory를 모두
정리한다.

## Push와 navigation

Firebase Installation ID는 인증된 participant로 register한다. APNs token 도착과 FID callback은
순서가 고정되지 않으므로 첫 callback과 rotation을 모두 backend reconciliation 신호로 사용한다.
APNs 등록 실패와 Settings 복귀는 provider/권한 상태를 다시 확인하되 FID나 provider detail을
노출하지 않는다. Rotation은 직렬화하고 sign-out이나 participant 변경 전 unregister를 제한시간
내 best effort로 시도한다. 실패를 server logout 성공처럼 표현하지 않으며 credential 삭제를
영구 차단하지 않는다.

Push payload는 generic alert와 `eventType`/`resourceId`만 포함한다. App은 resource ID로 보호
API를 다시 읽고 권한과 존재 여부를 확인한다. Notification body는 source of truth가 아니다.
Foreground 수신은 banner만 표시하고 tap/launch response에서만 navigation intent를 만든다.
Parent write 중 intent는 write 완료 뒤 처리하고 sign-out/재인증 중 intent는 폐기한다.

## Appearance와 text input

App, sheet와 system keyboard는 사용자가 선택한 iOS light/dark appearance를 따른다. Bundle이나
view에서 interface style을 고정하지 않고, warm visual identity는 light/dark 값을 함께 가진
semantic palette로 유지한다. Text, surface, control border, status와 accent는 각 appearance에서
독립적으로 읽을 수 있는 대비를 가져야 하며 system `List`, alert와 privacy cover의 platform
semantic color를 덮어쓰지 않는다.

모든 text input은 `FocusState`로 화면 lifecycle과 제출·취소 시점을 통제한다. Number pad와
multiline editor를 포함한 keyboard에는 명시적인 `완료` 동작을 제공하고, scroll container는
interactive dismissal을 지원한다. Multiline field의 return key는 줄바꿈에 남겨 두므로 keyboard
toolbar가 dismissal의 일관된 경계다. Light/dark system appearance 전파와 number-pad dismissal은
simulator UI test로 검증하고, 색상 token의 text/control 대비는 deterministic test로 검증한다.

## Local data와 privacy

- PIN, Authorization header, FID, presigned URL과 private content를 log, analytics, crash report,
  screenshot artifact에 넣지 않는다.
- Display cache는 재조회 가능한 derived data이며 participant/realm 변경 시 삭제한다.
- Staging, review와 production은 credential/cache/upload/FID namespace를 공유하지 않는다.
- Offline write queue와 local conflict merge는 지원하지 않는다.
- Firebase Apple client configuration은 배포 가능한 client identifier이며 server service
  account나 APNs private key를 app bundle에 넣지 않는다.

## 검증 책임

- API adapter: Mapping, Basic injection, redirect/host 정책과 status/error 변환
- Feature model: Success, failure, retry, cancellation과 stale response suppression
- UI: Loading/error/content, Dynamic Type, VoiceOver, keyboard와 privacy cover
- Integration: Approved HTTPS host, Basic API, R2 upload/complete/download와 FID route
- Release: Signed device에서 read/write/media/push/background E2E

구체적인 반복 명령과 승격 기준은 [iOS release runbook](../operations/ios-release.md), private
data 취급은 [보안 문서](../operations/security-and-secrets.md)를 따른다.

## 재검토 조건

Android 출시와 전담 유지 요구가 확정되거나 SwiftUI로 충족하기 어려운 platform 기능이 생기면
client 기술과 repository 경계를 다시 평가한다. 반복적인 PIN 재입력이 실제 사용성을 해치면
server 인증 모델과 함께 device-bound credential 또는 안전한 영속화를 검토한다.
