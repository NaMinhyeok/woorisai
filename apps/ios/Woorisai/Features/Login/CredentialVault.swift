import Foundation
import LocalAuthentication
import WoorisaiAPI

enum CredentialVaultError: Error, Sendable, Equatable {
  /// The user dismissed the biometric sheet.
  case cancelled
  /// No stored credential (presence check), or the Keychain is temporarily inaccessible.
  case unavailable
  /// The stored item can no longer be read at all: a `.biometryCurrentSet` item is permanently
  /// invalidated by biometry re-enrollment (read returns `errSecItemNotFound` while the
  /// attributes-only presence check still sees it), or the item vanished. Never transient —
  /// callers must forget the vault instead of asking the user to retry.
  case invalidated
  /// A stored blob could not be decoded into an archive.
  case itemCorrupted
  /// Biometric authentication failed, lockout, or any other Keychain error.
  case failed
}

/// The only at-rest credential store. Reads are gated by a biometric prompt via the item's
/// `SecAccessControl`; existence checks never prompt. Abstracted so tests inject a fake instead of
/// touching the Keychain / `LAContext`.
protocol CredentialVaultStoring: Sendable {
  /// Existence check that MUST NOT present a biometric prompt.
  func hasStoredCredential() async -> Bool
  func save(_ credential: ArchivedCredential) async throws
  /// Biometric-gated read. `reason` is shown in the system prompt.
  func loadCredential(reason: String) async throws -> ArchivedCredential
  func deleteCredential() async
}

/// Production vault over the default app Keychain (no keychain-access-group; entitlements
/// unchanged). `@unchecked Sendable` because `SecItem*`/`LAContext` are not Sendable; the type
/// holds only immutable `String` configuration and the Keychain is itself thread-safe.
final class KeychainCredentialVault: CredentialVaultStoring, @unchecked Sendable {
  private let service: String
  private let account: String

  init(
    service: String = "com.naminhyeok.woorisai.session",
    account: String = "participant-credential"
  ) {
    self.service = service
    self.account = account
  }

  func hasStoredCredential() async -> Bool {
    // Forbid interaction instead of skipping protected items: `kSecUseAuthenticationUISkip` would
    // silently drop the access-controlled item from the results (`errSecItemNotFound`), making the
    // stored session invisible. With interaction forbidden the item stays in the results and
    // surfaces as `errSecInteractionNotAllowed`, still without ever presenting a prompt.
    let context = LAContext()
    context.interactionNotAllowed = true
    var query = baseQuery()
    query[kSecReturnData as String] = false
    query[kSecReturnAttributes as String] = true
    query[kSecUseAuthenticationContext as String] = context
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    // `interactionNotAllowed` means "exists but would require auth"; `authFailed` means "exists
    // but biometry is locked out" — both are still present, and the locked screen's PIN fallback
    // covers the lockout case.
    return status == errSecSuccess || status == errSecInteractionNotAllowed
      || status == errSecAuthFailed
  }

  func save(_ credential: ArchivedCredential) async throws {
    guard
      let access = SecAccessControlCreateWithFlags(
        nil,
        kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly,
        .biometryCurrentSet,
        nil
      )
    else {
      throw CredentialVaultError.unavailable
    }

    // Overwrite any prior item so a re-login always replaces cleanly. Deleting an
    // access-controlled item does not require authentication.
    SecItemDelete(baseQuery() as CFDictionary)

    var attributes = baseQuery()
    attributes[kSecAttrAccessControl as String] = access
    attributes[kSecValueData as String] = credential.rawData
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw CredentialVaultError.failed
    }
  }

  func loadCredential(reason: String) async throws -> ArchivedCredential {
    // The biometric read blocks until the user responds. Offload to a global queue so the async
    // function suspends instead of blocking the caller's (or a cooperative pool) executor.
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        let context = LAContext()
        context.localizedReason = reason
        var query = self.baseQuery()
        query[kSecReturnData as String] = true
        query[kSecUseAuthenticationContext as String] = context

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
          if let data = item as? Data, let archive = ArchivedCredential(rawData: data) {
            continuation.resume(returning: archive)
          } else {
            continuation.resume(throwing: CredentialVaultError.itemCorrupted)
          }
        case errSecUserCanceled:
          continuation.resume(throwing: CredentialVaultError.cancelled)
        case errSecItemNotFound:
          // The unlock flow only reads after a positive presence check, so "not found" at read
          // time means the item was invalidated (biometry re-enrollment) — not "try again later".
          continuation.resume(throwing: CredentialVaultError.invalidated)
        default:
          // Auth failure, lockout, or any other status. The UI offers PIN as the recovery path.
          continuation.resume(throwing: CredentialVaultError.failed)
        }
      }
    }
  }

  func deleteCredential() async {
    SecItemDelete(baseQuery() as CFDictionary)
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}

/// An empty, no-op vault. Used as the `AuthenticationModel` default and in the test/UI-test
/// dependency branches so session restore never finds a stored credential.
struct InertCredentialVault: CredentialVaultStoring {
  func hasStoredCredential() async -> Bool { false }
  func save(_ credential: ArchivedCredential) async throws {}
  func loadCredential(reason: String) async throws -> ArchivedCredential {
    throw CredentialVaultError.unavailable
  }
  func deleteCredential() async {}
}
