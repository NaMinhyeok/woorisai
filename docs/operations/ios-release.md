# iOS release와 App Store runbook

이 문서는 모든 iOS release에 반복 적용하는 승격 기준이다. 개별 build 번호, source revision,
archive checksum과 App Store Connect 상태는 해당 release
artifact와 배포 시스템에 기록하고 이 문서에는 누적하지 않는다.

제품 식별자는 다음과 같다.

- App Store 이름: `우리사이: 둘만의 기록`
- 기기 표시 이름: `우리사이`
- Bundle ID: `com.naminhyeok.woorisai`
- Minimum deployment target, Swift/Xcode version과 package pin은 `apps/ios/project.yml`과
  `Package.resolved`가 소유한다.

Client 구조와 privacy contract는 [iOS architecture](../architecture/ios-architecture.md), 비밀
취급은 [보안 문서](security-and-secrets.md), wire contract는
[OpenAPI](../../contracts/openapi-v2.yaml)를 따른다.

## Release 원칙

- 같은 archive를 TestFlight 검증과 App Store release에 사용한다. 검증 뒤 rebuild/re-sign하지
  않는다.
- Backend artifact, OpenAPI contract와 iOS binary의 호환성을 하나의 release 단위로 확인한다.
- Simulator는 빠른 회귀 gate이고 signed device는 signing, media, APNs와 background
  동작의 필수 gate다.
- Review/staging/production realm은 data와 credential을 공유하지 않는다.
- Public release는 자동 승격하지 않고 모든 gate를 통과한 build를 수동으로 release한다.
- 배포된 app은 즉시 회수할 수 없으므로 backend는 지원 중인 binary의 API contract를 보존한다.

## Source와 simulator gate

`project.yml`이 Xcode project structure의 정본이다. Project 재생성이 필요하면 repository가
정한 XcodeGen version을 사용하고 generated project diff를 검토한다.

최소 검증 명령은 다음과 같다.

```bash
cd apps/ios
xcodebuild test -project Woorisai.xcodeproj -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=26.5' \
  -skipPackagePluginValidation
xcodebuild test -project Woorisai.xcodeproj -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro,OS=26.5' \
  -skipPackagePluginValidation
xcodebuild build -project Woorisai.xcodeproj -scheme Woorisai \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation
```

Simulator와 unit test는 다음 계약을 다룬다.

- OpenAPI generation, adapter mapping과 generated type 격리
- Same-origin HTTPS Basic injection과 redirect/R2 header 차단
- Login options, 401 re-authentication과 local sign-out
- Relationship/diary read/write, authorization와 409 reload behavior
- Media selection, upload/complete/download, cancel과 ambiguous outcome handling
- FID register/unregister와 notification route mapping
- Loading/error/retry/cancel/stale-response suppression
- Dynamic Type, VoiceOver, keyboard, reduce motion와 color contrast
- Long Korean content, media-only comment, pagination과 privacy cover

Simulator success를 physical device gate의 대체로 사용하지 않는다.

GitHub `Verify` workflow는 pull request와 `main`에서 Repository hygiene, backend/container와 함께
두 지원 화면의 iOS test를 실행한다. TestFlight workflow는 선택한 revision이 `main`이고 같은 SHA의
Repository hygiene, Backend check, Container smoke와 iOS app gates가 모두 성공한 경우에만 release
job을 시작한다. CI 성공 여부를 문서에 복제하지 않고 GitHub check가 실행 증거를 소유한다.

## Environment와 realm

- Debug는 allowlisted staging HTTPS host만 사용한다.
- Tracked Release 설정은 통신 불가능한 placeholder이고, archive는 승인된 production HTTPS host를
  protected input으로 주입한다.
- Review flow가 필요하면 동일 Release artifact가 compile-time allowlist의 synthetic review host를
  선택하는 명시적 경로만 허용한다.
- 임의 URL 입력, cleartext fallback, remote host toggle과 reviewer 탐지를 만들지 않는다.
- Staging/review/production은 credential, cache, upload state와 FID namespace를 공유하지 않는다.

Review backend는 production과 호환되는 backend/OpenAPI/schema contract를 사용하지만 DB, R2,
Firebase와 PIN은 분리한다. 정확히 두 synthetic participant만 두고 review PIN은 source나 binary가
아닌 App Store Connect의 비공개 review 정보로만 전달한다.

API Basic header는 API origin 밖 redirect나 presigned R2 URL에 전달되어서는 안 된다.

### Local env 입력

다음 실제 파일은 Git에서 제외하고 mode `0600`으로 유지한다.

- `apps/ios/.env.local`: Debug Firebase provider/device 검증 입력
- `apps/ios/.env.production`: Production API host, Release Firebase config path/realm assertion,
  App Store Connect API key path/ID/issuer와 release version/build 입력
- `/.private/ios-signing/`: 재사용 가능한 Apple Distribution PKCS#12, 암호 파일과 App Store
  provisioning profile의 local 보호 원본

Commit되는 `.env.local.example`과 `.env.production.example`은 key schema와 placeholder만 가진다.
Production API host 자체는 credential이 아니지만 private product의 target을 source에 고정하지 않고
release input으로 관리한다. `project.yml`에는 통신 불가능한 placeholder만 둔다. PIN, Firebase Admin
service account, APNs private key와 Railway token은 iOS env나 app bundle에 넣지 않는다.

```bash
apps/ios/scripts/validate-env.zsh --kind local apps/ios/.env.local
apps/ios/scripts/validate-env.zsh --kind production apps/ios/.env.production
```

Validator와 release script는 dotenv를 shell code로 source/eval하지 않고 allowlisted key만 읽는다.
실제 값, plist field, key content를 출력하지 않으며 unknown, duplicate, malformed 또는 realm 불일치
입력에서 중단한다. Local `.env.production`과 `/.private/`는 protected 원본의 대체 backup이나 CI의
정본이 아니다. `/.private/` 전체는 repository root `.gitignore`에 포함하며 각 파일은
group/other 권한이 없는 `0600`으로 유지한다. PKCS#12 암호 값은 command line 인자로 전달하지 않고
한 줄짜리 암호 파일 경로만 release script에 전달한다.

## Firebase client configuration

Firebase Apple client plist는 source control에서 제외한다. Simulator Debug는 기본적으로
configuration을 주입하지 않는다. 실제 device build와 Release archive는 staging/provider 검증
또는 release realm의 보호된 config path와 승인된 realm digest가 없으면 실패한다. Config와
expected digest가 모두 검증된 경우에만 plist를 bundle에 넣는다.

Firebase Console의 정확한 Apple app은 signing team과 같은 Team ID를 사용하고, 대상 realm에서
유효한 APNs authentication key 또는 certificate를 가져야 한다. 이 metadata와 만료 상태는
signed-device gate 전에 확인하되 private key나 key contents를 release evidence에 복사하지 않는다.

Realm digest는 `PROJECT_ID`, `GOOGLE_APP_ID`, `GCM_SENDER_ID`, `API_KEY`, `BUNDLE_ID`를 고정
순서로 NUL-terminated해 계산한 SHA-256이다. Config와 expected digest를 같은 job에서 함께
만들지 않는다. Archive는 plist 누락, malformed data, bundle ID·필수 key·realm 불일치에서
실제 값을 출력하지 않고 실패해야 한다.

이 plist는 app이 Firebase project를 찾기 위한 배포 가능한 client configuration이다. Firebase
Admin service account와 APNs private key는 server secret이며 app bundle에 절대 포함하지 않는다.

## Signed-device gate

실제 지원 기기 또는 승인된 동급 기기에서 Release/TestFlight artifact로 다음을 확인한다.
UDID, serial, 실제 PIN, FID/device token과 사용자 이름은 기록하지 않는다.

- First launch, upgrade, slot/PIN 입력, 401 재인증과 local sign-out
- 두 방향 relationship read/write와 concurrent refresh
- Diary entry/comment의 전체 CRUD와 작성자 권한
- 지원 image/video upload/download, 취소/retry와 background 전환
- Parent media write 중 back/tab/push navigation이 upload를 조기 discard하지 않는지 확인
- Notification permission 거절 시 핵심 기능 유지
- FID rotation/register/unregister와 각 producer event의 APNs delivery
- Generic lock-screen text와 tap 이후 Basic API authorization
- Foreground notification이 자동 navigation하지 않고 user tap에서만 route하는지 확인
- App restart, network loss, backend 503와 duplicate notification recovery
- Detail/media가 열린 app-switcher snapshot에 neutral privacy cover가 적용되는지 확인

Provider E2E는 production과 분리한 staging R2/Firebase credential로 먼저 수행한다. Production
smoke는 승인된 account와 최소 범위로 수행하고 private payload를 test evidence에 복사하지 않는다.

## Signing과 privacy gate

- Explicit Bundle ID, distribution profile와 signing team이 product record와 일치한다.
- Release archive/export는 Team `83KHWR8L3R`, `Apple Distribution`, profile
  `Woorisai App Store Reusable 2026`를 지정한 manual signing만 사용한다. Profile에 등록 기기
  목록이 있거나 enterprise all-device entitlement가 있으면 중단한다.
- Manual identity, style과 profile은 `project.yml`의 `Woorisai` Release target에서
  `sdk=iphoneos*`일 때만 적용한다. Team은 signed-device test target도 사용하는 project 공통값으로
  유지한다. Archive 명령의 전역 build setting으로 전달하지 않아 package, `WoorisaiAPI`와 Release
  simulator build에 profile을 전파하지 않는다.
- Release entitlement는 필요한 Push Notifications와 최소 background mode만 포함한다.
- Distribution artifact에서 `get-task-allow=false`와 expected App Store entitlement를 확인한다.
- Signing key, certificate password와 APNs key는 repository, project file, command line과 build
  log에 넣지 않는다.
- PIN fixture, private content, server provider credential와 Debug endpoint가 archive에 없어야 한다.
- Camera, microphone, location, tracking과 full photo-library 권한은 실제 feature 필요와 product
  privacy review 없이 추가하지 않는다.
- PhotosPicker처럼 system picker로 충분하면 broad library permission을 요청하지 않는다.
- App Privacy, privacy policy, retention, third-party SDK와 required privacy manifest를 release마다
  검토한다.

## Archive와 승격 순서

1. Source revision, backend artifact, OpenAPI/schema compatibility와 release owner를 고정한다.
2. Backend staging/review realm과 simulator gate를 통과한다.
3. Signed-device media/Firebase/APNs와 privacy/security gate를 통과한다.
4. Release archive 하나를 만들고 checksum, signature, entitlement와 embedded configuration을
   검토한다.
5. 같은 archive를 App Store Connect에 올리고 TestFlight review realm에서 검증한다.
6. Review 정보에는 synthetic credential만 비공개로 제공한다.
7. Production API에서 같은 TestFlight artifact의 최소 read/write/media/push smoke를 수행한다.
8. 승인된 build를 manual release하고 privacy-safe health/error 지표를 관찰한다.

심사 artifact와 출시 artifact가 다르거나 production contract E2E를 통과하지 못하면 release하지
않는다.

## GitHub TestFlight delivery

`.github/workflows/ios-testflight.yml`은 `main`에서만 수동 `workflow_dispatch`로 실행한다. Version은
`x.y.z`, build number는 App Store Connect에서 아직 사용하지 않은 양의 정수여야 한다. Workflow
수동 실행 자체를 승인 경계로 사용하고 `ios-testflight` environment는 deployment record를 소유한다.

`ios-testflight` environment secret은 다음 이름을 사용한다.

| Secret | 내용 |
| --- | --- |
| `WOORISAI_API_HOST` | Scheme/path 없는 production API DNS hostname |
| `ASC_KEY_P8_BASE64` | 최소 권한 App Store Connect API private key의 base64 |
| `ASC_KEY_ID`, `ASC_ISSUER_ID` | 해당 API key identity |
| `IOS_DISTRIBUTION_P12_BASE64` | profile에 포함된 Apple Distribution identity의 PKCS#12 base64 |
| `IOS_DISTRIBUTION_P12_PASSWORD` | 해당 PKCS#12를 여는 암호 |
| `IOS_APP_STORE_PROFILE_BASE64` | `Woorisai App Store Reusable 2026` profile의 base64 |
| `FIREBASE_RELEASE_PLIST_BASE64` | production Firebase Apple client plist의 base64 |
| `FIREBASE_RELEASE_REALM_SHA256` | release realm assertion |
| `FIREBASE_DEBUG_REALM_SHA256` | release와 다른 debug realm assertion |

Workflow는 secret을 runner 임시 directory에만 mode `0600`으로 복원한 뒤
`apps/ios/scripts/release-testflight.zsh`를 호출한다. Script는 Xcode 26.6과 pinned package를
확인하고 exact profile의 manual Apple Distribution signing으로 Release archive를 만든다.
PKCS#12 암호는 OpenSSL password-file 입력으로만 읽으며 process argument나 log에 값을 넣지 않는다.
암호를 해제한 임시 PEM은 mode `0600` release directory에서 keychain import 직후 삭제한다. Script는
기존 default/search keychain을 기록한 뒤 임시 keychain만 사용하고 종료·실패·signal에서 원래
keychain 설정을 복구하고 임시 keychain을 삭제한다. Provisioning profile도 UUID 충돌을 검사한 뒤
Xcode의 현재 `~/Library/Developer/Xcode/UserData/Provisioning Profiles` 위치에 설치하며 script가
새로 설치한 파일만 종료 시 삭제한다. 이미 설치된 byte-identical profile은 재사용하고 보존한다.

App Store Connect API key는 provisioning이나 signing을 자동 생성하는 데 쓰지 않는다. Archive와
export 및 bundle 검증을 마친 뒤 임시 경로에 복원하여 동일 IPA의 `altool` validate/upload 인증에만
사용하고 즉시 삭제한다. 따라서 build phase와 package plugin은 API key 경로나 내용을 전달받지 않고,
registered device 없이 App Store profile로
archive/export할 수 있고, signing 자산이 profile과 맞지 않으면 Apple provider 호출 전에 중단한다.
실제 upload는 tracked·untracked 변경이 하나도 없는 worktree에서만 허용해 기록한 HEAD revision이
archive source를 정확히 식별하게 한다. Local `--no-upload` 검증은 commit 전 확인을 위해 dirty
worktree에서도 허용한다.
Local release와 `test-release-evidence.zsh`의 keychain lifecycle 검사는 user default/search keychain을
잠시 격리하므로 서로 또는 다른 codesign 작업과 병렬 실행하지 않는다. 종료 뒤 default/search가 원래
목록으로 복구되지 않았으면 다음 signing 작업을 시작하지 않는다. GitHub runner는 job별 격리와 workflow
concurrency를 사용한다.
Archive의 bundle/version/build, production APNs entitlement, `get-task-allow=false`, signature와
Firebase config 및 embedded profile의 byte identity를 검증한 뒤 같은 archive에서 IPA를 export한다.
Export는
`manageAppVersionAndBuildNumber=false`라 입력한 build identity를 바꾸지 않으며, `altool` validate와
upload `--wait`가 성공해야 workflow를 완료한다.

검증된 archive는 entry type, 상대 경로, permission, symlink target과 각 regular file SHA-256을
정렬된 manifest로 만들고 그 manifest의 SHA-256을 archive checksum으로 사용한다. 따라서 절대 경로,
filesystem 순회 순서와 timestamp는 checksum을 바꾸지 않지만 archive content, 경로, permission과
symlink target 변경은 감지한다. IPA 자체의 SHA-256도 별도로 계산한다. Workflow는 source revision,
version/build, 두 checksum, validate/upload 상태만 GitHub job summary에 남긴다. `altool` JSON이
`builds` resource identifier를 명확하게 제공할 때만 그 identifier를 기록하고, 그렇지 않으면
`not-reported`로 남긴다. Provider 원문, archive/IPA와 protected input은 summary나 GitHub artifact로
보존하지 않고 runner 임시 directory에서 종료 시 삭제한다. Evidence destination은 archive와
upload 전에 생성 가능 여부를 확인해, 성공한 upload 뒤 기록 경로 오류 때문에 같은 build를 다시
실행하는 상황을 막는다.

Local에서 같은 경계를 upload 없이 확인할 수 있다.

```bash
apps/ios/scripts/release-testflight.zsh \
  --env-file apps/ios/.env.production \
  --build-number 6 \
  --distribution-p12 "$PWD/.private/ios-signing/woorisai-distribution.p12" \
  --distribution-p12-password-file \
    "$PWD/.private/ios-signing/woorisai-distribution-p12.password" \
  --provisioning-profile \
    "$PWD/.private/ios-signing/Woorisai_App_Store_Reusable_2026.mobileprovision" \
  --no-upload
```

실제 release input이 채워져 있으면 archive/export/App Store Connect validation까지 수행한다.
Placeholder 상태의 ignored 파일에서는 Xcode/toolchain, env schema와 manual export option만 검사하고
signing과 archive는 건너뛴다. 실제 release input에서는 세 signing file 인자를 모두 제공해야 한다.

TestFlight internal 배포는 automation할 수 있지만 App Store review/public 승격은 자동화하지 않는다.
현재 synthetic review realm 선택과 credential/cache/upload/FID namespace 분리가 준비되지 않았다면
external TestFlight와 App Review를 중단한다. 이 경계를 구현하고 signed-device/review smoke를 통과한
뒤 같은 uploaded archive를 App Store Connect에서 수동 승격한다.

## Rollback과 forward fix

App Store binary는 server처럼 즉시 rollback할 수 없다.

- Release 전에는 build를 TestFlight/internal 상태에 유지하고 승격을 중단한다.
- Release 후 client defect는 가능한 경우 server-side compatibility를 유지한 채 forward fix
  build를 준비한다.
- Backend rollback이 필요하면 현재 iOS binary의 OpenAPI/schema contract와 호환되는지 먼저
  확인한다.
- Credential/provider compromise는 build 재배포만 기다리지 말고 affected secret을 즉시
  revoke/rotate하고 backend access를 제한한다.

## Release evidence

각 release artifact에는 다음을 연결한다. Canonical runbook에는 결과를 누적하지 않는다.

- App version/build, archive checksum과 App Store build identifier
- Source revision, backend artifact와 OpenAPI/schema compatibility
- Xcode/Swift/SDK와 resolved package version
- Simulator, signed-device, staging/review/production gate 결과
- Basic/media/FID/push/privacy/security 결과
- 실행하지 못한 test, known issue와 rollback/forward-fix owner

실제 secret, PIN, hostname credential와 device identifier는 evidence에 쓰지 않는다.

## 참고

- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store 제출](https://developer.apple.com/app-store/submitting/)
- [Firebase Apple platform 설정](https://firebase.google.com/docs/ios/setup)
- [Firebase Messaging for Apple platforms](https://firebase.google.com/docs/cloud-messaging/ios/get-started)
