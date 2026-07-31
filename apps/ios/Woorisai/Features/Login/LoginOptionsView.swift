import SwiftUI
import WoorisaiAPI

struct LoginOptionsView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: LoginOptionsModel
  @State private var authenticationModel: AuthenticationModel
  @FocusState private var isPINFocused: Bool
  @AccessibilityFocusState private var isLoginFailureFocused: Bool
  @AccessibilityFocusState private var isAuthenticationFailureFocused: Bool
  /// True when this screen mounted with a participant already selected — the 401
  /// re-authentication flow, where PIN entry must not depend on the options reload.
  @State private var isReauthenticatingSession = false

  @MainActor
  init(model: LoginOptionsModel, authenticationModel: AuthenticationModel) {
    _model = State(initialValue: model)
    _authenticationModel = State(initialValue: authenticationModel)
  }

  var body: some View {
    WarmBackground {
      ScrollView {
        VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 20 : 26) {
          brandHeader
          if let notice = authenticationModel.storedSessionNotice {
            storedSessionNoticeView(notice)
          }
          stateContent
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 20 : 24)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 24 : 40)
        .frame(maxWidth: .infinity)
        .dismissesKeyboardOnBackgroundTap()
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if authenticationModel.selectedOption != nil {
        loginActionBar
      }
    }
    .overlay {
      #if DEBUG
        VStack(spacing: 0) {
          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(dynamicTypeVerificationValue)
            .accessibilityIdentifier("loginOptions.dynamicTypeSize")

          Color.clear
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel(colorScheme == .dark ? "dark" : "light")
            .accessibilityIdentifier("loginOptions.colorScheme")
        }
        .allowsHitTesting(false)
      #endif
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("loginOptions.screen")
    .onAppear {
      isReauthenticatingSession = authenticationModel.selectedOption != nil
    }
    .task {
      model.loadIfNeeded()
      await authenticationModel.refreshRememberOption()
    }
    .onDisappear {
      isPINFocused = false
      isLoginFailureFocused = false
      isAuthenticationFailureFocused = false
      model.cancel()
    }
    .onChange(of: model.state, initial: true) { _, state in
      switch state {
      case .unavailable, .failed:
        Task { @MainActor in
          await Task.yield()
          isLoginFailureFocused = true
        }
      case .idle, .loading, .loaded:
        isLoginFailureFocused = false
      }
    }
    .onChange(of: authenticationModel.pin) { _, _ in
      autoSubmitCompletePIN()
    }
    .onChange(of: authenticationModel.state, initial: true) { _, state in
      switch state {
      case .enteringPIN:
        isAuthenticationFailureFocused = false
        isPINFocused = true
      case .credentialRejected:
        // The user retypes immediately after a rejected PIN — keep the keyboard up so the retry
        // does not need an extra tap on the field. VoiceOver still gets the failure message.
        Task { @MainActor in
          await Task.yield()
          isAuthenticationFailureFocused = true
          isPINFocused = true
        }
      case .unavailable, .failed:
        isPINFocused = false
        Task { @MainActor in
          await Task.yield()
          isAuthenticationFailureFocused = true
        }
      case .choosingParticipant, .validating, .authenticated,
        .restoring, .locked, .unlocking:
        isAuthenticationFailureFocused = false
        isPINFocused = false
      }
    }
  }

  /// A 4-digit PIN is complete by construction — `updatePIN` refuses a fifth digit — so the fourth
  /// keystroke IS the submit intent, the same as iOS's own passcode field. Requiring a separate
  /// button tap only added a keyboard dismissal and a scroll to every single login.
  ///
  /// Deliberately limited to `.enteringPIN`. `.unavailable`/`.failed` promise the user that an
  /// unknown authentication result is never resent automatically, so those states keep the explicit
  /// 다시 시도 button. `.credentialRejected` clears the PIN, so retyping four digits re-arms this.
  private func autoSubmitCompletePIN() {
    guard case .enteringPIN = authenticationModel.state,
      authenticationModel.canSubmit
    else { return }
    authenticationModel.submit()
    isPINFocused = false
  }

  #if DEBUG
    private var dynamicTypeVerificationValue: String {
      dynamicTypeSize == .accessibility5
        ? "accessibility-extra-extra-extra-large"
        : "not-accessibility-extra-extra-extra-large"
    }
  #endif

  private var brandHeader: some View {
    VStack(spacing: dynamicTypeSize.isAccessibilitySize ? 8 : 10) {
      if !dynamicTypeSize.isAccessibilitySize {
        ZStack {
          RoundedRectangle(cornerRadius: WoorisaiRadius.large, style: .continuous)
            .fill(WoorisaiColor.Bg.layerDefault)
            .overlay {
              RoundedRectangle(cornerRadius: WoorisaiRadius.large, style: .continuous)
                .stroke(WoorisaiColor.Stroke.brandSubtle, lineWidth: 1)
            }
            .woorisaiShadow(.s2)

          Image(systemName: "heart.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(WoorisaiColor.Fg.brandVivid)
            .rotationEffect(.degrees(4))
        }
        .frame(width: 72, height: 72)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)

        Eyebrow("JUST BETWEEN US")
      }

      Text("우리 둘만의 작은 마음 기록")
        .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
        .foregroundStyle(WoorisaiColor.Fg.neutral)
        .multilineTextAlignment(.center)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 440 : 300)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if !dynamicTypeSize.isAccessibilitySize {
        Text("서로를 생각하는 마음을 차곡차곡 쌓아 보세요.")
          .font(.body)
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 320)
      }
    }
  }

  /// Why the stored session ended on its own — without this, a launch that used to Face-ID-unlock
  /// silently lands on the participant chooser and reads as a broken app.
  private func storedSessionNoticeView(_ notice: StoredSessionNotice) -> some View {
    let message: String
    switch notice {
    case .invalidated:
      message = "Face ID 정보가 바뀌어 저장해 둔 로그인을 초기화했어요. PIN으로 다시 들어와 주세요."
    case .rejected:
      message = "저장해 둔 로그인 정보가 더 이상 맞지 않아 초기화했어요. PIN으로 다시 들어와 주세요."
    }
    return Label(message, systemImage: "info.circle")
    .font(.callout)
    .foregroundStyle(WoorisaiColor.Fg.neutral)
    .padding(WoorisaiSpacing.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      WoorisaiColor.Bg.brandWeakAlpha,
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("loginOptions.sessionNotice")
  }

  @ViewBuilder
  private var stateContent: some View {
    if isReauthenticatingSession, let selectedOption = authenticationModel.selectedOption {
      // A preserved participant selection (server rejected the stored credential mid-session)
      // must render the PIN field immediately — never behind the options reload, which may be
      // the very request that is failing offline. It also lives ONLY here during the whole
      // re-authentication: hosting it inside loadedState as usual would recreate the field the
      // moment the reload finishes, dropping focus and the keyboard mid-retype.
      VStack(spacing: WoorisaiSpacing.medium) {
        WarmSurface(cornerRadius: WoorisaiRadius.large) {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
            pinEntry(selectedOption)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(WoorisaiSpacing.large)
        }
        optionsStateBody(includesPINEntry: false)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("loginOptions.reauthenticating")
    } else {
      optionsStateBody(includesPINEntry: true)
    }
  }

  @ViewBuilder
  private func optionsStateBody(includesPINEntry: Bool) -> some View {
    switch model.state {
    case .idle:
      progressState(
        message: "로그인 정보를 준비하고 있어요.",
        identifier: "loginOptions.idle"
      )
    case .loading:
      progressState(
        message: "두 사람의 이름을 불러오고 있어요.",
        identifier: "loginOptions.loading"
      )
    case .loaded(let options):
      loadedState(options: options, includesPINEntry: includesPINEntry)
    case .unavailable:
      retryState(
        message: "지금은 로그인할 사람을 확인할 수 없어요. 잠시 후 다시 시도해 주세요.",
        identifier: "loginOptions.unavailable"
      )
    case .failed:
      retryState(
        message: "로그인 정보를 불러오지 못했어요. 네트워크 연결을 확인하고 다시 시도해 주세요.",
        identifier: "loginOptions.failed"
      )
    }
  }

  private func progressState(message: String, identifier: String) -> some View {
    BrandedStateCard {
      VStack(spacing: WoorisaiSpacing.regular) {
        ProgressView()
          .controlSize(.large)
          .tint(WoorisaiColor.Fg.brand)
          .accessibilityHidden(true)
        Text(message)
          .multilineTextAlignment(.center)
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message)
    .accessibilityIdentifier(identifier)
  }

  private func loadedState(options: [LoginOption], includesPINEntry: Bool) -> some View {
    VStack(spacing: WoorisaiSpacing.medium) {
      WarmSurface(cornerRadius: WoorisaiRadius.large) {
        VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
          Text("누구인가요?")
            .font(.title2.bold())
            .foregroundStyle(WoorisaiColor.Fg.neutral)
            .accessibilityAddTraits(.isHeader)

          LazyVGrid(columns: participantColumns, spacing: WoorisaiSpacing.medium) {
            ForEach(options, id: \.slot) { option in
              participantButton(option)
            }
          }

          if includesPINEntry, let selectedOption = authenticationModel.selectedOption {
            pinEntry(selectedOption)
          }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(WoorisaiSpacing.large)
      }

      Label("두 사람만 들어올 수 있는 비밀 공간이에요.", systemImage: "sparkles")
        .font(.footnote.weight(.medium))
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("loginOptions.loaded")
  }

  private var participantColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible(), spacing: WoorisaiSpacing.medium)]
    }
    return [
      GridItem(.flexible(), spacing: WoorisaiSpacing.medium),
      GridItem(.flexible(), spacing: WoorisaiSpacing.medium),
    ]
  }

  private func participantButton(_ option: LoginOption) -> some View {
    let isSelected = authenticationModel.selectedOption?.slot == option.slot

    return Button {
      isPINFocused = false
      Task {
        await authenticationModel.select(option)
      }
    } label: {
      VStack(spacing: WoorisaiSpacing.small) {
        ParticipantAvatar(name: option.displayName, size: 48)

        Text(option.displayName)
          .font(.headline)
          .foregroundStyle(isSelected ? WoorisaiColor.Fg.neutral : WoorisaiColor.Fg.neutralMuted)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 92)
      .padding(WoorisaiSpacing.medium)
      .background(
        isSelected ? WoorisaiColor.Bg.selected : WoorisaiColor.Bg.layerFill,
        in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
          .stroke(
            isSelected ? WoorisaiColor.Stroke.brandSolid : WoorisaiColor.Stroke.neutralWeak,
            lineWidth: isSelected ? 2 : 1
          )
      }
      .shadow(
        color: isSelected ? WoorisaiColor.Component.SelectableCard.glow : .clear,
        radius: 8,
        y: 3
      )
      .contentShape(RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(option.displayName)
    .accessibilityValue(isSelected ? "선택됨" : "")
    .accessibilityIdentifier("loginOptions.participant.\(option.slot)")
  }

  private func pinEntry(_ option: LoginOption) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
      Text("\(option.displayName)님의 PIN")
        .font(.headline)
        .foregroundStyle(WoorisaiColor.Fg.neutral)
        .accessibilityAddTraits(.isHeader)

      if case .credentialRejected = authenticationModel.state {
        Text("PIN이 맞지 않아요. 네 자리 PIN을 다시 입력해 주세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiColor.Fg.brand)
          .accessibilityFocused($isAuthenticationFailureFocused)
          .accessibilityIdentifier("authentication.rejected")
      } else if case .unavailable = authenticationModel.state {
        Text("인증 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          .accessibilityFocused($isAuthenticationFailureFocused)
          .accessibilityIdentifier("authentication.unavailable")
      } else if case .failed = authenticationModel.state {
        Text("인증 결과를 확인하지 못했어요. 자동으로 다시 보내지 않았습니다.")
          .font(.callout)
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          .accessibilityFocused($isAuthenticationFailureFocused)
          .accessibilityIdentifier("authentication.failed")
      }

      HStack(spacing: WoorisaiSpacing.small) {
        SecureField(
          "네 자리 PIN",
          text: Binding(
            get: { authenticationModel.pin },
            set: { authenticationModel.updatePIN($0) }
          )
        )
        .keyboardType(.numberPad)
        .textContentType(.password)
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
        .tint(WoorisaiColor.Fg.brand)
        .padding(.horizontal, WoorisaiSpacing.regular)
        .frame(minHeight: WoorisaiControlMetric.primaryHeight)
        .background(
          WoorisaiColor.Bg.layerFill,
          in: RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
            .stroke(WoorisaiColor.Stroke.neutralWeak, lineWidth: 1)
        }
        .privacySensitive()
        .disabled(authenticationModel.isValidating)
        .focused($isPINFocused)
        .accessibilityLabel("네 자리 PIN")
        .accessibilityHint("숫자 네 자리를 입력하세요")
        .accessibilityIdentifier("authentication.pin")
      }

      Text("숫자 네 자리를 입력해 주세요.")
        .font(.footnote)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)

      if authenticationModel.canOfferRemembering {
        Toggle("다음부터 Face ID로 빠르게 열기", isOn: $authenticationModel.remembersSession)
          .tint(WoorisaiColor.Fg.brandVivid)
          .font(.footnote.weight(.medium))
          .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
          .accessibilityIdentifier("authentication.rememberSession")
      }

      if authenticationModel.isValidating {
        HStack(spacing: WoorisaiSpacing.small) {
          ProgressView()
            .tint(WoorisaiColor.Fg.brand)
          Text("PIN을 확인하고 있어요.")
            .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("authentication.validating")
      }

    }
    .padding(WoorisaiSpacing.regular)
    .background(
      WoorisaiColor.Bg.brandSubtle,
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("authentication.pinEntry")
  }

  @ViewBuilder
  private var loginActionBar: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: WoorisaiSpacing.small) {
          cancelPINButton(expandsHorizontally: true)
          authenticationActionButton
        }
      } else {
        HStack(spacing: WoorisaiSpacing.medium) {
          cancelPINButton(expandsHorizontally: false)
          authenticationActionButton
        }
      }
    }
    .frame(maxWidth: 520)
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.small)
    .frame(maxWidth: .infinity)
    .background(.ultraThinMaterial)
    .overlay(alignment: .top) {
      Divider().opacity(0.5)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("authentication.actionBar")
  }

  private func cancelPINButton(expandsHorizontally: Bool) -> some View {
    Button("취소") {
      isPINFocused = false
      Task {
        await authenticationModel.cancel()
      }
    }
    .font(.headline.weight(.semibold))
    .foregroundStyle(WoorisaiColor.Fg.brand)
    .padding(.horizontal, WoorisaiSpacing.regular)
    .frame(
      maxWidth: expandsHorizontally ? .infinity : nil,
      minHeight: WoorisaiControlMetric.secondaryHeight
    )
    .background(
      WoorisaiColor.Bg.layerFill,
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
        .stroke(WoorisaiColor.Stroke.neutralWeak, lineWidth: 1)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("authentication.cancel")
  }

  @ViewBuilder
  private var authenticationActionButton: some View {
    if case .unavailable = authenticationModel.state {
      PrimaryHeartButton("다시 시도", isEnabled: authenticationModel.canSubmit) {
        isPINFocused = false
        authenticationModel.retry()
      }
      .accessibilityIdentifier("authentication.retry")
    } else if case .failed = authenticationModel.state {
      PrimaryHeartButton("다시 시도", isEnabled: authenticationModel.canSubmit) {
        isPINFocused = false
        authenticationModel.retry()
      }
      .accessibilityIdentifier("authentication.retry")
    } else {
      PrimaryHeartButton(
        "마음 공간으로 들어가기",
        isEnabled: authenticationModel.canSubmit,
        isLoading: authenticationModel.isValidating
      ) {
        isPINFocused = false
        authenticationModel.submit()
      }
      .accessibilityIdentifier("authentication.submit")
    }
  }

  private func retryState(message: String, identifier: String) -> some View {
    BrandedStateCard {
      VStack(spacing: WoorisaiSpacing.regular) {
        Image(systemName: "exclamationmark.icloud")
          .font(.system(size: 34))
          .foregroundStyle(WoorisaiColor.Fg.brand)
          .accessibilityHidden(true)

        Text(message)
          .foregroundStyle(WoorisaiColor.Fg.neutral)
          .multilineTextAlignment(.center)
          .accessibilityFocused($isLoginFailureFocused)

        PrimaryHeartButton("다시 시도") {
          model.retry()
        }
        .accessibilityIdentifier("loginOptions.retry")
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }
}
