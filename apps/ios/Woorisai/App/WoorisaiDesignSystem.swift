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

  private let value: Int
  private let prominence: Prominence

  init(_ value: Int, prominence: Prominence = .primary) {
    self.value = value
    self.prominence = prominence
  }

  private var delta: WoorisaiColor.Delta { WoorisaiColor.Delta(value) }

  static func label(for value: Int) -> String {
    if value == 0 { return "변화 없음" }
    return value > 0 ? "+\(value)점" : "\(value)점"
  }

  static func accessibilityLabel(for value: Int) -> String {
    if value == 0 { return "변화 없음" }
    return value > 0 ? "\(value)점 올라감" : "\(-value)점 내려감"
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
