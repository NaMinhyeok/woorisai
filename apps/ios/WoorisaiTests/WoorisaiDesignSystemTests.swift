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
  /// **아래 목록이 흰 글자를 받을 수 있는 브랜드 면의 전부다.** 새로 배경을 칠할 일이 생기면
  /// 여기에 넣고 통과하는지 먼저 볼 것.
  ///
  /// `Fg` 축의 브랜드 색을 배경으로 돌리면 다크모드에서 무너진다(`brandVivid` 2.2:1,
  /// `brand` 1.8:1). 실제로 그렇게 쓰인 곳이 일곱 군데 있었고 — `.background(Fg.brand,
  /// in: Capsule())` 하나와 `.buttonStyle(.borderedProminent)` + `.tint(Fg.brand)` 여섯 —
  /// 이 테스트는 토큰 짝만 보기 때문에 그걸 잡지 못했다. 호출부가 어느 축의 토큰을 어디에
  /// 넘기는지는 컴파일러도 테스트도 막지 못하므로, 방어는 결국 이름과 doc comment에 있다.
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

  // MARK: - CharacterBudget

  /// 카운터가 평소에 숨어 있으므로 등장 시점이 곧 이 규칙의 전부다. 화면 안에서는 경계 한 글자를
  /// 눈으로 확인할 방법이 없어 값으로 못 박는다.
  @Test
  func characterCounterStaysHiddenUntilTheProportionalShareIsReachedOnShortFields() {
    // 200자의 15% = 30자. 절대 임계 40자보다 작으므로 비율이 지배한다.
    #expect(CharacterBudget(used: 169, limit: 200).isVisible == false)
    #expect(CharacterBudget(used: 170, limit: 200).isVisible)
  }

  @Test
  func characterCounterStaysHiddenUntilTheAbsoluteThresholdIsReachedOnLongFields() {
    // 500자의 15% = 75자지만 절대 임계 40자가 더 작으므로 40자 남을 때까지 숨는다.
    #expect(CharacterBudget(used: 425, limit: 500).isVisible == false)
    #expect(CharacterBudget(used: 459, limit: 500).isVisible == false)
    #expect(CharacterBudget(used: 460, limit: 500).isVisible)
  }

  @Test
  func characterCounterShowsTheOverflowAsANegativeRemainder() {
    let exact = CharacterBudget(used: 500, limit: 500)
    #expect(exact.remaining == 0)
    #expect(exact.isExceeded == false)
    #expect(exact.isVisible)
    #expect(exact.displayText == "0")

    let over = CharacterBudget(used: 508, limit: 500)
    #expect(over.remaining == -8)
    #expect(over.isExceeded)
    #expect(over.isVisible)
    #expect(over.displayText == "-8")
  }

  /// 제출을 막은 이유는 화면에 남아야 하므로 초과는 임계값과 무관하게 항상 보인다.
  @Test
  func characterCounterAlwaysShowsWhileExceeded() {
    #expect(CharacterBudget(used: 100_000, limit: 500).isVisible)
    #expect(CharacterBudget(used: 201, limit: 200).isVisible)
  }

  /// 한도가 없는 field는 카운터를 그릴 근거 자체가 없다. 초과처럼 보이는 입력이 와도 마찬가지다 —
  /// `limit`이 0인 것은 사용자가 많이 쓴 상황이 아니라 한도를 넘겨받지 못한 설정 문제이고, 그때
  /// "-1"을 띄우면 사용자가 고칠 수 없는 수를 보게 된다.
  @Test
  func characterCounterStaysHiddenWithoutALimit() {
    #expect(CharacterBudget(used: 0, limit: 0).isVisible == false)
    #expect(CharacterBudget(used: 1, limit: 0).isVisible == false)
  }

  @Test
  func characterCounterDescribesRemainingBudgetForVoiceOver() {
    #expect(
      CharacterBudget(used: 460, limit: 500).accessibilityDescription == "40자 남았습니다"
    )
    #expect(
      CharacterBudget(used: 508, limit: 500).accessibilityDescription
        == "500자 한도를 8자 넘었습니다"
    )
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
