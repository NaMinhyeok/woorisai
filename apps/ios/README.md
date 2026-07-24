# Woorisai iOS

이 디렉터리는 iOS 17 이상을 대상으로 하는 native SwiftUI client를 담는다. 제품·보안 결정은
[iOS 아키텍처](../../docs/architecture/ios-architecture.md), 공개 wire는
[OpenAPI](../../contracts/openapi-v2.yaml), 배포 gate는
[iOS release runbook](../../docs/operations/ios-release.md)이 정본이다.

## 정본과 생성물

- `project.yml`: target, build setting, deployment target와 direct package version의 정본
- `Woorisai.xcodeproj`: `project.yml`이 요구하는 XcodeGen으로 생성하고 diff를 검토하는 project
- `Package.resolved`: transitive Swift package resolution
- `Woorisai/Core/API/openapi.yaml`: root OpenAPI를 가리키는 target-local symlink
- DerivedData의 generated Swift source: build 생성물이므로 commit하거나 손으로 수정하지 않음

`project.yml`을 바꿨다면 다음 명령으로 project를 다시 만들고 generated project diff를
검토한다.

```bash
xcodegen generate --spec apps/ios/project.yml
```

OpenAPI operation을 추가·삭제하면 generator filter, public/protected authorization 분류,
adapter mapping과 app 소비를 같은 변경에서 갱신한다. Generated type은 `WoorisaiAPI` 밖의
public signature에 노출하지 않는다.

## Target 경계

| Target | 책임 |
| --- | --- |
| `WoorisaiAPI` | Generated client/type과 app-owned API adapter/model |
| `Woorisai` | SwiftUI app, feature state와 provider composition |
| `WoorisaiAPITests` | Generated protocol 경계의 mapping·transport·security 검증 |
| `WoorisaiTests` | Authentication, relationship, diary, media와 notification state 검증 |
| `WoorisaiUITests` | Simulator launch, navigation, accessibility와 주요 오류 흐름 smoke |

App target은 `WoorisaiAPI`의 public adapter/model만 사용한다. Feature view/model이 HTTP status나
generated response를 직접 해석하지 않는다.

## Environment와 credential

- Debug와 tracked Release API host는 `project.yml`의 network 성공을 의도하지 않는 예약
  placeholder다. 실제 Release host는 ignored `.env.production` 또는 GitHub secret에서 승인된
  archive에만 build setting으로 주입한다.
- Slot과 네 자리 PIN으로 만든 Basic credential은 process memory에만 둔다. Keychain,
  UserDefaults, file, log와 analytics에는 기록하지 않는다.
- Authorization middleware는 승인된 same-origin HTTPS API request에만 header를 주입한다.
  Redirect와 presigned R2 request에는 Basic header를 전달하지 않는다.
- 401은 PIN 재입력을 요구한다. Local sign-out은 best-effort FID unregister 뒤 credential,
  private cache와 navigation state를 지우며 server logout endpoint를 호출하지 않는다.
- Private download는 인증 session별 shared loader에서 attachment별로 합치고 최대 세 건만
  동시에 실행한다. Presigned URL은 저장하지 않으며 bounded protected-file cache는 sign-out과
  PIN 재입력 전에 진행 중 작업과 함께 지운다.

Firebase Apple client plist는 source control에 넣지 않는다. Debug provider 검증은 보호된
`WOORISAI_FIREBASE_DEBUG_CONFIG_PATH`와 독립적으로 관리한 realm digest를 함께 제공할 때만
사용한다. Simulator는 config 없이 실행할 수 있지만 실제 device build와 Release archive는
보호된 config path와 expected digest 검증을 통과해야 한다. Firebase Admin service account와
APNs private key는 app target에 주입하지 않는다. 구체적인 변수와 승격 조건은 release
runbook을 따른다.

실제 local/release 입력은 ignored `apps/ios/.env.local`과 `apps/ios/.env.production`에서 관리하고
commit되는 `.example` 두 파일은 key schema만 소유한다. Dotenv는 shell에서 source하지 않는다.

```bash
apps/ios/scripts/validate-env.zsh --kind local apps/ios/.env.local
apps/ios/scripts/validate-env.zsh --kind production apps/ios/.env.production

# 실제 값을 채웠다면 archive/export까지 검증하고 Apple에는 올리지 않는다.
# Placeholder 상태에서는 schema/toolchain/export option만 검증한다.
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

실제 TestFlight upload는 검증된 `main`에서 GitHub의 `iOS TestFlight` workflow를 수동 실행한다.
Production API host, App Store Connect key, Apple Distribution PKCS#12/password/profile과 Firebase
plist는 repository file이 아니라 GitHub environment secret에서 runner 임시 파일로 복원한다.

## Build와 test

Repository root에서 실행한다.

```bash
xcodebuild -resolvePackageDependencies \
  -project apps/ios/Woorisai.xcodeproj \
  -scheme Woorisai

xcodebuild test \
  -project apps/ios/Woorisai.xcodeproj \
  -scheme WoorisaiAPI \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=26.5' \
  -skipPackagePluginValidation

xcodebuild test \
  -project apps/ios/Woorisai.xcodeproj \
  -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=26.5' \
  -derivedDataPath .local/ios-derived-15 \
  -skipPackagePluginValidation

xcodebuild test \
  -project apps/ios/Woorisai.xcodeproj \
  -scheme Woorisai \
  -destination 'platform=iOS Simulator,name=iPhone 13 Pro,OS=26.5' \
  -derivedDataPath .local/ios-derived-13 \
  -skipPackagePluginValidation

xcodebuild build \
  -project apps/ios/Woorisai.xcodeproj \
  -scheme Woorisai \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -skipPackagePluginValidation
```

`-skipPackagePluginValidation`은 exact pin한 OpenAPI build plugin을 non-interactive CLI에서
실행하기 위한 project-local 옵션이다. 전역 plugin trust 설정은 바꾸지 않는다.

Simulator는 generated client, feature state, navigation과 접근성 회귀를 검증한다. Signing,
실제 Basic API, R2, FID/APNs, background와 privacy snapshot은 같은 archive를 실제 기기에서
검증해야 하며 simulator 결과로 대체하지 않는다.

## UI smoke

CI `Verify`는 iOS unit/API test만 실행한다. 화면 회귀는 다음 script로 로컬에서 확인하고,
UI에 영향 있는 변경은 merge 전에 통과 결과를 남긴다.

```bash
apps/ios/scripts/ui-smoke.zsh          # 화면 2종의 핵심 smoke 6개
apps/ios/scripts/ui-smoke.zsh --full   # 화면 2종의 전체 WoorisaiUITests
```

## 선택적 화면 캡처

Debug app을 만든 뒤 login-options 상태별 framebuffer를 다음 script로 저장할 수 있다.

```bash
apps/ios/scripts/capture-login-options-ui.zsh \
  'iPhone 15 Pro' \
  '.local/ios-derived-15/Build/Products/Debug-iphonesimulator/Woorisai.app' \
  '.local/ios-ui-15'
apps/ios/scripts/capture-login-options-ui.zsh \
  'iPhone 13 Pro' \
  '.local/ios-derived-13/Build/Products/Debug-iphonesimulator/Woorisai.app' \
  '.local/ios-ui-13'
```

두 capture는 순서대로 실행한다. 결과는 `.local/`의 검토용 생성물이며 commit하지 않는다.
Framebuffer 검토는 semantic XCTest나 실제 backend E2E의 대체가 아니다.
