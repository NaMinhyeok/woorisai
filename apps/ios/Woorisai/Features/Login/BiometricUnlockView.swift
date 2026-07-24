import SwiftUI

struct BiometricUnlockView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var authenticationModel: AuthenticationModel
  @State private var hasTriggeredAutoUnlock = false

  @MainActor
  init(authenticationModel: AuthenticationModel) {
    _authenticationModel = State(initialValue: authenticationModel)
  }

  var body: some View {
    WarmBackground {
      VStack(spacing: WoorisaiSpacing.large) {
        brandMark
        content
      }
      .frame(maxWidth: 420)
      .padding(.horizontal, WoorisaiSpacing.large)
      .padding(.vertical, WoorisaiSpacing.xLarge)
      .frame(maxWidth: .infinity)
    }
    .onAppear { triggerAutoUnlockIfNeeded() }
    .onChange(of: authenticationModel.state) { _, _ in
      // Launch-time restore usually settles into `.locked` after the scene is already active, so
      // neither `onAppear` (still `.restoring`) nor the scenePhase change can fire the first
      // prompt. Re-arming is unaffected: a post-failure `.locked` is blocked by the trigger flag.
      triggerAutoUnlockIfNeeded()
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .background {
        // A real background cycle (home / app switcher) re-arms auto-unlock, so returning to a
        // locked app re-presents Face ID — the common iOS pattern. The biometric sheet only drives
        // the app to `.inactive`, never `.background`, so it can't re-arm and double-prompt.
        hasTriggeredAutoUnlock = false
      } else {
        triggerAutoUnlockIfNeeded()
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("biometricUnlock.screen")
  }

  private var brandMark: some View {
    VStack(spacing: WoorisaiSpacing.small) {
      Image(systemName: "lock.heart")
        .font(.system(size: 40, weight: .semibold))
        .foregroundStyle(WoorisaiPalette.coral)
        .accessibilityHidden(true)
      Text("우리 둘만의 공간이 잠겨 있어요")
        .font(.title2.bold())
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
    }
  }

  @ViewBuilder
  private var content: some View {
    switch authenticationModel.state {
    case .restoring:
      progress(message: "세션을 확인하고 있어요.", identifier: "biometricUnlock.restoring")
    case .unlocking:
      progress(message: "잠금을 해제하고 있어요.", identifier: "biometricUnlock.unlocking")
    case .locked(let context):
      lockedContent(context)
    default:
      // AppRootView only shows this view while awaiting unlock; other states are transient.
      Color.clear.frame(height: 0)
    }
  }

  private func lockedContent(_ context: BiometricUnlockContext) -> some View {
    VStack(spacing: WoorisaiSpacing.regular) {
      if let message = failureMessage(context.lastFailure) {
        Text(message)
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.coralDark)
          .multilineTextAlignment(.center)
          .accessibilityIdentifier("biometricUnlock.failure")
      } else {
        Text("\(unlockModalityName(context.kind))로 안전하게 다시 들어오세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .multilineTextAlignment(.center)
      }

      PrimaryHeartButton(unlockButtonTitle(context.kind)) {
        authenticationModel.unlock()
      }
      .accessibilityIdentifier("biometricUnlock.unlock")

      Button("PIN으로 들어가기") {
        Task { await authenticationModel.fallBackToPINLogin() }
      }
      .font(.headline.weight(.semibold))
      .foregroundStyle(WoorisaiPalette.coralDark)
      .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
      .accessibilityIdentifier("biometricUnlock.usePIN")
    }
  }

  private func progress(message: String, identifier: String) -> some View {
    BrandedStateCard {
      VStack(spacing: WoorisaiSpacing.regular) {
        ProgressView()
          .controlSize(.large)
          .tint(WoorisaiPalette.coralDark)
          .accessibilityHidden(true)
        Text(message)
          .foregroundStyle(WoorisaiPalette.muted)
          .multilineTextAlignment(.center)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message)
    .accessibilityIdentifier(identifier)
  }

  private func triggerAutoUnlockIfNeeded() {
    // Fire once, only from a settled `.locked` state while the scene is active. A failed unlock
    // returns to `.locked(failure)` but must NOT auto-retrigger — the user retries deliberately,
    // and this also prevents a duplicate prompt when the biometric sheet churns `scenePhase`.
    guard !hasTriggeredAutoUnlock,
      scenePhase == .active,
      case .locked = authenticationModel.state
    else { return }
    hasTriggeredAutoUnlock = true
    authenticationModel.unlock()
  }

  private func failureMessage(_ failure: BiometricUnlockFailure?) -> String? {
    switch failure {
    case .none:
      nil
    case .cancelled:
      "잠금 해제를 취소했어요. 다시 시도하거나 PIN으로 들어갈 수 있어요."
    case .offline:
      "지금은 서버에 연결할 수 없어요. 잠시 후 다시 시도하거나 PIN으로 들어가 주세요."
    case .failed:
      "잠금을 해제하지 못했어요. 다시 시도하거나 PIN으로 들어가 주세요."
    }
  }

  private func unlockModalityName(_ kind: BiometricKind) -> String {
    switch kind {
    case .faceID: "Face ID"
    case .touchID: "Touch ID"
    case .opticID: "Optic ID"
    case .none: "생체인증"
    }
  }

  private func unlockButtonTitle(_ kind: BiometricKind) -> LocalizedStringKey {
    switch kind {
    case .faceID: "Face ID로 열기"
    case .touchID: "Touch ID로 열기"
    case .opticID: "Optic ID로 열기"
    case .none: "생체인증으로 열기"
    }
  }
}
