import Observation
import WoorisaiAPI

/// Why a biometric unlock could not complete, surfaced on the locked screen.
enum BiometricUnlockFailure: Equatable, Sendable {
  case cancelled
  case offline
  case failed
}

struct BiometricUnlockContext: Equatable, Sendable {
  let kind: BiometricKind
  var lastFailure: BiometricUnlockFailure?
}

@MainActor
@Observable
final class AuthenticationModel {
  enum State: Equatable, Sendable {
    case choosingParticipant
    case enteringPIN(LoginOption)
    case validating(LoginOption)
    case credentialRejected(LoginOption)
    case unavailable(LoginOption)
    case failed(LoginOption)
    case authenticated(AuthenticatedParticipant)
    /// Launch-time: deciding whether a stored session exists before any UI commits.
    case restoring
    /// A stored session exists; waiting for the user to unlock with biometrics.
    case locked(BiometricUnlockContext)
    /// Biometric unlock is in flight (Keychain read + server revalidation).
    case unlocking(BiometricUnlockContext)
  }

  private(set) var state: State
  private(set) var pin = ""

  /// Opt-in, default off: persist the credential to the vault on the next successful login.
  var remembersSession = false

  /// Whether the "remember with biometrics" toggle should be offered. Refreshed from the probe;
  /// stays false wherever biometrics are unavailable (including tests / UI tests).
  private(set) var canOfferRemembering = false

  var canSubmit: Bool {
    pin.utf8.count == 4 && pin.utf8.allSatisfy(Self.isASCIIDigit)
      && selectedOption != nil
      && !isValidating
  }

  var isValidating: Bool {
    if case .validating = state { return true }
    return false
  }

  /// True while the biometric unlock screen (restore / locked / unlocking) should be shown.
  var isAwaitingBiometricUnlock: Bool {
    switch state {
    case .restoring, .locked, .unlocking:
      return true
    case .choosingParticipant, .enteringPIN, .validating, .credentialRejected,
      .unavailable, .failed, .authenticated:
      return false
    }
  }

  var authenticatedParticipant: AuthenticatedParticipant? {
    if case .authenticated(let participant) = state { return participant }
    return nil
  }

  var selectedOption: LoginOption? {
    switch state {
    case .enteringPIN(let option), .validating(let option),
      .credentialRejected(let option), .unavailable(let option), .failed(let option):
      return option
    case .choosingParticipant, .authenticated, .restoring, .locked, .unlocking:
      return nil
    }
  }

  @ObservationIgnored
  private let validator: any CredentialValidating

  @ObservationIgnored
  private let credentialStore: InMemoryCredentialStore

  @ObservationIgnored
  private let vault: any CredentialVaultStoring

  @ObservationIgnored
  private let biometricProbe: any BiometricAvailabilityProbing

  @ObservationIgnored
  private var validationTask: Task<Void, Never>?

  @ObservationIgnored
  private var unlockTask: Task<Void, Never>?

  @ObservationIgnored
  private var requestGeneration: UInt = 0

  private static let unlockReason = "우리사이 잠금을 해제합니다."

  init(
    validator: any CredentialValidating,
    credentialStore: InMemoryCredentialStore,
    vault: any CredentialVaultStoring = InertCredentialVault(),
    biometricProbe: any BiometricAvailabilityProbing = UnavailableBiometricProbe(),
    restoresSession: Bool = false
  ) {
    self.validator = validator
    self.credentialStore = credentialStore
    self.vault = vault
    self.biometricProbe = biometricProbe
    state = restoresSession ? .restoring : .choosingParticipant
  }

  /// Probe biometric availability so the login screen can decide whether to offer the toggle.
  func refreshRememberOption() async {
    canOfferRemembering = await biometricProbe.availability().canPromptForUnlock
  }

  func select(_ option: LoginOption) async {
    guard ParticipantSlot(rawValue: option.slot) != nil else {
      state = .failed(option)
      return
    }

    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
    unlockTask?.cancel()
    unlockTask = nil
    pin = ""
    state = .enteringPIN(option)
    await credentialStore.clear()
  }

  func updatePIN(_ newValue: String) {
    let bytes = Array(newValue.utf8)
    guard bytes.count <= 4, bytes.allSatisfy(Self.isASCIIDigit) else {
      return
    }
    pin = newValue

    if case .credentialRejected(let option) = state {
      state = .enteringPIN(option)
    }
  }

  func submit() {
    guard canSubmit,
      let option = selectedOption,
      let slot = ParticipantSlot(rawValue: option.slot),
      let credential = try? ParticipantCredential(slot: slot, pin: pin)
    else {
      return
    }

    requestGeneration &+= 1
    let generation = requestGeneration
    let validator = validator
    let vault = vault
    let shouldRemember = remembersSession
    validationTask?.cancel()
    state = .validating(option)

    validationTask = Task { @MainActor [weak self] in
      do {
        let participant = try await validator.validateCredential(credential)
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation else { return }

        if shouldRemember {
          // Best effort: a failed Keychain write must never block login.
          try? await vault.save(credential.archived())
          guard self.requestGeneration == generation else {
            // Superseded during the save (cancel/select/lock): undo persistence, do not authenticate.
            await vault.deleteCredential()
            return
          }
        }

        self.pin = ""
        self.state = .authenticated(participant)
        self.validationTask = nil
      } catch is CancellationError {
        guard let self, self.requestGeneration == generation else { return }
        await self.credentialStore.clear()
        self.validationTask = nil
      } catch WoorisaiAPIError.credentialRejected {
        guard let self, self.requestGeneration == generation else { return }
        self.pin = ""
        self.state = .credentialRejected(option)
        self.validationTask = nil
      } catch WoorisaiAPIError.serviceUnavailable {
        guard let self, self.requestGeneration == generation else { return }
        self.state = .unavailable(option)
        self.validationTask = nil
      } catch {
        guard let self,
          self.requestGeneration == generation,
          !Task.isCancelled
        else { return }
        self.state = .failed(option)
        self.validationTask = nil
      }
    }
  }

  func retry() {
    switch state {
    case .unavailable, .failed:
      submit()
    default:
      break
    }
  }

  func cancel() async {
    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
    unlockTask?.cancel()
    unlockTask = nil
    pin = ""
    state = .choosingParticipant
    await credentialStore.clear()
  }

  func signOut() async {
    await cancel()
  }

  /// Full sign-out that also forgets the device: purges the vault so the next launch requires a
  /// fresh PIN login. Backs the settings "이 기기에서 로그인 정보 지우기" action.
  func signOutAndForget() async {
    await vault.deleteCredential()
    await cancel()
  }

  func requirePINAgain(for participant: AuthenticatedParticipant) async {
    // The server rejected this credential, so it can never unlock again — forget it first to avoid
    // a launch → Face ID → rehydrate-rejected-credential → reject loop.
    await vault.deleteCredential()
    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
    unlockTask?.cancel()
    unlockTask = nil
    pin = ""
    await credentialStore.clear()
    state = .credentialRejected(
      LoginOption(slot: participant.slot.rawValue, displayName: participant.displayName)
    )
  }

  // MARK: - Biometric session

  /// Launch-time resolution: is there a stored session, and can biometrics reopen it? Idempotent;
  /// only advances out of `.restoring`.
  func restoreLockedSessionIfAvailable() async {
    guard case .restoring = state else { return }

    guard await vault.hasStoredCredential() else {
      if case .restoring = state { state = .choosingParticipant }
      return
    }
    let availability = await biometricProbe.availability()
    guard case .restoring = state else { return }

    guard availability.canPromptForUnlock else {
      // Biometrics unenrolled/unavailable: keep the vault, require a PIN login this launch.
      state = .choosingParticipant
      return
    }
    state = .locked(BiometricUnlockContext(kind: availability.kind, lastFailure: nil))
  }

  /// Present the biometric prompt, then revalidate the stored credential against the server (which
  /// also rehydrates the in-memory store and yields the display name we never persist).
  func unlock() {
    guard case .locked(let context) = state else { return }

    requestGeneration &+= 1
    let generation = requestGeneration
    let validator = validator
    let vault = vault
    validationTask?.cancel()
    unlockTask?.cancel()
    state = .unlocking(context)

    unlockTask = Task { @MainActor [weak self] in
      do {
        let archived = try await vault.loadCredential(reason: Self.unlockReason)
        try Task.checkCancellation()
        let credential = try ParticipantCredential(archived: archived)
        let participant = try await validator.validateCredential(credential)
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation else { return }
        self.pin = ""
        self.state = .authenticated(participant)
        self.unlockTask = nil
      } catch is CancellationError {
        guard let self, self.requestGeneration == generation else { return }
        await self.credentialStore.clear()
        self.unlockTask = nil
      } catch {
        guard let self, self.requestGeneration == generation else { return }
        await self.handleUnlockFailure(error, context: context, generation: generation)
      }
    }
  }

  /// Leave the locked screen and start a normal PIN login. Keeps the vault: a transient biometric
  /// failure or a one-off preference must not forget the device.
  func fallBackToPINLogin() async {
    requestGeneration &+= 1
    unlockTask?.cancel()
    unlockTask = nil
    validationTask?.cancel()
    validationTask = nil
    pin = ""
    state = .choosingParticipant
    await credentialStore.clear()
  }

  /// Lock the app: clear the in-memory session but keep the vault so Face ID can reopen it. If no
  /// remembered credential exists, this degrades to a full sign-out (PIN required next time).
  func lock() async {
    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
    unlockTask?.cancel()
    unlockTask = nil
    pin = ""
    await credentialStore.clear()

    let availability = await biometricProbe.availability()
    if await vault.hasStoredCredential(), availability.canPromptForUnlock {
      state = .locked(BiometricUnlockContext(kind: availability.kind, lastFailure: nil))
    } else {
      state = .choosingParticipant
    }
  }

  private func handleUnlockFailure(
    _ error: any Error,
    context: BiometricUnlockContext,
    generation: UInt
  ) async {
    let outcome = Self.unlockOutcome(for: error, kind: context.kind)
    await credentialStore.clear()
    if outcome.forgetsVault {
      await vault.deleteCredential()
    }
    guard requestGeneration == generation else { return }
    unlockTask = nil
    state = outcome.state
  }

  /// The unlock-failure policy — how a Keychain/biometric or server error becomes a UX state, and
  /// whether the stored credential should be forgotten. This is the one place that decides "retry
  /// biometrics", "fall back to PIN", or "forget and start over".
  private static func unlockOutcome(
    for error: any Error,
    kind: BiometricKind
  ) -> UnlockOutcome {
    switch error {
    case WoorisaiAPIError.credentialRejected, WoorisaiAPIError.credentialMissing,
      ParticipantCredentialError.invalidPIN, CredentialVaultError.itemCorrupted:
      // The stored credential can never succeed (server rejected it, or the blob is corrupt):
      // forget it and drop to a fresh PIN login.
      return UnlockOutcome(state: .choosingParticipant, forgetsVault: true)
    case CredentialVaultError.cancelled:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .cancelled)),
        forgetsVault: false
      )
    case WoorisaiAPIError.transport, WoorisaiAPIError.serviceUnavailable,
      CredentialVaultError.unavailable:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .offline)),
        forgetsVault: false
      )
    default:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .failed)),
        forgetsVault: false
      )
    }
  }

  private struct UnlockOutcome {
    let state: State
    let forgetsVault: Bool
  }

  private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
  }
}
