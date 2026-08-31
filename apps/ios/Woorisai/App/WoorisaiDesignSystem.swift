import SwiftUI
import UIKit

enum WoorisaiSpacing {
  static let xSmall: CGFloat = 4
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let regular: CGFloat = 16
  static let large: CGFloat = 24
  static let xLarge: CGFloat = 32
  static let screenGutter: CGFloat = regular
}

/// 모서리 반경 스케일.
///
/// 호출부에 3부터 24까지 여덟 가지 값이 흩어져 있던 것을 네 단으로 접었다. 반경이 2pt 다른 두
/// 카드는 나란히 놓아도 구분되지 않는데, 값이 다르면 다음 사람은 그 차이에 이유가 있다고 믿게
/// 된다.
enum WoorisaiRadius {
  /// 마스킹 테이프처럼 아주 작은 조각.
  static let xSmall: CGFloat = 4
  /// 버튼·칩.
  static let small: CGFloat = 12
  /// 카드·필드·말풍선.
  static let medium: CGFloat = 18
  /// 큰 카드·시트.
  static let large: CGFloat = 24
}

/// 컨트롤 높이 3단.
enum WoorisaiControlMetric {
  /// HIG가 요구하는 최소 탭 영역. 아이콘 버튼처럼 시각적으로 작은 컨트롤의 하한이다.
  static let minimumTapTarget: CGFloat = 44
  /// 보조 버튼.
  static let secondaryHeight: CGFloat = 48
  /// 주요 액션 버튼과 텍스트 필드. 둘을 같은 높이로 두면 나란히 놓았을 때 정렬이 맞는다.
  static let primaryHeight: CGFloat = 52
  static let mediaGap: CGFloat = WoorisaiSpacing.small
}

enum SubmittedDraftEditingPolicy {
  static func isLocked(
    isSubmitting: Bool,
    requiresOutcomeConfirmation: Bool
  ) -> Bool {
    isSubmitting || requiresOutcomeConfirmation
  }
}

/// 글자수 카운터의 표시 판단.
///
/// 카운터를 항상 띄우면 "0/500"처럼 정보가 없는 상태가 늘 자리를 차지한다. 키보드 위 입력
/// 바에서는 그 대가가 특히 컸다 — 카운터 하나가 행 하나를 온전히 점유했다. 한도에 가까워질
/// 때만 등장하도록 시점을 여기서 정한다.
///
/// 화면마다 한도가 다르다(이유 200자, 점수·일기 댓글 500자, 일기 본문은 또 다르다). 판단을
/// 각 View에 두면 같은 앱 안에서 어떤 필드는 이르게, 어떤 필드는 늦게 나타난다. 표시 여부와
/// 초과 판정을 한 타입에 모아 View는 결과만 그린다.
struct CharacterBudget: Equatable {
  let used: Int
  let limit: Int

  init(used: Int, limit: Int) {
    self.used = used
    self.limit = limit
  }

  /// 남은 글자 수. 한도를 넘으면 음수다 — 몇 자를 줄여야 하는지 보여주려고 0으로 자르지 않는다.
  var remaining: Int { limit - used }

  /// 제출을 막아야 하는 상태.
  var isExceeded: Bool { remaining < 0 }

  /// 카운터를 화면에 둘지. `false`면 View는 아무 공간도 차지하지 않는다.
  ///
  /// 비율과 절대 수 중 **작은 쪽**을 임계값으로 쓴다. 비율만 쓰면 500자 필드가 75자 남은
  /// 시점에 등장하는데 그때는 아직 문장 여러 개를 더 쓸 수 있어 경고가 이르다. 절대 수만 쓰면
  /// 200자 필드에서 한도의 20%를 남기고 뜨는 반면 500자 필드는 8%에서 떠서 같은 숫자가 다른
  /// 촉박함을 뜻하게 된다. 둘의 최소값은 "비율로도 촉박하고 남은 글자로도 촉박할 때"만 고른다.
  ///
  /// `limit`이 0 이하면 초과로 보이더라도 숨는다. 그것은 사용자가 많이 쓴 상황이 아니라 한도를
  /// 넘겨받지 못한 설정 문제이고, 그때 음수를 띄우면 사용자가 고칠 수 없는 수를 보게 된다.
  var isVisible: Bool {
    guard limit > 0 else { return false }
    guard !isExceeded else { return true }
    let proportionalThreshold = Int((Double(limit) * Self.proportionalShare).rounded(.down))
    return remaining <= min(proportionalThreshold, Self.absoluteThreshold)
  }

  /// 한도의 15%. 짧은 필드에서 임계값을 지배한다.
  private static let proportionalShare = 0.15
  /// 40자. 긴 필드에서 임계값을 지배한다 — 한 문장을 더 쓸 여유가 남은 지점이다.
  private static let absoluteThreshold = 40

  /// 카운터에 그릴 문자열.
  var displayText: String { "\(remaining)" }

  /// 카운터가 숨어 있어도 VoiceOver는 여유를 알아야 하므로 입력 필드의 `accessibilityValue`가
  /// 항상 이 문장을 읽는다. 시각적 표시와 접근성 표시의 등장 시점을 분리하는 것이 요점이다.
  var accessibilityDescription: String {
    isExceeded
      ? "\(limit)자 한도를 \(-remaining)자 넘었습니다"
      : "\(remaining)자 남았습니다"
  }
}

/// 글자수 카운터.
///
/// 다섯 개 입력 화면이 각자 `Text("\(count)/\(limit)")`를 그리면서 폰트가 `caption`, `caption2`,
/// `caption.monospacedDigit()` 세 갈래로 갈렸고 어떤 화면은 사용량을, 어떤 화면은 같은 값을 다른
/// 크기로 보여줬다. 표시는 남은 글자 수 하나로 모은다 — 사용자가 결정해야 하는 것은 "몇 자를 더
/// 쓸 수 있나"이고, 사용량은 그 값을 머릿속에서 빼야 알 수 있다.
///
/// `monospacedDigit()`은 필수다. 타이핑 중 숫자 폭이 바뀌면 옆에 놓인 전송 버튼이 좌우로 흔들린다.
struct WoorisaiCharacterCountLabel: View {
  private let budget: CharacterBudget
  private let name: String

  /// - Parameter name: VoiceOver가 어느 입력의 여유인지 말할 수 있게 하는 이름. "댓글", "이유".
  init(_ budget: CharacterBudget, name: String) {
    self.budget = budget
    self.name = name
  }

  var body: some View {
    if budget.isVisible {
      Text(budget.displayText)
        .font(.caption.monospacedDigit())
        .foregroundStyle(
          budget.isExceeded ? WoorisaiColor.Fg.critical : WoorisaiColor.Fg.neutralMuted
        )
        .accessibilityLabel("\(name) 남은 글자 수")
        .accessibilityValue(budget.accessibilityDescription)
    }
  }
}

extension View {
  /// 키보드 위에 붙는 액션 바의 표면.
  ///
  /// iOS 26 키보드는 상단 좌우를 약 15pt 반경으로 굽는다. 바가 각진 전폭 사각형이면 두 가지가
  /// 어긋난다 — 위로는 스크롤 카드를 직선으로 잘라 내고, 아래로는 키보드 곡선 바깥 좌우 코너에
  /// 배경이 비치는 틈을 남긴다. 그 틈이 바를 키보드 위에 떠 있는 판처럼 보이게 한다.
  ///
  /// 그래서 상단만 굽히고 하단은 그대로 둔다. 상단 곡률이 키보드와 같은 계열이 되면 두 표면이
  /// 한 스택으로 읽히고, 하단을 굽히지 않는 것은 키보드가 없을 때 화면 바닥까지 채우는 지금의
  /// safe area 처리를 그대로 유지하기 위해서다. Divider를 상단 테두리로 대신해 선이 곡선을 따라
  /// 돌게 한다.
  func woorisaiKeyboardActionBarSurface() -> some View {
    background {
      let shape = UnevenRoundedRectangle(
        topLeadingRadius: WoorisaiRadius.medium,
        bottomLeadingRadius: 0,
        bottomTrailingRadius: 0,
        topTrailingRadius: WoorisaiRadius.medium,
        style: .continuous
      )
      shape
        .fill(.regularMaterial)
        .overlay {
          shape.strokeBorder(WoorisaiColor.Stroke.neutralWeak, lineWidth: 1)
        }
    }
  }
}

/// The app-standard way to put the keyboard away.
@MainActor
enum WoorisaiKeyboard {
  static func dismiss() {
    UIApplication.shared.sendAction(
      #selector(UIResponder.resignFirstResponder),
      to: nil,
      from: nil,
      for: nil
    )
  }
}

extension View {
  /// Messenger-style keyboard dismissal: tapping the empty area around the cards puts the keyboard
  /// away.
  ///
  /// This is why the app has NO "완료" bar above the keyboard. Every text-entry screen already pins
  /// its own action bar (`safeAreaInset(edge: .bottom)`) directly above the keys, so a system keyboard
  /// toolbar only stacked a third chrome strip between the composer and the keyboard. This tap plus
  /// `scrollDismissesKeyboard(.interactively)` covers both the tap and the drag habit.
  ///
  /// Attach it to a `ScrollView`'s CONTENT, after the content's outermost
  /// `.frame(maxWidth: .infinity)`, so the tap area spans the full width including the gutters:
  ///
  /// - A layer placed *behind* the content never fires. `ScrollView` is a `UIScrollView`, and
  ///   `UIView.hitTest` claims every touch inside its bounds regardless of background.
  /// - Attaching to the `ScrollView` itself is not enough either. A backgroundless `VStack` produces
  ///   no hit region, so taps in the margins match nothing and the gesture never recognizes — hence
  ///   the explicit `contentShape`.
  ///
  /// SwiftUI gives child gestures priority over ancestor ones, so buttons, links and text fields
  /// inside keep their own taps. That matters: tapping 전송 must NOT dismiss, because a conversation
  /// screen deliberately keeps focus for the next reply.
  func dismissesKeyboardOnBackgroundTap() -> some View {
    contentShape(Rectangle())
      .onTapGesture(perform: WoorisaiKeyboard.dismiss)
  }
}

struct WarmBackground<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack {
      WoorisaiColor.Bg.layerBasement
        .ignoresSafeArea()

      RadialGradient(
        colors: [WoorisaiColor.Decor.ambientBrand.opacity(0.72), .clear],
        center: .topTrailing,
        startRadius: 8,
        endRadius: 360
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      Canvas { context, size in
        let dots: [(CGPoint, CGFloat, Color)] = [
          (CGPoint(x: size.width * 0.12, y: size.height * 0.16), 4, WoorisaiColor.Decor.dotWarm),
          (CGPoint(x: size.width * 0.88, y: size.height * 0.28), 3, WoorisaiColor.Decor.dotCalm),
          (CGPoint(x: size.width * 0.18, y: size.height * 0.78), 3, WoorisaiColor.Decor.dotBrand),
        ]
        for (point, radius, color) in dots {
          context.fill(
            Path(
              ellipseIn: CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
              )),
            with: .color(color.opacity(0.22))
          )
        }
      }
      .ignoresSafeArea()
      .allowsHitTesting(false)
      .accessibilityHidden(true)

      RadialGradient(
        colors: [WoorisaiColor.Decor.ambientCalm.opacity(0.72), .clear],
        center: .bottomLeading,
        startRadius: 8,
        endRadius: 340
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      content
    }
  }
}

struct WarmSurface<Content: View>: View {
  private let cornerRadius: CGFloat
  private let content: Content

  init(
    cornerRadius: CGFloat = WoorisaiRadius.medium,
    @ViewBuilder content: () -> Content
  ) {
    self.cornerRadius = cornerRadius
    self.content = content()
  }

  var body: some View {
    content
      .background {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
          .fill(WoorisaiColor.Bg.layerDefault)
          .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .stroke(WoorisaiColor.Stroke.neutralWeak, lineWidth: 1)
          }
          .woorisaiShadow(.s1)
      }
  }
}

struct Eyebrow: View {
  private let text: LocalizedStringKey

  init(_ text: LocalizedStringKey) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.caption2.weight(.heavy))
      .tracking(2.1)
      .foregroundStyle(WoorisaiColor.Fg.brand)
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .accessibilityHidden(true)
  }
}

struct ParticipantAvatar: View {
  private let name: String
  @ScaledMetric(relativeTo: .headline) private var size: CGFloat = 0

  init(name: String, size: CGFloat) {
    self.name = name
    _size = ScaledMetric(wrappedValue: size, relativeTo: .headline)
  }

  static func label(for name: String) -> String {
    String(name.prefix(2))
  }

  var body: some View {
    Text(Self.label(for: name))
      .font(.headline.weight(.heavy))
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      .allowsTightening(true)
      .padding(.horizontal, size * 0.1)
      .foregroundStyle(WoorisaiColor.Fg.brand)
      .frame(width: size, height: size)
      .background(WoorisaiColor.Bg.brandWeak, in: Circle())
      .accessibilityHidden(true)
  }
}

struct PrimaryHeartButton: View {
  @Environment(\.isEnabled) private var environmentIsEnabled
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private let title: LocalizedStringKey
  private let isEnabled: Bool
  private let isLoading: Bool
  private let action: () -> Void

  init(
    _ title: LocalizedStringKey,
    isEnabled: Bool = true,
    isLoading: Bool = false,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.isEnabled = isEnabled
    self.isLoading = isLoading
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: WoorisaiSpacing.small) {
        if isLoading {
          ProgressView()
            .tint(WoorisaiColor.Fg.brandContrast)
            .accessibilityHidden(true)
        } else {
          if !dynamicTypeSize.isAccessibilitySize {
            Image(systemName: "heart.fill")
              .accessibilityHidden(true)
          }
        }

        Text(title)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)

        if !isLoading, !dynamicTypeSize.isAccessibilitySize {
          Image(systemName: "arrow.right")
            .accessibilityHidden(true)
        }
      }
      .font(.headline.weight(.bold))
      .foregroundStyle(WoorisaiColor.Fg.brandContrast)
      .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.primaryHeight)
      .padding(.horizontal, WoorisaiSpacing.regular)
    }
    .buttonStyle(PressableSolidButtonStyle(isEnabled: buttonIsEnabled))
    .disabled(!isEnabled || isLoading)
  }

  private var buttonIsEnabled: Bool {
    environmentIsEnabled && isEnabled && !isLoading
  }
}

/// 브랜드 솔리드 버튼의 눌림 반응.
///
/// 예전에는 `.buttonStyle(.plain)`이라 손가락을 올려도 아무 변화가 없었다. 탭이 먹혔는지 알
/// 방법이 화면 전환뿐이어서, 느린 네트워크에서 같은 버튼을 두 번 누르게 만들었다.
///
/// 눌림은 두 갈래로 표현한다 — 배경이 진한 쪽으로 가라앉고, 살짝 줄어든다. 색만으로는 색각
/// 이상이나 밝은 야외에서 놓치기 쉽고, 크기 변화는 `reduceMotion`을 켠 사람에게 부담이 된다.
/// 둘을 겹쳐 두면 어느 한쪽이 빠져도 피드백이 남는다.
private struct PressableSolidButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  let isEnabled: Bool

  func makeBody(configuration: Configuration) -> some View {
    let isPressed = configuration.isPressed && isEnabled
    let shape = RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)

    return configuration.label
      .background(background(isPressed: isPressed), in: shape)
      // 비활성일 때는 그림자를 걷어 눌리지 않는 버튼임을 드러낸다. 눌린 동안에는 낮춰서
      // 버튼이 표면 쪽으로 내려앉은 것처럼 보이게 한다.
      .shadow(
        color: isEnabled ? (isPressed ? WoorisaiElevation.s1.color : WoorisaiElevation.s3.color)
          : .clear,
        radius: isPressed ? WoorisaiElevation.s1.radius : WoorisaiElevation.s3.radius,
        y: isPressed ? WoorisaiElevation.s1.offsetY : WoorisaiElevation.s3.offsetY
      )
      .scaleEffect(isPressed && !reduceMotion ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: isPressed)
      .contentShape(shape)
  }

  private func background(isPressed: Bool) -> LinearGradient {
    let colors: [Color] =
      if !isEnabled {
        [WoorisaiColor.Bg.disabled]
      } else if isPressed {
        [WoorisaiColor.Component.PrimaryButton.solidPressed]
      } else {
        [WoorisaiColor.Bg.brandSolid, WoorisaiColor.Component.PrimaryButton.solidEnd]
      }

    return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
  }
}

/// A transient success confirmation that floats over the content instead of taking layout space.
///
/// Success used to render in the same persistent card as failures, so "댓글을 남겼어요." sat above the
/// comment composer until the user tapped its X — shrinking the conversation after every single
/// reply. Problems still use that card: a message the user must act on may never time out.
///
/// The view owns the dismissal timing (the model just exposes the text and a clear method) so
/// mutation tests stay deterministic instead of waiting on a timer.
struct WoorisaiToast: View {
  @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

  let message: String
  let onDismiss: () -> Void

  var body: some View {
    Label(message, systemImage: "checkmark.circle.fill")
      .font(.callout.weight(.semibold))
      .foregroundStyle(WoorisaiColor.Fg.neutral)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, WoorisaiSpacing.regular)
      .padding(.vertical, WoorisaiSpacing.medium)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().stroke(WoorisaiColor.Stroke.brandWeak, lineWidth: 1)
      }
      .woorisaiShadow(.s2)
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("toast")
      .task(id: message) {
        // Announce rather than steal focus: a toast that grabs VoiceOver focus interrupts whatever
        // the user was reading, and one that vanishes on a sighted timer can be missed entirely.
        AccessibilityNotification.Announcement(message).post()
        try? await Task.sleep(for: voiceOverEnabled ? .seconds(6) : .seconds(2.4))
        guard !Task.isCancelled else { return }
        onDismiss()
      }
  }
}

extension View {
  /// Hosts the toast at the top of a screen's content — below the navigation bar, and clear of the
  /// bottom composer and tab bar, which are the crowded edges in this app.
  func woorisaiToast(
    _ message: String?,
    reduceMotion: Bool,
    onDismiss: @escaping () -> Void
  ) -> some View {
    overlay(alignment: .top) {
      if let message {
        WoorisaiToast(message: message, onDismiss: onDismiss)
          .padding(.horizontal, WoorisaiSpacing.screenGutter)
          .padding(.top, WoorisaiSpacing.small)
          .transition(
            reduceMotion
              ? .opacity
              : .move(edge: .top).combined(with: .opacity)
          )
      }
    }
    .animation(reduceMotion ? .none : .easeOut(duration: 0.22), value: message)
  }
}

struct WoorisaiSectionHeading: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let title: String
  let detail: String?
  let symbol: String

  init(_ title: String, detail: String? = nil, symbol: String = "heart.fill") {
    self.title = title
    self.detail = detail
    self.symbol = symbol
  }

  var body: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        titleContent
        if let detail {
          detailContent(detail)
        }
      }
    } else {
      HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
        titleContent
        Spacer(minLength: WoorisaiSpacing.small)
        if let detail {
          detailContent(detail)
        }
      }
    }
  }

  private var titleContent: some View {
    HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
      Image(systemName: symbol)
        .foregroundStyle(WoorisaiColor.Fg.brandVivid)
        .accessibilityHidden(true)
      Text(title)
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private func detailContent(_ detail: String) -> some View {
    Text(detail)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// 점수 변화량 배지.
///
/// 히스토리 행과 점수 편집 미리보기가 각자 구현하던 것을 합쳤다. 라벨 문구와 VoiceOver 표현도
/// 여기서 만든다 — 예전에는 같은 값을 히스토리가 `"0점"`, 미리보기가 `"변화 없음"`으로 다르게
/// 불렀다.
struct WoorisaiDeltaBadge: View {
  /// 배지가 그 화면에서 주요 지표인지, 곁들여진 보조 정보인지.
  enum Prominence {
    /// 히스토리 행처럼 그 행의 핵심 수치일 때.
    case primary
    /// 편집 미리보기처럼 다른 정보에 딸려 나올 때.
    case secondary
  }

  private let value: Int64
  private let prominence: Prominence

  init(_ value: Int64, prominence: Prominence = .primary) {
    self.value = value
    self.prominence = prominence
  }

  private var delta: WoorisaiColor.Delta { WoorisaiColor.Delta(value) }

  static func label(for value: Int64) -> String {
    if value == 0 { return "변화 없음" }
    return value > 0 ? "+\(value)점" : "\(value)점"
  }

  static func accessibilityLabel(for value: Int64) -> String {
    if value == 0 { return "변화 없음" }
    return value > 0 ? "\(value)점 올라감" : "\(value.magnitude)점 내려감"
  }

  var body: some View {
    Text(Self.label(for: value))
      .font(font)
      .foregroundStyle(WoorisaiColor.fg(delta))
      .padding(.horizontal, horizontalPadding)
      .padding(.vertical, verticalPadding)
      .background(WoorisaiColor.bg(delta), in: Capsule())
      .overlay {
        if let stroke = WoorisaiColor.stroke(delta) {
          Capsule().stroke(stroke, lineWidth: 1)
        }
      }
      .fixedSize(horizontal: true, vertical: true)
      .accessibilityLabel(Self.accessibilityLabel(for: value))
  }

  private var font: Font {
    switch prominence {
    case .primary: .subheadline.weight(.heavy)
    case .secondary: .caption.weight(.heavy)
    }
  }

  private var horizontalPadding: CGFloat {
    switch prominence {
    case .primary: WoorisaiSpacing.medium
    case .secondary: WoorisaiSpacing.small
    }
  }

  private var verticalPadding: CGFloat {
    switch prominence {
    case .primary: WoorisaiSpacing.small
    case .secondary: WoorisaiSpacing.xSmall
    }
  }
}

struct WoorisaiIconButton: View {
  let symbol: String
  let accessibilityLabel: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.body.weight(.semibold))
        .foregroundStyle(WoorisaiColor.Fg.brand)
        .frame(
          width: WoorisaiControlMetric.minimumTapTarget,
          height: WoorisaiControlMetric.minimumTapTarget
        )
    }
    .buttonStyle(PressableCircleButtonStyle())
    .accessibilityLabel(accessibilityLabel)
  }
}

/// 원형 아이콘 버튼의 눌림 반응. ``PressableSolidButtonStyle``과 같은 이유로 색과 크기를 함께 쓴다.
private struct PressableCircleButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background(
        configuration.isPressed
          ? WoorisaiColor.Component.IconButton.backgroundPressed
          : WoorisaiColor.Component.IconButton.background,
        in: Circle()
      )
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
      .contentShape(Circle())
  }
}

/// 대화 말풍선의 반대쪽 여백.
///
/// 말풍선이 화면 폭을 다 채우면 좌우 정렬만으로는 누가 말했는지 읽히지 않는다. 그래서 내 말풍선
/// 왼쪽, 상대 말풍선 오른쪽에 최소 여백을 세운다.
///
/// 다만 접근성 텍스트 크기에서는 여백을 걷는다. 글자가 커진 상태에서 폭까지 좁히면 한 줄에 몇
/// 글자 못 들어가 말풍선이 세로로 길어지기만 한다. 그 크기에서는 화자 구분을 정렬이 아니라
/// 이름 라벨이 맡는다.
///
/// 점수 대화와 일기 댓글이 이 규칙을 각자 네 곳에 적어두고 있어서 한 곳으로 모았다.
struct BubbleOppositeGutter: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// 탭 영역 하한과 우연히 같은 44지만 뜻이 다르므로 따로 둔다.
  private static let minimumWidth: CGFloat = 44

  private let isVisible: Bool

  init(_ isVisible: Bool) {
    self.isVisible = isVisible
  }

  var body: some View {
    if isVisible, !dynamicTypeSize.isAccessibilitySize {
      Spacer(minLength: Self.minimumWidth)
    }
  }
}

struct BrandedStateCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      content
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(WoorisaiSpacing.large)
    }
  }
}
