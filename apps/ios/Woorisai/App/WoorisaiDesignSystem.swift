import SwiftUI
import UIKit

enum WoorisaiPalette {
  /// UIKit-level brand colors for non-SwiftUI chrome (privacy covers). Keep in sync with `cream`
  /// and `coral` below; system semantic colors (`.systemBackground` 등) must not replace these —
  /// they read as a foreign black/white flash against the warm brand background.
  static let creamUIColor = adaptiveUIColor(light: (255, 248, 241), dark: (23, 19, 18))
  static let coralUIColor = adaptiveUIColor(light: (217, 92, 78), dark: (255, 143, 125))

  static let cream = Color(uiColor: creamUIColor)
  static let creamDeep = adaptive(light: (249, 238, 228), dark: (46, 37, 33))
  static let surface = adaptive(light: (255, 252, 250), dark: (37, 31, 29))
  static let field = adaptive(light: (255, 251, 248), dark: (48, 40, 37))
  static let selectedSurface = adaptive(light: (255, 240, 236), dark: (58, 40, 37))
  static let ink = adaptive(light: (57, 45, 42), dark: (247, 238, 234))
  static let muted = adaptive(light: (112, 94, 88), dark: (200, 181, 172))
  static let line = adaptive(light: (160, 139, 130), dark: (142, 114, 104))
  static let coral = Color(uiColor: coralUIColor)
  static let coralDark = adaptive(light: (168, 63, 53), dark: (255, 170, 153))
  static let coralSoft = adaptive(light: (255, 224, 216), dark: (84, 48, 43))
  static let rose = adaptive(light: (246, 181, 173), dark: (192, 120, 112))
  static let sage = adaptive(light: (75, 113, 86), dark: (155, 201, 168))
  static let sageSoft = adaptive(light: (228, 240, 231), dark: (43, 69, 51))
  static let success = adaptive(light: (61, 110, 75), dark: (155, 213, 169))
  static let error = adaptive(light: (180, 35, 24), dark: (255, 180, 171))
  static let primaryButtonStart = adaptive(light: (193, 64, 52), dark: (183, 62, 52))
  static let primaryButtonEnd = adaptive(light: (150, 47, 40), dark: (132, 42, 36))
  static let primaryButtonDisabled = adaptive(light: (132, 102, 97), dark: (140, 108, 102))
  static let primaryButtonLabel = Color.white
  // Dark mode: a pure-black drop shadow is invisible on the warm-dark background, flattening
  // every card. A faint warm glow reads as elevation instead. (Call sites keep their 0.08–0.2
  // opacities.)
  static let shadow = adaptive(light: (57, 45, 42), dark: (255, 190, 175))

  private static func adaptive(
    light: (red: Int, green: Int, blue: Int),
    dark: (red: Int, green: Int, blue: Int)
  ) -> Color {
    Color(uiColor: adaptiveUIColor(light: light, dark: dark))
  }

  private static func adaptiveUIColor(
    light: (red: Int, green: Int, blue: Int),
    dark: (red: Int, green: Int, blue: Int)
  ) -> UIColor {
    UIColor { traits in
      let components = traits.userInterfaceStyle == .dark ? dark : light
      return UIColor(
        red: CGFloat(components.red) / 255,
        green: CGFloat(components.green) / 255,
        blue: CGFloat(components.blue) / 255,
        alpha: 1
      )
    }
  }
}

enum WoorisaiSpacing {
  static let xSmall: CGFloat = 4
  static let small: CGFloat = 8
  static let medium: CGFloat = 12
  static let regular: CGFloat = 16
  static let large: CGFloat = 24
  static let xLarge: CGFloat = 32
  static let screenGutter: CGFloat = regular
}

enum WoorisaiRadius {
  static let small: CGFloat = 12
  static let medium: CGFloat = 18
  static let large: CGFloat = 24
}

enum WoorisaiControlMetric {
  static let minimumTapTarget: CGFloat = 44
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
      WoorisaiPalette.cream
        .ignoresSafeArea()

      RadialGradient(
        colors: [WoorisaiPalette.coralSoft.opacity(0.72), .clear],
        center: .topTrailing,
        startRadius: 8,
        endRadius: 360
      )
      .ignoresSafeArea()
      .allowsHitTesting(false)

      Canvas { context, size in
        let dots: [(CGPoint, CGFloat, Color)] = [
          (CGPoint(x: size.width * 0.12, y: size.height * 0.16), 4, WoorisaiPalette.rose),
          (CGPoint(x: size.width * 0.88, y: size.height * 0.28), 3, WoorisaiPalette.sage),
          (CGPoint(x: size.width * 0.18, y: size.height * 0.78), 3, WoorisaiPalette.coral),
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
        colors: [WoorisaiPalette.sageSoft.opacity(0.72), .clear],
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
          .fill(WoorisaiPalette.surface)
          .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
              .stroke(WoorisaiPalette.line, lineWidth: 1)
          }
          .shadow(color: WoorisaiPalette.shadow.opacity(0.08), radius: 10, y: 4)
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
      .foregroundStyle(WoorisaiPalette.coralDark)
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
      .foregroundStyle(WoorisaiPalette.coralDark)
      .frame(width: size, height: size)
      .background(WoorisaiPalette.coralSoft, in: Circle())
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
      HStack(spacing: 10) {
        if isLoading {
          ProgressView()
            .tint(WoorisaiPalette.primaryButtonLabel)
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
      .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
      .frame(maxWidth: .infinity, minHeight: 52)
      .padding(.horizontal, 18)
      .background(
        LinearGradient(
          colors: buttonIsEnabled
            ? [WoorisaiPalette.primaryButtonStart, WoorisaiPalette.primaryButtonEnd]
            : [WoorisaiPalette.primaryButtonDisabled],
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        ),
        in: RoundedRectangle(cornerRadius: 15, style: .continuous)
      )
      .shadow(
        color: WoorisaiPalette.shadow.opacity(buttonIsEnabled ? 0.2 : 0),
        radius: 12,
        y: 6
      )
      .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled || isLoading)
  }

  private var buttonIsEnabled: Bool {
    environmentIsEnabled && isEnabled && !isLoading
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
      .foregroundStyle(WoorisaiPalette.ink)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, WoorisaiSpacing.regular)
      .padding(.vertical, WoorisaiSpacing.medium)
      .background(.regularMaterial, in: Capsule())
      .overlay {
        Capsule().stroke(WoorisaiPalette.coral.opacity(0.28), lineWidth: 1)
      }
      .shadow(color: WoorisaiPalette.shadow.opacity(0.16), radius: 12, y: 4)
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
        .foregroundStyle(WoorisaiPalette.coral)
        .accessibilityHidden(true)
      Text(title)
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)
        .accessibilityAddTraits(.isHeader)
    }
  }

  private func detailContent(_ detail: String) -> some View {
    Text(detail)
      .font(.footnote.weight(.semibold))
      .foregroundStyle(WoorisaiPalette.muted)
      .fixedSize(horizontal: false, vertical: true)
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
        .foregroundStyle(WoorisaiPalette.coralDark)
        .frame(
          width: WoorisaiControlMetric.minimumTapTarget,
          height: WoorisaiControlMetric.minimumTapTarget
        )
        .background(WoorisaiPalette.coralSoft.opacity(0.72), in: Circle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(accessibilityLabel)
  }
}

struct BrandedStateCard<Content: View>: View {
  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    WarmSurface(cornerRadius: 24) {
      content
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding(22)
    }
  }
}
