import SwiftUI
import Testing

@testable import Woorisai

/// `AppPrivacyCoverPolicy` is the single decision point for both privacy covers (the SwiftUI
/// overlay and the UIKit snapshot shield). These tests pin the full scenePhase × privacy matrix so
/// a future change can't silently reintroduce covering the biometric lock screen — which blanks
/// the app behind the Face ID sheet.
struct AppPrivacyCoverPolicyTests {
  @Test(arguments: [ScenePhase.inactive, ScenePhase.background])
  func coversPrivateContentWheneverSceneIsNotActive(phase: ScenePhase) {
    #expect(AppPrivacyCoverPolicy.shouldCover(phase, contentIsPrivate: true))
  }

  @Test
  func neverCoversWhileSceneIsActive() {
    #expect(!AppPrivacyCoverPolicy.shouldCover(.active, contentIsPrivate: true))
  }

  @Test(arguments: [ScenePhase.active, ScenePhase.inactive, ScenePhase.background])
  func neverCoversNonPrivateContent(phase: ScenePhase) {
    #expect(!AppPrivacyCoverPolicy.shouldCover(phase, contentIsPrivate: false))
  }
}
