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

### 성공 신호와 문제 신호를 분리한다

Model은 사용자가 처리해야 하는 문제(`notice`/`mutationNotice`)와 스스로 사라지는 성공 확인
(`toast`/`mutationToast`)을 서로 다른 property로 노출한다. 성공은 자동 소멸 toast로 띄우고, 실패와
결과 불명 메시지는 사용자가 읽고 조치할 때까지 화면에 남긴다 — 눌러야 할 메시지는 시간이 지나
사라져선 안 된다. Toast의 소멸 시점은 view가 소유해 model의 mutation test가 timer에 의존하지
않게 하고, VoiceOver에서는 focus를 훔치지 않고 announcement로 알리며 더 길게 유지한다.

화면 전환, 포커스 복원과 sheet 닫기는 표시 문구가 아니라 typed mutation event
(`DiaryModel.MutationCompletion`)로 결정한다. 한국어 message 문자열을 비교해 navigation을 정하면
문구만 다듬어도 화면이 조용히 깨진다. Event는 대상 ID를 실어 화면이 자기 것만 반응하게 하고
(pushed detail 뒤에서 list가 그대로 mount돼 있으므로 scope 없는 반응은 두 번 발동한다), 연속된
같은 결과도 구분되도록 sequence를 함께 stamp한다.

### 쓰기 잠금은 쓰기만 잠근다

동시 쓰기와 결과 불명 재전송은 model(`canBeginMutation`, `canCreateScoreChange`)이 막고, 각 화면은
자기 입력·제출 control을 비활성화한다. 진행 중인 write 때문에 app 전체(tab 전환, scroll, 읽기)를
비활성화하지 않는다 — 느린 network에서 설명 없이 멈춘 app으로 읽힌다. 전체 화면 비활성화는 상호작용
자체가 의미 없는 session teardown에만 쓰고 진행 상태를 함께 표시한다.

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
준비한다. 준비된 파일은 temporary filename을 노출하는 system preview 대신 앱이 소유한
`AVPlayer`/`AVPlayerLayer` full-screen viewer에서 원본 비율로 재생한다. 재생·일시 정지,
현재/전체 길이를 말하는 VoiceOver 진행값, 명시적인 닫기와 사진 앱 저장 action을 제공하고 임의
목적지로 내보내는 공유 시트는 두지 않는다. 진행 상태 갱신은 재생 중에만 수행하고 Scene이
active가 아니면 즉시 멈춰 privacy cover 아래에 유지한다. Decoder가 파일을 열지 못하면 검은 화면에 머물지 않고 오류와 닫기, 파일 다시
받기를 제공한다. 다시 받기는 손상된 session cache lease의 discard가 끝난 뒤 새 download를
시작해 같은 파일을 재사용하는 경합을 막는다.

첨부 source는 사진 보관함(Photos picker), 카메라 촬영과 파일 앱 세 가지이며 하나의 paperclip
menu 뒤에 둔다. 세 source는 같은 준비 경로와 같은 정책 검증을 통과한다 — 입구만 늘리고 허용
kind/size/cardinality 판단을 복제하지 않아야 "보관함은 막히는데 파일 앱은 통과하는" 차이가
생기지 않는다. Camera는 simulator에서 사용할 수 없으므로 menu 항목 자체를 숨긴다.

Menu 항목은 상태만 바꾸는 `Button`으로 두고 세 presentation은 모두 `MediaAttachmentSourceMenu`가
소유한다. `Menu` content는 SwiftUI 계층에 남지 않고 UIKit menu로 평탄화되어 action closure만
살아남으므로, presentation을 스스로 소유하는 `PhotosPicker`를 항목으로 두면 label만 보이고 탭이 아무
일도 하지 않는다. 새 source를 추가할 때도 같은 모양을 지킨다. Menu가 composer와 분리된 view인 것도
이 때문이 아니라 배치 때문이다 — scrolling editor는 카드 안에, keyboard 위 입력 바는 text field와
같은 행에 두므로, 묶어 두면 배치를 바꿀 때 presentation 소유권이 함께 움직여야 한다.

선택한 첨부의 미리보기는 두 문법을 갖는다. Scrolling editor는 `MediaAttachmentComposer`의 갤러리와
항목별 파일명·byte 크기·상태 문장을 펼치고, keyboard 위 입력 바는 고정 높이 가로
strip(`MediaAttachmentStrip`)만 둔다. 갤러리 높이는 폭의 비율로 정해지므로 iPhone 15 Pro에서 사진
한 장이 약 425pt를 먹는데, keyboard 위에서 그 높이는 감당할 수 없다. Strip은 상태를 tile overlay에
맡기고 — 문장과 overlay가 같은 것을 두 번 말하고 있었다 — 결정이 필요한 실패만 한 줄로 내린다.
첨부 진입은 paperclip 한 번으로 소스 menu를 열고 트레이를 여는 토글은 두지 않는다. 트레이는 상한을
준 `ScrollView`였고, `ScrollView`는 상한을 받아도 주어진 공간을 채우므로 첨부가 없는 빈 트레이가
240pt를 그대로 점유했다.

Picker가 넘기는 파일은 앱 container 안 복사본으로 받는다 — `FileRepresentation`에
`shouldAttemptToOpenInPlace`를 쓰지 않는다. 원본을 그 자리에서 열면 JPEG asset은 통과하지만 HEIC
asset은 읽을 수 있는 파일을 얻지 못하고, 고른 HEIC 사진이 모두 "선택한 파일을 읽지 못했어요"에서
끝난다. iPhone camera의 기본 출력이 HEIC이므로 실사용에서는 보관함 대부분을 첨부할 수 없다는 뜻이다.
복사 비용은 image 10MB 상한 안에 있고 HEIF 변환은 어차피 byte가 필요하며, video는 그 다음 단계에서
protected temporary file로 복사하므로 in-place로 아낄 것이 남지 않는다. Provider가 넘긴 URL은
security-scoped일 수 있으므로 두 transfer 모두 읽기 구간 전체에서 접근을 열어 둔다. 파일 앱 경로만
그렇게 하고 picker 경로는 빼 두면, 같은 준비 경로를 공유한다는 위의 약속이 깨진다.

Photos picker와 파일 앱의 image, video는 provider file metadata에서 regular file, symbolic link
여부와 byte size를 먼저 검증한다. Image는 10MB 상한보다 큰 파일을 읽기 전에 거절하고 제한된 byte
reader로만 `Data`를 만든다. HEIF 변환은 main actor 밖에서 ImageIO downsample을 사용해 decode
축과 JPEG output 크기를 제한한다. 최대 100MB인 video는 app 전용 protected temporary file로
복사하고 file-backed URLSession upload를 사용한다. 이 파일과 directory는 backup 대상에서
제외하며 upload 성공, 취소, session lock 또는 selection 폐기 시 정확히 한 번 지운다. 실패 뒤
명시적 retry가 가능한 동안에는 파일을 유지하고, 이전 process가 남긴 upload file은 다음 launch의
scoped purge로 정리한다.

Camera 촬영본만 상한을 넘겨도 거절하지 않고 4096px과 품질 축소 loop로 다시 encode한다. 선택된
파일이 상한을 넘는 것은 사용자가 고른 대상이 정책 밖이라는 뜻이므로 조용히 축소하면 무엇을
올렸는지 감춘다. 반면 촬영본은 앱이 방금 만든 것이라 거절할 원본 의도가 없다. Encode는 raw
`CGImage`가 아니라 표시 크기로 다시 그려 `imageOrientation`을 굽는다 — 그러지 않으면 회전
정보가 사라져 옆으로 누운 사진이 올라간다.

Full-screen viewer는 사진 앱 저장 action을 제공한다. 앱이 통제하지 않는 저장소로 private
media를 내보내는 유일한 경로이며, 저장된 asset은 session을 넘어 남고 iCloud로 동기화될 수
있다. 두 participant가 서로의 사진을 이미 볼 수 있는 관계라 여기서 막는 것이 지키는 위협은
없고, 반대로 함께 남긴 기록을 각자 기기에 보관하지 못하는 제약은 제품 목적과 어긋난다. 이
결정은 [media lifecycle](../domain/media-lifecycle.md)이 함께 소유한다. 저장은 새 download
grant를 발급하지 않고 viewer가 이미 검증한 lease file을 그대로 쓰며, `addOnly` 권한만 요청해
보관함 읽기 권한은 얻지 않는다. iOS는 한 번 거부된 권한을 다시 묻지 못하게 하므로 거부 상태는
원인을 밝히고 Settings 경로를 제시한 뒤 사용자가 조치할 때까지 화면에 남긴다. 임의 목적지로
내보내는 공유 시트는 두지 않는다 — 저장 목적지가 사용자 자신의 보관함으로 한정될 때와 달리
어디로 나갈지 앱이 알 수 없다.

Upload policy가 허용하는 WebP과 WebM은 Photos가 asset으로 저장하지 못하므로 그 두 type에서는
저장 action 자체를 숨긴다. 항상 실패하는 버튼을 두고 재시도를 권하는 것보다 없는 편이 정확하다.
Upload 허용 type과 저장 가능 type이 갈라지는 지점이므로 둘 중 하나가 바뀌면 함께 확인한다.

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
"내가 보낸 것"의 판별은 표시 문구가 아니라 typed event가 실어 주는 comment ID로 한다.

두 대화 화면은 최신 위치로 갈 때 개별 댓글이 아니라 콘텐츠 끝의 1pt sentinel을 목표로 하고,
`Task.yield()` 직후와 약 120ms 뒤 두 번 이동한다. `scrollTo`는 geometry가 이미 알려진 target에만
정확히 착지하는데 `LazyVStack`의 마지막 댓글은 첫 layout 시점에 실체화되지 않아 추정값으로
움직이며, 단일 pass는 lazy 콘텐츠가 등록되기 전에 끝나 최신 댓글을 화면 밖에 남긴다. 같은 이유로
keyboard 위 입력 바의 `safeAreaInset`은 조상 view가 아니라 `ScrollView`에 붙인다 — 조상에 붙이면
ScrollView가 인식하는 가시 영역 하단이 실제와 달라져 착지점이 입력 바 뒤로 파묻힌다. 착지점은
sentinel이므로 콘텐츠 하단 padding은 최신 댓글과 입력 바 사이의 빈 틈으로 읽힌다.

대화형 comment 초안은 화면 state가 아니라 model이 scoreChange/entry 단위로 보관한다. 그래서
글을 쓰다 나가도 초안이 남고, 한 글자 입력했다는 이유로 뒤로가기와 스와이프 백을 없애지
않는다. 화면 이탈을 잠그는 것은 제출 중, 결과 불명, 그리고 아직 보내지 않은 media가 있을 때뿐이다
— media는 나가면 upload ownership이 붕 뜨기 때문이다. 이때 제공하는 탈출 action은 첨부만 버리고
글은 보관하며, dialog 문구도 실제로 지워지는 대상만 말한다.

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

모든 text input은 `FocusState`로 화면 lifecycle과 제출·취소 시점을 통제한다.

Keyboard 닫기는 messenger 관례를 따른다: 카드 주변 빈 영역을 탭하면 닫히고
(`dismissesKeyboardOnBackgroundTap()`), scroll container는 interactive dismissal을 지원한다.
Keyboard 위에 `완료` toolbar를 두지 않는다 — 모든 입력 화면은 이미 자신의 action bar를
`safeAreaInset(edge: .bottom)`으로 keyboard 바로 위에 고정하므로, system toolbar는 composer와
keyboard 사이에 세 번째 chrome 줄만 쌓았다.

그 action bar의 표면은 상단 좌우만 굽힌다(`woorisaiKeyboardActionBarSurface()`). iOS 26 keyboard는
상단 모서리를 약 15pt 반경으로 그리므로 각진 전폭 바는 두 곳에서 어긋난다 — 위로는 scroll 카드를
직선으로 잘라 내고, 아래로는 keyboard 곡선 바깥 좌우 코너에 배경이 비치는 틈을 남겨 바가 keyboard
위에 떠 있는 판처럼 보인다. 하단을 굽히지 않는 것은 keyboard가 없을 때 화면 바닥까지 채우는 safe
area 처리를 그대로 유지하기 위해서다. Divider는 상단 테두리로 대신해 선이 곡선을 따라 돌게 한다.
다섯 개 입력 화면이 같은 modifier를 쓰므로 재질과 곡률이 화면마다 갈리지 않는다.

글자수 카운터는 남은 글자 수만 보여주고 한도에 가까워질 때만 나타난다(`CharacterBudget`). 한도의
15%와 40자 중 작은 쪽이 임계값이다 — 비율만 쓰면 500자 field가 75자 남은 시점에 뜨는데 그때는 아직
문장 여러 개를 더 쓸 수 있고, 절대 수만 쓰면 200자 field는 한도의 20%에서 뜨는 반면 500자 field는
8%에서 떠서 같은 숫자가 다른 촉박함을 뜻한다. 초과는 임계값과 무관하게 항상 보인다 — 제출을 막은
이유는 화면에 남아야 한다. 표시는 사용량(`120/500`)이 아니라 잔여 수다. 사용자가 결정해야 하는 것은
몇 자를 더 쓸 수 있는지이고, 사용량은 그 값을 머릿속에서 빼야 알 수 있다. 숫자는
`monospacedDigit()`으로 폭을 고정한다. 그러지 않으면 타이핑 중 옆의 전송 버튼이 좌우로 흔들린다.
카운터가 숨어 있는 동안 VoiceOver는 입력 field의 `accessibilityHint`로 여유를 듣는다 — `value`는
입력한 text로 남겨 둔다.

이 탭 제스처는 `ScrollView`의 **content**에, content의 가장 바깥
`.frame(maxWidth: .infinity)` 뒤에 붙여 gutter까지 포함한 전체 폭을 탭 영역으로 만든다. 두 가지
함정이 있다: 콘텐츠 **뒤에** 깔아 둔 layer는 터치를 받지 못하고(`ScrollView`는 `UIScrollView`이며
`UIView.hitTest`는 배경색과 무관하게 자기 bounds 안의 터치를 가져간다), `ScrollView` 자체에 붙이는
것으로도 부족하다(배경 없는 `VStack`은 hit 영역을 만들지 않아 여백 탭이 아무것도 match하지 못한다).
그래서 `contentShape`를 명시한다.

SwiftUI는 조상 제스처보다 자식 제스처에 우선권을 주므로 내부의 버튼, 링크와 입력 필드는 자기 탭을
유지한다 — `전송`은 keyboard를 내리지 않아야 한다(대화 화면은 다음 답장을 위해 포커스를 유지한다).
콘텐츠 위를 덮는 탭 layer는 그 의도를 조용히 깨뜨리므로 만들지 않는다. 포커스에 따라 나타났다
사라지는 인라인 dismiss control도 layout을 흔들므로 만들지 않는다. Multiline field의 return key는
줄바꿈에 남겨 둔다.

네 자리 PIN은 다섯 번째 숫자를 받지 않으므로 네 번째 입력이 곧 제출 의도다. `.enteringPIN`에서는
자동 제출해 로그인마다 keyboard 내리기와 scroll을 요구하지 않는다. `.unavailable`/`.failed`는
결과 불명을 자동 재전송하지 않겠다는 약속이므로 자동 제출하지 않고 명시적 `다시 시도` 버튼을
유지한다. 거부된 PIN은 keyboard를 유지해 재입력에 추가 탭이 필요 없게 하고, 대화형 comment
전송 성공 후에는 포커스를 복원해 연속 답장이 끊기지 않게 한다.

작성 화면의 sheet는 `.large` detent로 고정한다. `.medium`은 text editor와 keyboard가 함께
올라오면 본문이 거의 보이지 않는다. 반복 카피 hero card는 목록 root에만 두고 detail과 editor에는
두지 않는다 — navigation title이 이미 화면을 지칭하고, hero는 사용자가 보러 온 본문과 입력란을
화면 밖으로 밀어낸다.

Light/dark system appearance 전파, 배경 탭 keyboard dismissal과 number-pad dismissal은 simulator
UI test로 검증하고, 색상 token의 text/control 대비는 deterministic test로 검증한다.

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
