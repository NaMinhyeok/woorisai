import Observation
import WoorisaiAPI

/// Why a biometric unlock could not complete, surfaced on the locked screen.
enum BiometricUnlockFailure: Equatable, Sendable {
  case cancelled
  case offline
  /// Biometry is locked out (too many failed attempts). Retrying in-app is futile until the
  /// device passcode unlocks biometry again, so the UI must steer to PIN instead of "재시도".
  case biometryLockedOut
  case failed
}

/// Why a stored session ended without the user asking it to — shown once on the login screen so a
/// silent drop back to the participant chooser never looks like "Face ID가 고장났다".
enum StoredSessionNotice: Equatable, Sendable {
  /// The Keychain item was permanently invalidated (biometry re-enrollment).
  case invalidated
  /// The server rejected the stored credential (PIN changed).
  case rejected
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

  /// One-shot explanation for a stored session that ended on its own (invalidated / rejected).
  /// Shown on the login screen; cleared as soon as the user moves on to a participant.
  private(set) var storedSessionNotice: StoredSessionNotice?

  /// Whether the vault currently holds a credential — backs the settings toggle. Refreshed via
  /// `refreshRememberedSessionStatus()` and kept current by the settings actions below.
  private(set) var isSessionRemembered = false

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

  /// Refresh both settings-toggle inputs: whether biometrics can gate a vault at all, and whether
  /// a credential is currently stored.
  func refreshRememberedSessionStatus() async {
    canOfferRemembering = await biometricProbe.availability().canPromptForUnlock
    isSessionRemembered = await vault.hasStoredCredential()
  }

  /// Settings-driven opt-in AFTER login: persist the active session's credential so the user does
  /// not have to sign out and back in just to enable Face ID unlock.
  func rememberCurrentSession() async {
    guard case .authenticated = state,
      let archive = await credentialStore.archivedCurrentCredential()
    else {
      isSessionRemembered = false
      return
    }
    do {
      try await vault.save(archive)
      isSessionRemembered = true
    } catch {
      isSessionRemembered = false
    }
  }

  /// Settings-driven opt-out: forget the stored credential without ending the current session.
  func forgetRememberedSession() async {
    await vault.deleteCredential()
    isSessionRemembered = false
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
    storedSessionNotice = nil
    state = .enteringPIN(option)
    await credentialStore.clear()
  }

  func updatePIN(_ newValue: String) {
    // Pasted PINs commonly carry stray whitespace ("1234 ", "12 34"); strip it instead of
    // silently rejecting the whole paste with no feedback.
    let sanitized = String(newValue.unicodeScalars.filter { !$0.properties.isWhitespace })
    let bytes = Array(sanitized.utf8)
    guard bytes.count <= 4, bytes.allSatisfy(Self.isASCIIDigit) else {
      return
    }
    // Refocusing a SecureField makes iOS clear it and push "" through the binding. Only a real
    // change counts as "the user started retyping" — otherwise the programmatic no-op would
    // dismiss the credential-rejected message the instant it appears.
    guard sanitized != pin else { return }
    pin = sanitized

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
          self.isSessionRemembered = true
        } else {
          // A non-remembered login must invalidate whatever the vault held before: a stale
          // archive would let the next launch biometric-unlock as whoever logged in previously —
          // including the other participant.
          await vault.deleteCredential()
          guard self.requestGeneration == generation else { return }
          self.isSessionRemembered = false
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
    isSessionRemembered = false
    await cancel()
  }

  func requirePINAgain(for participant: AuthenticatedParticipant) async {
    // The server rejected this credential, so it can never unlock again — forget it first to avoid
    // a launch → Face ID → rehydrate-rejected-credential → reject loop.
    await vault.deleteCredential()
    isSessionRemembered = false
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
    var outcome = Self.unlockOutcome(for: error, kind: context.kind)
    if case .locked(let lockedContext) = outcome.state, lockedContext.lastFailure == .failed {
      // A generic failure while biometrics report unusable is a lockout: retrying in-app cannot
      // succeed until the device passcode re-enables biometry, so say that instead of "재시도".
      let availability = await biometricProbe.availability()
      if !availability.canPromptForUnlock {
        outcome = UnlockOutcome(
          state: .locked(
            BiometricUnlockContext(kind: context.kind, lastFailure: .biometryLockedOut)
          ),
          forgetsVault: false,
          notice: nil
        )
      }
    }
    await credentialStore.clear()
    if outcome.forgetsVault {
      await vault.deleteCredential()
      isSessionRemembered = false
    }
    guard requestGeneration == generation else { return }
    unlockTask = nil
    storedSessionNotice = outcome.notice
    state = outcome.state
  }

  /// The unlock-failure policy — how a Keychain/biometric or server error becomes a UX state,
  /// whether the stored credential should be forgotten, and what the login screen should tell the
  /// user about it. This is the one place that decides "retry biometrics", "fall back to PIN", or
  /// "forget and start over". Every terminal drop to `.choosingParticipant` MUST carry a notice —
  /// a silent jump from a successful Face ID to the participant chooser reads as a broken app.
  private static func unlockOutcome(
    for error: any Error,
    kind: BiometricKind
  ) -> UnlockOutcome {
    switch error {
    case WoorisaiAPIError.credentialRejected, WoorisaiAPIError.credentialMissing,
      ParticipantCredentialError.invalidPIN, CredentialVaultError.itemCorrupted:
      // The stored credential can never succeed (server rejected it, or the blob is corrupt):
      // forget it and drop to a fresh PIN login.
      return UnlockOutcome(state: .choosingParticipant, forgetsVault: true, notice: .rejected)
    case CredentialVaultError.invalidated:
      // Biometry re-enrollment permanently killed the item. Without the purge this loops forever:
      // the presence check still sees the item, so every launch re-locks against a dead archive.
      return UnlockOutcome(state: .choosingParticipant, forgetsVault: true, notice: .invalidated)
    case CredentialVaultError.cancelled:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .cancelled)),
        forgetsVault: false,
        notice: nil
      )
    case WoorisaiAPIError.transport, WoorisaiAPIError.serviceUnavailable,
      CredentialVaultError.unavailable:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .offline)),
        forgetsVault: false,
        notice: nil
      )
    default:
      return UnlockOutcome(
        state: .locked(BiometricUnlockContext(kind: kind, lastFailure: .failed)),
        forgetsVault: false,
        notice: nil
      )
    }
  }

  private struct UnlockOutcome {
    let state: State
    let forgetsVault: Bool
    let notice: StoredSessionNotice?
  }

  private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
  }
}
