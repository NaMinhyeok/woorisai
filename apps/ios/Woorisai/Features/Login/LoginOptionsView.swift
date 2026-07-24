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
      }
      .scrollDismissesKeyboard(.interactively)
    }
    .keyboardDoneToolbar()
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
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(WoorisaiPalette.surface)
            .overlay {
              RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(WoorisaiPalette.coral.opacity(0.16), lineWidth: 1)
            }
            .shadow(color: WoorisaiPalette.shadow.opacity(0.12), radius: 12, y: 6)

          Image(systemName: "heart.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(WoorisaiPalette.coral)
            .rotationEffect(.degrees(4))
        }
        .frame(width: 72, height: 72)
        .rotationEffect(.degrees(-4))
        .accessibilityHidden(true)

        Eyebrow("JUST BETWEEN US")
      }

      Text("우리 둘만의 작은 마음 기록")
        .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 440 : 300)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      if !dynamicTypeSize.isAccessibilitySize {
        Text("서로를 생각하는 마음을 차곡차곡 쌓아 보세요.")
          .font(.body)
          .foregroundStyle(WoorisaiPalette.muted)
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
    .foregroundStyle(WoorisaiPalette.ink)
    .padding(WoorisaiSpacing.regular)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      WoorisaiPalette.coralSoft.opacity(0.5),
      in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("loginOptions.sessionNotice")
  }

  @ViewBuilder
  private var stateContent: some View {
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
      loadedState(options: options)
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
      VStack(spacing: 16) {
        ProgressView()
          .controlSize(.large)
          .tint(WoorisaiPalette.coralDark)
          .accessibilityHidden(true)
        Text(message)
          .multilineTextAlignment(.center)
          .foregroundStyle(WoorisaiPalette.muted)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(message)
    .accessibilityIdentifier(identifier)
  }

  private func loadedState(options: [LoginOption]) -> some View {
    VStack(spacing: 14) {
      WarmSurface(cornerRadius: 22) {
        VStack(alignment: .leading, spacing: 18) {
          Text("누구인가요?")
            .font(.title2.bold())
            .foregroundStyle(WoorisaiPalette.ink)
            .accessibilityAddTraits(.isHeader)

          LazyVGrid(columns: participantColumns, spacing: 12) {
            ForEach(options, id: \.slot) { option in
              participantButton(option)
            }
          }

          if let selectedOption = authenticationModel.selectedOption {
            pinEntry(selectedOption)
          }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
      }

      Label("두 사람만 들어올 수 있는 비밀 공간이에요.", systemImage: "sparkles")
        .font(.footnote.weight(.medium))
        .foregroundStyle(WoorisaiPalette.muted)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("loginOptions.loaded")
  }

  private var participantColumns: [GridItem] {
    if dynamicTypeSize.isAccessibilitySize {
      return [GridItem(.flexible(), spacing: 12)]
    }
    return [
      GridItem(.flexible(), spacing: 12),
      GridItem(.flexible(), spacing: 12),
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
      VStack(spacing: 9) {
        ParticipantAvatar(name: option.displayName, size: 48)

        Text(option.displayName)
          .font(.headline)
          .foregroundStyle(isSelected ? WoorisaiPalette.ink : WoorisaiPalette.muted)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, minHeight: 92)
      .padding(12)
      .background(
        isSelected ? WoorisaiPalette.selectedSurface : WoorisaiPalette.field,
        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
          .stroke(
            isSelected ? WoorisaiPalette.coral : WoorisaiPalette.line,
            lineWidth: isSelected ? 2 : 1
          )
      }
      .shadow(
        color: isSelected ? WoorisaiPalette.coral.opacity(0.09) : .clear,
        radius: 8,
        y: 3
      )
      .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(option.displayName)
    .accessibilityValue(isSelected ? "선택됨" : "")
    .accessibilityIdentifier("loginOptions.participant.\(option.slot)")
  }

  private func pinEntry(_ option: LoginOption) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("\(option.displayName)님의 PIN")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
        .accessibilityAddTraits(.isHeader)

      if case .credentialRejected = authenticationModel.state {
        Text("PIN이 맞지 않아요. 네 자리 PIN을 다시 입력해 주세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.coralDark)
          .accessibilityFocused($isAuthenticationFailureFocused)
          .accessibilityIdentifier("authentication.rejected")
      } else if case .unavailable = authenticationModel.state {
        Text("인증 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .accessibilityFocused($isAuthenticationFailureFocused)
          .accessibilityIdentifier("authentication.unavailable")
      } else if case .failed = authenticationModel.state {
        Text("인증 결과를 확인하지 못했어요. 자동으로 다시 보내지 않았습니다.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
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
        .foregroundStyle(WoorisaiPalette.ink)
        .tint(WoorisaiPalette.coralDark)
        .padding(.horizontal, WoorisaiSpacing.regular)
        .frame(minHeight: 54)
        .background(
          WoorisaiPalette.field,
          in: RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
        )
        .overlay {
          RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
            .stroke(WoorisaiPalette.line, lineWidth: 1)
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
        .foregroundStyle(WoorisaiPalette.muted)

      if authenticationModel.canOfferRemembering {
        Toggle("다음부터 Face ID로 빠르게 열기", isOn: $authenticationModel.remembersSession)
          .tint(WoorisaiPalette.coral)
          .font(.footnote.weight(.medium))
          .foregroundStyle(WoorisaiPalette.muted)
          .accessibilityIdentifier("authentication.rememberSession")
      }

      if authenticationModel.isValidating {
        HStack(spacing: 10) {
          ProgressView()
            .tint(WoorisaiPalette.coralDark)
          Text("PIN을 확인하고 있어요.")
            .foregroundStyle(WoorisaiPalette.muted)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("authentication.validating")
      }

    }
    .padding(16)
    .background(
      WoorisaiPalette.coralSoft.opacity(0.34),
      in: RoundedRectangle(cornerRadius: 18, style: .continuous)
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
    .foregroundStyle(WoorisaiPalette.coralDark)
    .padding(.horizontal, 16)
    .frame(maxWidth: expandsHorizontally ? .infinity : nil, minHeight: 48)
    .background(
      WoorisaiPalette.field,
      in: RoundedRectangle(cornerRadius: 14, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WoorisaiPalette.line, lineWidth: 1)
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
      VStack(spacing: 20) {
        Image(systemName: "exclamationmark.icloud")
          .font(.system(size: 34))
          .foregroundStyle(WoorisaiPalette.coralDark)
          .accessibilityHidden(true)

        Text(message)
          .foregroundStyle(WoorisaiPalette.ink)
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
