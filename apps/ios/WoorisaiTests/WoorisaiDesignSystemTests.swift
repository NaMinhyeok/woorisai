import Foundation
import SwiftUI
import UIKit
import XCTest

@testable import Woorisai

@MainActor
final class WoorisaiDesignSystemTests: XCTestCase {
  func testPaletteSurfacesAdaptToInterfaceStyle() {
    let lightBackground = resolved(WoorisaiPalette.cream, style: .light)
    let darkBackground = resolved(WoorisaiPalette.cream, style: .dark)
    let lightSurface = resolved(WoorisaiPalette.surface, style: .light)
    let darkSurface = resolved(WoorisaiPalette.surface, style: .dark)

    XCTAssertGreaterThan(relativeLuminance(lightBackground), relativeLuminance(darkBackground))
    XCTAssertGreaterThan(relativeLuminance(lightSurface), relativeLuminance(darkSurface))
  }

  func testSemanticTextAndControlColorsKeepReadableContrast() {
    for style in [UIUserInterfaceStyle.light, .dark] {
      assertContrast(WoorisaiPalette.ink, against: WoorisaiPalette.cream, style: style)
      for background in [
        WoorisaiPalette.cream,
        WoorisaiPalette.creamDeep,
        WoorisaiPalette.surface,
        WoorisaiPalette.field,
        WoorisaiPalette.selectedSurface,
        WoorisaiPalette.coralSoft,
        WoorisaiPalette.sageSoft,
      ] {
        assertContrast(WoorisaiPalette.muted, against: background, style: style)
      }
      assertContrast(WoorisaiPalette.coralDark, against: WoorisaiPalette.coralSoft, style: style)
      assertContrast(WoorisaiPalette.sage, against: WoorisaiPalette.sageSoft, style: style)
      assertContrast(WoorisaiPalette.success, against: WoorisaiPalette.creamDeep, style: style)
      assertContrast(WoorisaiPalette.error, against: WoorisaiPalette.creamDeep, style: style)
      assertContrast(
        WoorisaiPalette.primaryButtonLabel,
        against: WoorisaiPalette.primaryButtonStart,
        style: style
      )
      assertContrast(
        WoorisaiPalette.primaryButtonLabel,
        against: WoorisaiPalette.primaryButtonEnd,
        style: style
      )
      assertContrast(
        WoorisaiPalette.primaryButtonLabel,
        against: WoorisaiPalette.primaryButtonDisabled,
        style: style
      )

      let background = resolved(WoorisaiPalette.cream, style: style)
      let coralGradient = composited(
        resolved(WoorisaiPalette.coralSoft, style: style),
        alpha: 0.72,
        over: background
      )
      let sageGradient = composited(
        resolved(WoorisaiPalette.sageSoft, style: style),
        alpha: 0.72,
        over: background
      )
      let muted = resolved(WoorisaiPalette.muted, style: style)
      XCTAssertGreaterThanOrEqual(contrastRatio(muted, coralGradient), 4.5)
      XCTAssertGreaterThanOrEqual(contrastRatio(muted, sageGradient), 4.5)
    }
  }

  func testControlBordersRemainVisibleOnElevatedSurfaces() {
    for style in [UIUserInterfaceStyle.light, .dark] {
      for background in [WoorisaiPalette.surface, WoorisaiPalette.field] {
        let ratio = contrastRatio(
          resolved(WoorisaiPalette.line, style: style),
          resolved(background, style: style)
        )
        XCTAssertGreaterThanOrEqual(ratio, 3, "\(style) control border contrast was \(ratio)")
      }
      let disabledButtonRatio = contrastRatio(
        resolved(WoorisaiPalette.primaryButtonDisabled, style: style),
        resolved(WoorisaiPalette.surface, style: style)
      )
      XCTAssertGreaterThanOrEqual(disabledButtonRatio, 3)
    }
  }

  private func assertContrast(
    _ foreground: Color,
    against background: Color,
    style: UIUserInterfaceStyle,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let ratio = contrastRatio(
      resolved(foreground, style: style),
      resolved(background, style: style)
    )
    XCTAssertGreaterThanOrEqual(ratio, 4.5, "\(style) contrast was \(ratio)", file: file, line: line)
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
    var overlayRed: CGFloat = 0
    var overlayGreen: CGFloat = 0
    var overlayBlue: CGFloat = 0
    var overlayAlpha: CGFloat = 0
    var backgroundRed: CGFloat = 0
    var backgroundGreen: CGFloat = 0
    var backgroundBlue: CGFloat = 0
    var backgroundAlpha: CGFloat = 0
    XCTAssertTrue(
      overlay.getRed(
        &overlayRed,
        green: &overlayGreen,
        blue: &overlayBlue,
        alpha: &overlayAlpha
      )
    )
    XCTAssertTrue(
      background.getRed(
        &backgroundRed,
        green: &backgroundGreen,
        blue: &backgroundBlue,
        alpha: &backgroundAlpha
      )
    )

    return UIColor(
      red: overlayRed * alpha + backgroundRed * (1 - alpha),
      green: overlayGreen * alpha + backgroundGreen * (1 - alpha),
      blue: overlayBlue * alpha + backgroundBlue * (1 - alpha),
      alpha: 1
    )
  }

  private func relativeLuminance(_ color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

    func linearize(_ component: CGFloat) -> CGFloat {
      component <= 0.04045
        ? component / 12.92
        : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linearize(red)
      + 0.7152 * linearize(green)
      + 0.0722 * linearize(blue)
  }
}
