import SwiftUI
import WoorisaiAPI

struct LoginOptionsView: View {
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: LoginOptionsModel
  @State private var authenticationModel: AuthenticationModel
  @FocusState private var isPINFocused: Bool

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
          stateContent
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 20 : 24)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 24 : 40)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
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
    }
    .onDisappear {
      isPINFocused = false
      model.cancel()
    }
    .onChange(of: authenticationModel.state) { _, state in
      switch state {
      case .enteringPIN:
        isPINFocused = true
      case .choosingParticipant, .validating, .credentialRejected, .unavailable, .failed,
        .authenticated:
        isPINFocused = false
      }
    }
    .onChange(of: authenticationModel.pin) { _, pin in
      if pin.count == 4 {
        isPINFocused = false
      }
    }
    .toolbar {
      KeyboardDismissToolbar {
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
      ZStack {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .fill(WoorisaiPalette.surface)
          .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
              .stroke(WoorisaiPalette.coral.opacity(0.16), lineWidth: 1)
          }
          .shadow(color: WoorisaiPalette.shadow.opacity(0.12), radius: 12, y: 6)

        Image(systemName: "heart.fill")
          .font(
            .system(
              size: dynamicTypeSize.isAccessibilitySize ? 24 : 32,
              weight: .semibold
            )
          )
          .foregroundStyle(WoorisaiPalette.coral)
          .rotationEffect(.degrees(4))
      }
      .frame(
        width: dynamicTypeSize.isAccessibilitySize ? 52 : 72,
        height: dynamicTypeSize.isAccessibilitySize ? 52 : 72
      )
      .rotationEffect(.degrees(-4))
      .accessibilityHidden(true)

      Eyebrow("JUST BETWEEN US")

      Text("우리 둘만의 작은 마음 기록")
        .font(dynamicTypeSize.isAccessibilitySize ? .title.bold() : .largeTitle.bold())
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.center)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 440 : 300)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityAddTraits(.isHeader)

      Text("서로를 생각하는 마음을 차곡차곡 쌓아 보세요.")
        .font(.body)
        .foregroundStyle(WoorisaiPalette.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 440 : 320)
    }
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
          .accessibilityIdentifier("authentication.rejected")
      } else if case .unavailable = authenticationModel.state {
        Text("인증 서비스를 잠시 사용할 수 없어요. 잠시 후 다시 시도해 주세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .accessibilityIdentifier("authentication.unavailable")
      } else if case .failed = authenticationModel.state {
        Text("인증 결과를 확인하지 못했어요. 자동으로 다시 보내지 않았습니다.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .accessibilityIdentifier("authentication.failed")
      }

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
      .padding(.horizontal, 16)
      .frame(minHeight: 54)
      .background(
        WoorisaiPalette.field,
        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(WoorisaiPalette.line, lineWidth: 1)
      }
      .privacySensitive()
      .disabled(authenticationModel.isValidating)
      .focused($isPINFocused)
      .accessibilityLabel("네 자리 PIN")
      .accessibilityHint("숫자 네 자리를 입력하세요")
      .accessibilityIdentifier("authentication.pin")

      Text("숫자 네 자리를 입력해 주세요.")
        .font(.footnote)
        .foregroundStyle(WoorisaiPalette.muted)

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

      pinActions
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
  private var pinActions: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(spacing: 12) {
        cancelPINButton(expandsHorizontally: true)
        authenticationActionButton
      }
    } else {
      HStack(spacing: 12) {
        cancelPINButton(expandsHorizontally: false)
        authenticationActionButton
      }
    }
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
