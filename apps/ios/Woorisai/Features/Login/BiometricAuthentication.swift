import Foundation
import LocalAuthentication

enum BiometricKind: Sendable, Equatable {
  case faceID
  case touchID
  case opticID
  case none

  var isUsable: Bool { self != .none }
}

struct BiometricAvailability: Sendable, Equatable {
  let kind: BiometricKind
  let canPromptForUnlock: Bool

  static let unavailable = BiometricAvailability(kind: .none, canPromptForUnlock: false)
}

/// Reports which biometric modality can gate a Keychain unlock — WITHOUT presenting any prompt.
/// Abstracted so tests inject a fake instead of touching `LAContext`.
protocol BiometricAvailabilityProbing: Sendable {
  func availability() async -> BiometricAvailability
}

/// Production probe over `LocalAuthentication`. `@unchecked Sendable` because `LAContext` is not
/// Sendable; each probe builds a fresh context and returns only Sendable values, mirroring
/// `SystemNotificationPermissionAuthorizer`.
final class LocalAuthenticationBiometricProbe: BiometricAvailabilityProbing, @unchecked Sendable {
  func availability() async -> BiometricAvailability {
    // A fresh context per probe: `LAContext` caches its evaluation, so reuse would report stale
    // availability after the user changes enrollment in Settings. `biometryType` is only
    // meaningful once `canEvaluatePolicy` has been queried.
    let context = LAContext()
    let canEvaluate = context.canEvaluatePolicy(
      .deviceOwnerAuthenticationWithBiometrics,
      error: nil
    )
    let kind = Self.map(context.biometryType)
    return BiometricAvailability(
      kind: kind,
      canPromptForUnlock: canEvaluate && kind.isUsable
    )
  }

  private static func map(_ type: LABiometryType) -> BiometricKind {
    switch type {
    case .faceID: .faceID
    case .touchID: .touchID
    case .opticID: .opticID
    case .none: .none
    @unknown default: .none
    }
  }
}

/// Reports no biometrics. Used as the `AuthenticationModel` default and in the test/UI-test
/// dependency branches so session restore is inert.
struct UnavailableBiometricProbe: BiometricAvailabilityProbing {
  func availability() async -> BiometricAvailability { .unavailable }
}
