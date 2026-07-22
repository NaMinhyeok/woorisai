import SwiftUI
import UIKit

enum WoorisaiPalette {
  static let cream = adaptive(light: (255, 248, 241), dark: (23, 19, 18))
  static let creamDeep = adaptive(light: (249, 238, 228), dark: (46, 37, 33))
  static let surface = adaptive(light: (255, 252, 250), dark: (37, 31, 29))
  static let field = adaptive(light: (255, 251, 248), dark: (48, 40, 37))
  static let selectedSurface = adaptive(light: (255, 240, 236), dark: (58, 40, 37))
  static let ink = adaptive(light: (57, 45, 42), dark: (247, 238, 234))
  static let muted = adaptive(light: (112, 94, 88), dark: (200, 181, 172))
  static let line = adaptive(light: (160, 139, 130), dark: (142, 114, 104))
  static let coral = adaptive(light: (217, 92, 78), dark: (255, 143, 125))
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
  static let shadow = adaptive(light: (57, 45, 42), dark: (0, 0, 0))

  private static func adaptive(
    light: (red: Int, green: Int, blue: Int),
    dark: (red: Int, green: Int, blue: Int)
  ) -> Color {
    Color(
      uiColor: UIColor { traits in
        let components = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat(components.red) / 255,
          green: CGFloat(components.green) / 255,
          blue: CGFloat(components.blue) / 255,
          alpha: 1
        )
      }
    )
  }
}

struct KeyboardDismissToolbar: ToolbarContent {
  let action: () -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup(placement: .keyboard) {
      Spacer()
      Button("완료", action: action)
        .fontWeight(.semibold)
        .accessibilityLabel("키보드 닫기")
        .accessibilityIdentifier("keyboard.dismiss")
    }
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
    cornerRadius: CGFloat = 22,
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
          .shadow(color: WoorisaiPalette.shadow.opacity(0.12), radius: 18, y: 8)
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
