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
- 401은 local credential과 저장된 Keychain archive를 제거하고 PIN 재입력을 요구한다.
  Server login/logout call은 없다.
- Credential은 기본으로 process memory에만 둔다. 로그인 화면에서 생체인증 저장을 opt-in한
  경우에만 불투명 archive를 Keychain에 보관한다: `WhenPasscodeSetThisDeviceOnly` +
  `.biometryCurrentSet`(device-only, non-synchronizing, 생체 재등록 시 무효화), 읽기는 생체
  프롬프트로 gate하고 존재 확인은 `LAContext.interactionNotAllowed`로 프롬프트 없이 수행한다.
- 다시 실행하면 존재 확인이 잠금 화면 여부를 결정하고, 생체 해제 뒤 보호 요청 재검증
  (2xx/401)이 세션 복원을 확정한다. Server에는 여전히 세션이 없다.
- Local session lock은 in-memory credential, private cache와 navigation state를 지우되
  Keychain archive와 push FID는 유지하는 client 동작이다. 이 동작은 반복 사용 중 실수로
  누르기 쉬운 feature navigation bar가 아니라 Settings의 보안 section에서 확인 dialog를 거쳐
  제공한다. Settings의 "이 기기에서 로그인 정보 지우기"가 Keychain archive까지 제거하는 전체
  sign-out이다. 둘 다 server logout endpoint를 의미하지 않는다.

Memory-only 기본값은 device 저장소 노출 범위를 줄이는 대신 app을 다시 실행할 때마다 PIN을
재입력하게 한다. 생체인증 opt-in은 이 불편과 at-rest 저장의 균형을 사용자가 기기 단위로
결정하게 한다.

## State와 error

Async feature는 `idle/loading/success/recoverable failure`를 명시하고 model이 network task를
소유한다. 새 request나 화면 종료 시 이전 task를 취소하며 stale response가 최신 state를
덮지 못하게 한다. View가 HTTP status나 generated response를 직접 해석하지 않는다.

Adapter는 `401`, domain `400/403/404/409`, provider/DB `503`을 feature error로 변환한다.
Undocumented response는 success로 추정하지 않는다. Relationship create처럼 wire-level
idempotency가 없는 write는 transport outcome이 불명확하거나 409인 경우 자동 재시도하지 않고
사용자에게 reload/retry를 분리해 제시한다.

모든 unknown-outcome(결과 불명) 상태는 네트워크 없이도 도달 가능한 탈출로를 반드시 가진다:
"재전송 없이 초안 정리(abandon)"는 서버 재조회 성공을 전제하지 않으며, 재조회가 실패해도 항상
활성이다. 결과 불명이 대개 연결 장애에서 오므로, 재조회 성공을 요구하는 탈출로는 화면 잠금
(취소·스와이프·뒤로가기 비활성)과 결합해 강제 종료 외 탈출 불가 상태를 만든다. 화면 이탈을
잠그는 상태를 추가할 때는 같은 화면에 오프라인에서도 눌리는 명시적 탈출 액션이 있는지 함께
검증한다.

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

저장된 사진과 업로드 preview는 같은 gallery geometry를 사용한다. 한 장은 4:3, 두 장 이상은
정사각 mosaic, video는 16:9 tile을 기본으로 하며 inline tile에서는 `aspectFill`과 clipping으로
박스와 이미지 사이 빈 영역을 만들지 않는다. 원본 비율 확인이 필요한 full-screen viewer에서는
`aspectFit`으로 portrait, landscape와 panorama 전체를 보존하고 pinch, pan, double tap과
VoiceOver adjustable action으로 확대한다. 회전과 확대 배율 변경 때 pan offset을 다시 제한해
사진이 화면 밖에 남지 않게 한다. 이 presentation 선택은 wire 계약이나 attachment cardinality를
바꾸지 않는다. Video는 feed traversal 중 자동 download하지 않고 사용자가 16:9 tile을 누를 때만
준비한다. 준비된 파일은 공유 action이나 temporary filename을 노출하는 system preview 대신 앱이
소유한 `AVPlayer`/`AVPlayerLayer` full-screen viewer에서 원본 비율로 재생한다. 재생·일시 정지,
현재/전체 길이를 말하는 VoiceOver 진행값과 명시적인 닫기 action만 제공하며 공유 action은 두지
않는다. 진행 상태 갱신은 재생 중에만 수행하고 Scene이 active가 아니면 즉시 멈춰 privacy cover
아래에 유지한다. Decoder가 파일을 열지 못하면 검은 화면에 머물지 않고 오류와 닫기, 파일 다시
받기를 제공한다. 다시 받기는 손상된 session cache lease의 discard가 끝난 뒤 새 download를
시작해 같은 파일을 재사용하는 경합을 막는다.

Photos picker의 image와 video는 provider file metadata에서 regular file, symbolic link 여부와
byte size를 먼저 검증한다. Image는 10MB 상한보다 큰 파일을 읽기 전에 거절하고 제한된 byte
reader로만 `Data`를 만든다. HEIF 변환은 main actor 밖에서 ImageIO downsample을 사용해 decode
축과 JPEG output 크기를 제한한다. 최대 100MB인 video는 app 전용 protected temporary file로
복사하고 file-backed URLSession upload를 사용한다. 이 파일과 directory는 backup 대상에서
제외하며 upload 성공, 취소, session lock 또는 selection 폐기 시 정확히 한 번 지운다. 실패 뒤
명시적 retry가 가능한 동안에는 파일을 유지하고, 이전 process가 남긴 upload file은 다음 launch의
scoped purge로 정리한다.

## Presentation과 navigation

Relationship 첫 화면은 현재 양방향 점수와 최근 기록을 짧게 훑는 dashboard다. 점수 변경의
slider, 이유와 첨부는 item-driven sheet에서 편집하고 저장 action은 safe area에 고정한다. 이
구조는 작성 form 때문에 dashboard scroll이 길어지는 문제를 피한다. Dashboard에는 최근 기록
세 개만 두고 전체 timeline과 pagination은 별도 archive 화면에서 제공한다. 작성 중인 sheet는
명시적으로 저장하거나 버리기 전에는 interactive dismissal을 막아 draft 유실을 방지한다.

Diary 첫 화면은 최근 기록을 polaroid형 feed로 보여 주고 작성·편집·댓글 action은 keyboard와
겹치지 않는 safe-area composer에 둔다. Relationship와 Diary의 대화는 server 순서대로 평평한
시간순 목록이며 reply nesting을 만들지 않는다. Navigation path와 sheet destination은 stable ID로
표현하고, role에 따른 작성자 전용 edit/delete 권한은 화면을 다시 그릴 때도 domain model의
`isMine` 의미를 따른다.

Refresh는 이미 표시된 dashboard, feed와 detail을 비우거나 scroll 위치를 강제로 옮기지 않고
최신 snapshot으로 교체한다. 새로 도착한 상대 댓글도 읽던 위치를 빼앗지 않으며 사용자가 직접
최신 댓글로 이동한다. 자신이 방금 보낸 댓글만 commit 확인 후 입력을 비우고 최신 위치로 이동한다.

Score, diary와 comment create/update/delete는 idempotency key가 없는 write이므로 transport 단절
뒤 자동 재전송하지 않는다. Response를 받지 못해 commit 여부가 불명확하면 같은 mutation과 다른
write를 잠그고 draft와 제출한 media ownership을 유지한다. 사용자는 해당 score, entry 또는
comment를 포함하는 동일 mutation context를 성공적으로 다시 읽은 뒤 `이미 저장됨` 또는
`저장 안 됨`을 명시적으로 고른다. Entry/comment update editor는 이 확인이 끝날 때까지 화면에
남아 draft를 보존하며, 관계없는 list/detail refresh는 확인 근거로 쓰지 않는다. 전자는 draft를
정리하고 media를 소비하며, 후자는 제출 ownership만 풀어 같은 draft를 직접 재시도하게 한다.
Conflict와 server가 commit하지 않았음을 확정할 수 있는 validation/authorization 실패는 이
불명확 결과 경로와 구분한다.

Update reconciliation의 `제출 상태`는 전송을 시작할 때 normalized content와 attachment ID를
immutable snapshot으로 고정한다. Transport failure 뒤 editor에서 내용을 더 고쳐도 이 snapshot을
바꾸지 않는다. `저장 안 됨`을 확인해 재시도를 허용한 뒤에는 draft-protection lease를 별도로
유지한다. 이 lease는 실제 재제출의 in-flight fence로 끊김 없이 넘기거나 사용자가 초안을 명시적으로
버릴 때만 해제하므로, 그 사이 도착한 push가 navigation path를 바꿔 editor와 READY media를
정리하지 못한다.

Entry update의 최신 상태 비교는 본문만이 아니라 retained attachment ID와 제출한 READY upload
ID의 집합까지 확인한다. 최신 server 상태가 제출 상태와 정확히 같을 때만 `이미 저장됨`, 수정 전
상태와 정확히 같을 때만 `저장 안 됨`을 허용하고, 제3의 상태이면 두 선택을 모두 잠가 stale
snapshot 위 재전송이나 media 중복 연결을 막는다. Relationship archive pagination은 별도
loading/error/retry 상태를 표시해 긴 기록을 더 불러오는 실패가 무응답처럼 보이지 않게 한다.

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
실제 write 제출 중이거나 결과 불명확 상태가 해소되지 않은 동안의 intent는 화면 전환으로 복구
context를 잃지 않도록 보류하고, write 완료 또는 명시적 결과 확인 뒤 처리한다. Sign-out/재인증
중 intent는 폐기한다.

## Appearance와 text input

App, sheet와 system keyboard는 사용자가 선택한 iOS light/dark appearance를 따른다. Bundle이나
view에서 interface style을 고정하지 않고, warm visual identity는 light/dark 값을 함께 가진
semantic palette로 유지한다. Text, surface, control border, status와 accent는 각 appearance에서
독립적으로 읽을 수 있는 대비를 가져야 하며 system `List`와 alert의 platform semantic color를
덮어쓰지 않는다. App이 직접 그리는 전면 chrome(프라이버시 커버, launch 배경)은
`.systemBackground` 같은 system semantic color가 아니라 brand palette를 쓴다 — system color는
다크에서 순검정 플래시로 나타나 브랜드 배경과 이질적이다.

모든 text input은 `FocusState`로 화면 lifecycle과 제출·취소 시점을 통제한다. Keyboard 닫기는
화면당 한 번 부착하는 공용 `keyboardDoneToolbar()`(keyboard 위 `완료` toolbar)가 표준이고,
scroll container는 interactive dismissal을 지원한다. 포커스에 따라 나타났다 사라지는 인라인
dismiss control은 layout을 흔들므로 만들지 않는다. Multiline field의 return key는 줄바꿈에
남겨 둔다. 거부된 PIN은 keyboard를 유지해 재입력에 추가 탭이 필요 없게 하고, 대화형 comment
전송 성공 후에는 포커스를 복원해 연속 답장이 끊기지 않게 한다. Light/dark system appearance
전파와 number-pad dismissal은 simulator UI test로 검증하고, 색상 token의 text/control 대비는
deterministic test로 검증한다.

## Local data와 privacy

- PIN, Authorization header, FID, presigned URL과 private content를 log, analytics, crash report,
  screenshot artifact에 넣지 않는다.
- 프라이버시 커버(SwiftUI overlay + UIKit snapshot shield)는 `AppPrivacyCoverPolicy` 단일
  정책을 공유한다: scene이 비활성이고 화면 내용이 실제로 private할 때만 덮는다. 생체 잠금
  플로우(`restoring/locked/unlocking`)는 그 자체가 비민감 커버이므로 예외다 — 이 예외가 없으면
  Face ID system sheet가 scene을 `.inactive`로 떨어뜨려 잠금 화면 전체가 커버로 가려진다.
  정책 매트릭스는 deterministic test로 고정한다.
- Display cache는 재조회 가능한 derived data이며 participant/realm 변경 시 삭제한다.
- Staging, review와 production은 credential/cache/upload/FID namespace를 공유하지 않는다.
- Offline write queue와 local conflict merge는 지원하지 않는다.
- Firebase Apple client configuration은 배포 가능한 client identifier이며 server service
  account나 APNs private key를 app bundle에 넣지 않는다.

## 검증 책임

- API adapter: Mapping, Basic injection, redirect/host 정책과 status/error 변환
- Feature model: Success, failure, retry, cancellation과 stale response suppression
- UI: 두 participant role의 loading/error/content/conflict/empty/dirty state, Dynamic Type,
  VoiceOver, keyboard, portrait/landscape/panorama media와 privacy cover
- Integration: Approved HTTPS host, Basic API, R2 upload/complete/download와 FID route
- Release: Signed device에서 read/write/media/push/background E2E

구체적인 반복 명령과 승격 기준은 [iOS release runbook](../operations/ios-release.md), private
data 취급은 [보안 문서](../operations/security-and-secrets.md)를 따른다.

## 재검토 조건

Android 출시와 전담 유지 요구가 확정되거나 SwiftUI로 충족하기 어려운 platform 기능이 생기면
client 기술과 repository 경계를 다시 평가한다. 반복적인 PIN 재입력이 실제 사용성을 해치면
server 인증 모델과 함께 device-bound credential 또는 안전한 영속화를 검토한다.
