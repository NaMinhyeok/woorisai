import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Woorisai

/// `@Test(arguments:)`는 actor 밖에서 평가되므로 `@MainActor` 타입 안에 둘 수 없다.
private let interfaceStyles: [UIUserInterfaceStyle] = [.light, .dark]

/// `WoorisaiColor`가 약속하는 대비를 값으로 못 박는다.
///
/// 색 이름(`coral`, `sage`)을 역할 이름으로 바꾸면서 무엇을 글자에 써도 되고 무엇을 배경에만
/// 써야 하는지가 doc comment로만 남았다. 그 약속을 여기서 검증한다 — 특히 라이트/다크 양쪽에서
/// 모두 성립해야 한다는 점이 눈으로는 잘 잡히지 않는다.
@MainActor
struct WoorisaiDesignSystemTests {
  /// 본문 텍스트 기준(WCAG AA).
  private static let textContrast: CGFloat = 4.5
  /// 아이콘·경계선 등 글자가 아닌 요소 기준(WCAG AA non-text).
  private static let nonTextContrast: CGFloat = 3

  @Test
  func surfacesAdaptToInterfaceStyle() {
    #expect(
      relativeLuminance(resolved(WoorisaiColor.Bg.layerBasement, style: .light))
        > relativeLuminance(resolved(WoorisaiColor.Bg.layerBasement, style: .dark))
    )
    #expect(
      relativeLuminance(resolved(WoorisaiColor.Bg.layerDefault, style: .light))
        > relativeLuminance(resolved(WoorisaiColor.Bg.layerDefault, style: .dark))
    )
  }

  @Test(arguments: interfaceStyles)
  func textColorsKeepReadableContrast(style: UIUserInterfaceStyle) {
    expectContrast(WoorisaiColor.Fg.neutral, on: WoorisaiColor.Bg.layerBasement, style)

    for background in [
      WoorisaiColor.Bg.layerBasement,
      WoorisaiColor.Bg.layerSunken,
      WoorisaiColor.Bg.layerDefault,
      WoorisaiColor.Bg.layerFill,
      WoorisaiColor.Bg.selected,
      WoorisaiColor.Bg.brandWeak,
      WoorisaiColor.bg(.video),
    ] {
      expectContrast(WoorisaiColor.Fg.neutralMuted, on: background, style)
    }

    expectContrast(WoorisaiColor.Fg.brand, on: WoorisaiColor.Bg.brandWeak, style)
    expectContrast(WoorisaiColor.Fg.calm, on: WoorisaiColor.bg(.video), style)
    expectContrast(WoorisaiColor.Fg.positive, on: WoorisaiColor.Bg.layerSunken, style)
    expectContrast(WoorisaiColor.Fg.critical, on: WoorisaiColor.Bg.layerSunken, style)
  }

  /// 브랜드 솔리드 면 위의 라벨.
  ///
  /// `Fg.brandVivid`(coral)를 배경 삼아 흰 글자를 올리면 다크모드에서 2.2:1까지 떨어진다.
  /// 흰 글자를 얹는 면은 반드시 `Bg.brandSolid` 계열이어야 한다는 것을 고정한다.
  @Test(arguments: interfaceStyles)
  func brandSolidSurfacesCarryReadableLabels(style: UIUserInterfaceStyle) {
    for background in [
      WoorisaiColor.Bg.brandSolid,
      WoorisaiColor.Component.PrimaryButton.solidEnd,
      WoorisaiColor.Bg.disabled,
    ] {
      expectContrast(WoorisaiColor.Fg.brandContrast, on: background, style)
    }
  }

  /// 점수 변화 배지 세 상태.
  ///
  /// 방향을 색상(hue)이 아니라 강조의 세기로 구분하므로, 세 배지가 저마다 읽히는지는 눈으로
  /// 확인하기 어렵다.
  @Test(arguments: interfaceStyles)
  func deltaBadgesRemainReadableInEveryState(style: UIUserInterfaceStyle) {
    for delta in [WoorisaiColor.Delta.increase, .decrease, .unchanged] {
      expectContrast(WoorisaiColor.fg(delta), on: WoorisaiColor.bg(delta), style)
    }
  }

  /// 작성자·미디어 종류를 나타내는 색은 아이콘과 프로그레스바에만 쓰이므로 non-text 기준을 쓴다.
  @Test(arguments: interfaceStyles)
  func nonTextAccentsStayDistinguishableFromTheirBackdrop(style: UIUserInterfaceStyle) {
    for accent in [
      WoorisaiColor.fg(.mine),
      WoorisaiColor.fg(.partner),
      WoorisaiColor.Fg.brandVivid,
    ] {
      expectContrast(
        accent,
        on: WoorisaiColor.Bg.layerBasement,
        style,
        minimum: Self.nonTextContrast
      )
    }

    for kind in [WoorisaiColor.MediaKind.image, .video] {
      expectContrast(
        WoorisaiColor.fg(kind),
        on: WoorisaiColor.bg(kind),
        style,
        minimum: Self.nonTextContrast
      )
    }
  }

  @Test(arguments: interfaceStyles)
  func ambientGradientsDoNotSwallowSecondaryText(style: UIUserInterfaceStyle) {
    let background = resolved(WoorisaiColor.Bg.layerBasement, style: style)
    let muted = resolved(WoorisaiColor.Fg.neutralMuted, style: style)

    for ambient in [WoorisaiColor.Decor.ambientBrand, WoorisaiColor.Decor.ambientCalm] {
      let gradient = composited(resolved(ambient, style: style), alpha: 0.72, over: background)
      #expect(contrastRatio(muted, gradient) >= Self.textContrast)
    }
  }

  @Test(arguments: interfaceStyles)
  func controlBordersRemainVisibleOnElevatedSurfaces(style: UIUserInterfaceStyle) {
    for background in [WoorisaiColor.Bg.layerDefault, WoorisaiColor.Bg.layerFill] {
      expectContrast(
        WoorisaiColor.Stroke.neutralWeak,
        on: background,
        style,
        minimum: Self.nonTextContrast
      )
    }
    expectContrast(
      WoorisaiColor.Bg.disabled,
      on: WoorisaiColor.Bg.layerDefault,
      style,
      minimum: Self.nonTextContrast
    )
  }

  private func expectContrast(
    _ foreground: Color,
    on background: Color,
    _ style: UIUserInterfaceStyle,
    minimum: CGFloat = WoorisaiDesignSystemTests.textContrast,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    let ratio = contrastRatio(
      resolved(foreground, style: style),
      resolved(background, style: style)
    )
    #expect(
      ratio >= minimum,
      "\(style) 대비가 \(ratio), 기준 \(minimum)",
      sourceLocation: sourceLocation
    )
  }

  private func resolved(_ color: Color, style: UIUserInterfaceStyle) -> UIColor {
    UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
  }

  private func contrastRatio(_ first: UIColor, _ second: UIColor) -> CGFloat {
    let firstLuminance = relativeLuminance(first)
    let secondLuminance = relativeLuminance(second)
    return (max(firstLuminance, secondLuminance) + 0.05)
      / (min(firstLuminance, secondLuminance) + 0.05)
  }

  private func composited(_ overlay: UIColor, alpha: CGFloat, over background: UIColor) -> UIColor {
    let overlayComponents = components(of: overlay)
    let backgroundComponents = components(of: background)

    return UIColor(
      red: overlayComponents.red * alpha + backgroundComponents.red * (1 - alpha),
      green: overlayComponents.green * alpha + backgroundComponents.green * (1 - alpha),
      blue: overlayComponents.blue * alpha + backgroundComponents.blue * (1 - alpha),
      alpha: 1
    )
  }

  private func relativeLuminance(_ color: UIColor) -> CGFloat {
    let rgb = components(of: color)

    func linearize(_ component: CGFloat) -> CGFloat {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearize(rgb.red)
      + 0.7152 * linearize(rgb.green)
      + 0.0722 * linearize(rgb.blue)
  }

  private func components(of color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    return (red, green, blue)
  }
}
