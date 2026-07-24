import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct AuthenticationModelSessionTests {
  private let option = LoginOption(slot: 1, displayName: "봄")
  private let participant = AuthenticatedParticipant(slot: .one, displayName: "봄")

  private func archive() throws -> ArchivedCredential {
    try ParticipantCredential(slot: .one, pin: "0123").archived()
  }

  private func availableProbe(_ kind: BiometricKind = .faceID) -> FakeBiometricProbe {
    FakeBiometricProbe(value: BiometricAvailability(kind: kind, canPromptForUnlock: true))
  }

  // MARK: - Restore

  @Test
  func restoreWithoutStoredCredentialFallsToParticipantChooser() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    let model = makeModel(store: store, vault: vault, probe: availableProbe(), restores: true)

    await model.restoreLockedSessionIfAvailable()

    #expect(model.state == .choosingParticipant)
    #expect(await vault.deleteCount == 0)
  }

  @Test
  func restoreWithStoredCredentialAndBiometricsShowsLockedScreen() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let model = makeModel(store: store, vault: vault, probe: availableProbe(.touchID), restores: true)

    await model.restoreLockedSessionIfAvailable()

    #expect(model.state == .locked(BiometricUnlockContext(kind: .touchID, lastFailure: nil)))
    #expect(model.isAwaitingBiometricUnlock)
  }

  @Test
  func restoreWithStoredCredentialButNoBiometricsKeepsVaultAndRequiresPIN() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let probe = FakeBiometricProbe(value: .unavailable)
    let model = makeModel(store: store, vault: vault, probe: probe, restores: true)

    await model.restoreLockedSessionIfAvailable()

    #expect(model.state == .choosingParticipant)
    #expect(await vault.deleteCount == 0)
  }

  // MARK: - Unlock

  @Test
  func unlockSucceedsHydratesStoreAndAuthenticates() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(
      store: store, validator: validator, vault: vault, probe: availableProbe(), restores: true
    )
    await model.restoreLockedSessionIfAvailable()

    model.unlock()

    await sessionExpectEventually { model.authenticatedParticipant == self.participant }
    #expect(await store.containsCredential)
    #expect(await validator.attemptCount == 1)
    #expect(await vault.deleteCount == 0)
  }

  @Test
  func unlockCancelledStaysLockedAndKeepsVault() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .failure(.cancelled))
    let model = makeModel(store: store, vault: vault, probe: availableProbe(), restores: true)
    await model.restoreLockedSessionIfAvailable()

    model.unlock()

    await sessionExpectEventually {
      model.state == .locked(BiometricUnlockContext(kind: .faceID, lastFailure: .cancelled))
    }
    #expect(await vault.deleteCount == 0)
  }

  @Test
  func unlockRejectedForgetsVaultAndReturnsToChooser() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.credentialRejected])
    let model = makeModel(
      store: store, validator: validator, vault: vault, probe: availableProbe(), restores: true
    )
    await model.restoreLockedSessionIfAvailable()

    model.unlock()

    await sessionExpectEventually { model.state == .choosingParticipant }
    #expect(await vault.deleteCount >= 1)
    #expect(await !store.containsCredential)
    #expect(model.storedSessionNotice == .rejected)
  }

  @Test
  func unlockInvalidatedItemForgetsVaultAndExplains() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .failure(.invalidated))
    let model = makeModel(store: store, vault: vault, probe: availableProbe(), restores: true)
    await model.restoreLockedSessionIfAvailable()

    model.unlock()

    // Without the purge this loops forever: the presence check still sees the invalidated item,
    // so every launch would re-lock against an archive that can never be read again.
    await sessionExpectEventually { model.state == .choosingParticipant }
    #expect(await vault.deleteCount >= 1)
    #expect(model.storedSessionNotice == .invalidated)
  }

  @Test
  func selectingParticipantClearsStoredSessionNotice() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .failure(.invalidated))
    let model = makeModel(store: store, vault: vault, probe: availableProbe(), restores: true)
    await model.restoreLockedSessionIfAvailable()
    model.unlock()
    await sessionExpectEventually { model.storedSessionNotice == .invalidated }

    await model.select(option)

    #expect(model.storedSessionNotice == nil)
  }

  @Test
  func unlockGenericFailureWithUnusableBiometryReportsLockout() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .failure(.failed))
    let probe = MutableBiometricProbe(
      value: BiometricAvailability(kind: .faceID, canPromptForUnlock: true)
    )
    let model = makeModel(store: store, vault: vault, probe: probe, restores: true)
    await model.restoreLockedSessionIfAvailable()
    await probe.set(.unavailable)

    model.unlock()

    await sessionExpectEventually {
      model.state
        == .locked(BiometricUnlockContext(kind: .faceID, lastFailure: .biometryLockedOut))
    }
    #expect(await vault.deleteCount == 0)
  }

  @Test
  func unlockOfflineStaysLockedWithOfflineFailureAndKeepsVault() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.unavailable])
    let model = makeModel(
      store: store, validator: validator, vault: vault, probe: availableProbe(), restores: true
    )
    await model.restoreLockedSessionIfAvailable()

    model.unlock()

    await sessionExpectEventually {
      model.state == .locked(BiometricUnlockContext(kind: .faceID, lastFailure: .offline))
    }
    #expect(await vault.deleteCount == 0)
  }

  @Test
  func lateUnlockCompletionAfterCancelDoesNotAuthenticate() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = ControlledSessionValidator(store: store)
    let model = makeModel(
      store: store, validator: validator, vault: vault, probe: availableProbe(), restores: true
    )
    await model.restoreLockedSessionIfAvailable()

    model.unlock()
    await sessionExpectEventually { await validator.requestCount == 1 }

    await model.cancel()
    #expect(model.state == .choosingParticipant)

    await validator.succeed(participant)
    await Task.yield()

    #expect(model.authenticatedParticipant == nil)
    #expect(await !store.containsCredential)
  }

  // MARK: - Save on login

  @Test
  func submitPersistsCredentialWhenRememberingSession() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())

    await model.select(option)
    model.updatePIN("0123")
    model.remembersSession = true
    model.submit()

    await sessionExpectEventually { model.authenticatedParticipant == self.participant }
    #expect(await vault.saveCount == 1)
  }

  @Test
  func submitDoesNotPersistWhenNotRememberingSession() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())

    await model.select(option)
    model.updatePIN("0123")
    model.submit()

    await sessionExpectEventually { model.authenticatedParticipant == self.participant }
    #expect(await vault.saveCount == 0)
  }

  @Test
  func submitWithoutRememberingPurgesStaleVault() async throws {
    // Identity-confusion guard: participant A's archive is in the vault (PIN fallback kept it),
    // participant B logs in without remembering. The stale archive MUST be purged, or the next
    // launch would Face-ID-unlock as A.
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let participantB = AuthenticatedParticipant(slot: .two, displayName: "여름")
    let validator = SessionScriptedValidator(store: store, steps: [.success(participantB)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())

    await model.select(LoginOption(slot: 2, displayName: "여름"))
    model.updatePIN("9876")
    model.submit()

    await sessionExpectEventually { model.authenticatedParticipant == participantB }
    #expect(await vault.saveCount == 0)
    #expect(await vault.deleteCount >= 1)
    #expect(await vault.hasStoredCredential() == false)
  }

  // MARK: - Settings-driven remembering

  @Test
  func rememberCurrentSessionSavesArchiveFromActiveSession() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())
    await model.select(option)
    model.updatePIN("0123")
    model.submit()
    await sessionExpectEventually { model.authenticatedParticipant == self.participant }

    await model.rememberCurrentSession()

    #expect(await vault.saveCount == 1)
    #expect(model.isSessionRemembered)
  }

  @Test
  func forgetRememberedSessionPurgesVaultWithoutEndingSession() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())
    await model.select(option)
    model.updatePIN("0123")
    model.remembersSession = true
    model.submit()
    await sessionExpectEventually { model.authenticatedParticipant == self.participant }

    await model.forgetRememberedSession()

    #expect(await vault.deleteCount >= 1)
    #expect(!model.isSessionRemembered)
    #expect(model.authenticatedParticipant == self.participant)
  }

  @Test
  func rememberCurrentSessionWithoutActiveSessionDoesNotSave() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    let model = makeModel(store: store, vault: vault, probe: availableProbe())

    await model.rememberCurrentSession()

    #expect(await vault.saveCount == 0)
    #expect(!model.isSessionRemembered)
  }

  @Test
  func submitSupersededDuringSaveCompensatesAndDoesNotAuthenticate() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: false, loadResult: .success(try archive()))
    await vault.setBlocksSave(true)
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())

    await model.select(option)
    model.updatePIN("0123")
    model.remembersSession = true
    model.submit()
    await sessionExpectEventually { await vault.saveCount == 1 }

    // Supersede the login while the save is still in flight.
    await model.select(LoginOption(slot: 2, displayName: "여름"))
    await vault.releaseSave()
    await Task.yield()

    #expect(model.authenticatedParticipant == nil)
    #expect(await vault.deleteCount >= 1)
  }

  // MARK: - Teardown semantics

  @Test
  func requirePINAgainForgetsVault() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let validator = SessionScriptedValidator(store: store, steps: [.success(participant)])
    let model = makeModel(store: store, validator: validator, vault: vault, probe: availableProbe())
    await model.select(option)
    model.updatePIN("0123")
    model.submit()
    await sessionExpectEventually { model.authenticatedParticipant == self.participant }

    await model.requirePINAgain(for: participant)

    #expect(await vault.deleteCount >= 1)
    #expect(model.state == .credentialRejected(option))
  }

  @Test
  func lockKeepsVaultAndSignOutAndForgetPurgesIt() async throws {
    let store = InMemoryCredentialStore()
    let vault = FakeCredentialVault(stored: true, loadResult: .success(try archive()))
    let model = makeModel(store: store, vault: vault, probe: availableProbe())

    await model.lock()
    #expect(model.state == .locked(BiometricUnlockContext(kind: .faceID, lastFailure: nil)))
    #expect(await vault.deleteCount == 0)

    await model.signOutAndForget()
    #expect(model.state == .choosingParticipant)
    #expect(await vault.deleteCount >= 1)
  }

  // MARK: - Helpers

  private func makeModel(
    store: InMemoryCredentialStore,
    validator: (any CredentialValidating)? = nil,
    vault: any CredentialVaultStoring,
    probe: any BiometricAvailabilityProbing,
    restores: Bool = false
  ) -> AuthenticationModel {
    AuthenticationModel(
      validator: validator ?? SessionScriptedValidator(store: store, steps: []),
      credentialStore: store,
      vault: vault,
      biometricProbe: probe,
      restoresSession: restores
    )
  }
}

private struct FakeBiometricProbe: BiometricAvailabilityProbing {
  let value: BiometricAvailability
  func availability() async -> BiometricAvailability { value }
}

/// A probe whose answer can change mid-test — models biometry locking out between the restore
/// probe and the post-failure re-probe.
private actor MutableBiometricProbe: BiometricAvailabilityProbing {
  private var value: BiometricAvailability

  init(value: BiometricAvailability) {
    self.value = value
  }

  func set(_ newValue: BiometricAvailability) {
    value = newValue
  }

  func availability() async -> BiometricAvailability { value }
}

private actor FakeCredentialVault: CredentialVaultStoring {
  enum LoadResult: Sendable {
    case success(ArchivedCredential)
    case failure(CredentialVaultError)
  }

  private var stored: Bool
  private let loadResult: LoadResult
  private var blocksSave = false
  private var saveGate: CheckedContinuation<Void, Never>?
  private(set) var saveCount = 0
  private(set) var deleteCount = 0
  private(set) var savedArchive: ArchivedCredential?

  init(stored: Bool, loadResult: LoadResult) {
    self.stored = stored
    self.loadResult = loadResult
  }

  func setBlocksSave(_ blocks: Bool) {
    blocksSave = blocks
  }

  func releaseSave() {
    saveGate?.resume()
    saveGate = nil
  }

  func hasStoredCredential() async -> Bool { stored }

  func save(_ credential: ArchivedCredential) async throws {
    saveCount += 1
    savedArchive = credential
    if blocksSave {
      await withCheckedContinuation { self.saveGate = $0 }
    }
    stored = true
  }

  func loadCredential(reason: String) async throws -> ArchivedCredential {
    switch loadResult {
    case .success(let archive): return archive
    case .failure(let error): throw error
    }
  }

  func deleteCredential() async {
    deleteCount += 1
    stored = false
  }
}

private actor SessionScriptedValidator: CredentialValidating {
  enum Step: Sendable {
    case credentialRejected
    case success(AuthenticatedParticipant)
    case unavailable
  }

  private let store: InMemoryCredentialStore
  private var steps: [Step]
  private(set) var attemptCount = 0

  init(store: InMemoryCredentialStore, steps: [Step]) {
    self.store = store
    self.steps = steps
  }

  func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant {
    attemptCount += 1
    guard !steps.isEmpty else { throw SessionTestFailure.unexpectedValidation }
    switch steps.removeFirst() {
    case .credentialRejected:
      await store.clear()
      throw WoorisaiAPIError.credentialRejected
    case .success(let participant):
      await store.replace(with: credential)
      return participant
    case .unavailable:
      throw WoorisaiAPIError.serviceUnavailable
    }
  }
}

private actor ControlledSessionValidator: CredentialValidating {
  private let store: InMemoryCredentialStore
  private var continuation: CheckedContinuation<AuthenticatedParticipant, any Error>?
  private(set) var requestCount = 0

  init(store: InMemoryCredentialStore) {
    self.store = store
  }

  func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant {
    requestCount += 1
    await store.replace(with: credential)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
      }
    } onCancel: {
      // The fake completes late on purpose to prove the model's generation guard.
    }
  }

  func succeed(_ participant: AuthenticatedParticipant) {
    continuation?.resume(returning: participant)
    continuation = nil
  }
}

private enum SessionTestFailure: Error, Sendable {
  case unexpectedValidation
}

@MainActor
private func sessionExpectEventually(
  _ condition: @escaping @MainActor () async -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<200 {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("세션 상태가 제한 시간 안에 수렴하지 않았습니다.", sourceLocation: sourceLocation)
}
