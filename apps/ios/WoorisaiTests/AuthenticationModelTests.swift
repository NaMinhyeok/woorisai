import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct AuthenticationModelTests {
  private let option = LoginOption(slot: 1, displayName: "봄")

  @Test
  func acceptsOnlyExactlyFourASCIIDigits() async {
    let store = InMemoryCredentialStore()
    let model = AuthenticationModel(
      validator: ScriptedCredentialValidator(store: store, steps: []),
      credentialStore: store
    )
    await model.select(option)

    model.updatePIN("12")
    #expect(model.pin == "12")
    #expect(!model.canSubmit)

    model.updatePIN("１２３４")
    model.updatePIN("12345")
    #expect(model.pin == "12")

    model.updatePIN("0123")
    #expect(model.pin == "0123")
    #expect(model.canSubmit)
  }

  @Test
  func successfulValidationAuthenticatesAndErasesPIN() async {
    let store = InMemoryCredentialStore()
    let participant = AuthenticatedParticipant(slot: .one, displayName: "봄")
    let validator = ScriptedCredentialValidator(
      store: store,
      steps: [.success(participant)]
    )
    let model = AuthenticationModel(validator: validator, credentialStore: store)
    await model.select(option)
    model.updatePIN("0123")

    model.submit()

    await authExpectEventually {
      model.state == .authenticated(participant)
    }
    #expect(model.pin.isEmpty)
    #expect(await store.containsCredential)
    #expect(await validator.attemptCount == 1)
  }

  @Test
  func unauthorizedClearsPINAndAsksForItAgain() async {
    let store = InMemoryCredentialStore()
    let validator = ScriptedCredentialValidator(store: store, steps: [.credentialRejected])
    let model = AuthenticationModel(validator: validator, credentialStore: store)
    await model.select(option)
    model.updatePIN("9999")

    model.submit()

    await authExpectEventually {
      model.state == .credentialRejected(self.option)
    }
    #expect(model.pin.isEmpty)
    #expect(!model.canSubmit)
    #expect(await !store.containsCredential)
  }

  @Test
  func transientFailureRetriesOnlyAfterUserAction() async {
    let store = InMemoryCredentialStore()
    let participant = AuthenticatedParticipant(slot: .one, displayName: "봄")
    let validator = ScriptedCredentialValidator(
      store: store,
      steps: [.unavailable, .success(participant)]
    )
    let model = AuthenticationModel(validator: validator, credentialStore: store)
    await model.select(option)
    model.updatePIN("0123")

    model.submit()
    await authExpectEventually {
      model.state == .unavailable(self.option)
    }
    #expect(await validator.attemptCount == 1)
    #expect(model.pin == "0123")

    model.retry()
    await authExpectEventually {
      model.state == .authenticated(participant)
    }
    #expect(await validator.attemptCount == 2)
  }

  @Test
  func cancelIgnoresLateValidationAndClearsMemoryCredential() async {
    let store = InMemoryCredentialStore()
    let validator = ControlledCredentialValidator(store: store)
    let model = AuthenticationModel(validator: validator, credentialStore: store)
    await model.select(option)
    model.updatePIN("0123")
    model.submit()
    await authExpectEventually { await validator.requestCount == 1 }
    #expect(await store.containsCredential)

    await model.cancel()
    #expect(model.state == .choosingParticipant)
    #expect(await !store.containsCredential)

    await validator.succeed()
    await Task.yield()
    #expect(model.state == .choosingParticipant)
    #expect(await !store.containsCredential)
  }

  @Test
  func localSignOutClearsAuthenticatedStateAndCredential() async {
    let store = InMemoryCredentialStore()
    let participant = AuthenticatedParticipant(slot: .one, displayName: "봄")
    let model = AuthenticationModel(
      validator: ScriptedCredentialValidator(store: store, steps: [.success(participant)]),
      credentialStore: store
    )
    await model.select(option)
    model.updatePIN("0123")
    model.submit()
    await authExpectEventually { model.authenticatedParticipant == participant }

    await model.signOut()

    #expect(model.state == .choosingParticipant)
    #expect(model.pin.isEmpty)
    #expect(await !store.containsCredential)
  }

  @Test
  func cancelledOldValidationCannotClearNewSuccessfulCredential() async {
    let store = InMemoryCredentialStore()
    let validator = OverlappingCredentialValidator(store: store)
    let model = AuthenticationModel(validator: validator, credentialStore: store)
    let secondOption = LoginOption(slot: 2, displayName: "여름")

    await model.select(option)
    model.updatePIN("1111")
    model.submit()
    await authExpectEventually { await validator.requestCount == 1 }

    await model.select(secondOption)
    model.updatePIN("2222")
    model.submit()
    await authExpectEventually { await validator.requestCount == 2 }
    await validator.succeed(request: 1, participant: .init(slot: .two, displayName: "여름"))
    await authExpectEventually {
      model.authenticatedParticipant == .init(slot: .two, displayName: "여름")
    }

    await validator.failWithCancellation(request: 0)
    await Task.yield()

    #expect(model.authenticatedParticipant == .init(slot: .two, displayName: "여름"))
    #expect(await store.containsCredential)
  }
}

private actor ScriptedCredentialValidator: CredentialValidating {
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
    guard !steps.isEmpty else { throw AuthenticationTestFailure.unexpectedValidation }
    let step = steps.removeFirst()
    switch step {
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

private actor ControlledCredentialValidator: CredentialValidating {
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
      // The fake deliberately completes late to prove the model generation guard.
    }
  }

  func succeed() {
    continuation?.resume(returning: AuthenticatedParticipant(slot: .one, displayName: "봄"))
    continuation = nil
  }
}

private actor OverlappingCredentialValidator: CredentialValidating {
  private let store: InMemoryCredentialStore
  private var continuations:
    [Int: CheckedContinuation<AuthenticatedParticipant, any Error>] = [:]
  private(set) var requestCount = 0

  init(store: InMemoryCredentialStore) {
    self.store = store
  }

  func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant {
    let request = requestCount
    requestCount += 1
    await store.replace(with: credential)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        continuations[request] = continuation
      }
    } onCancel: {
      // Deliberately complete out of order after the replacement validation succeeds.
    }
  }

  func succeed(request: Int, participant: AuthenticatedParticipant) {
    continuations.removeValue(forKey: request)?.resume(returning: participant)
  }

  func failWithCancellation(request: Int) {
    continuations.removeValue(forKey: request)?.resume(throwing: CancellationError())
  }
}

private enum AuthenticationTestFailure: Error, Sendable {
  case unexpectedValidation
}

@MainActor
private func authExpectEventually(
  _ condition: @escaping @MainActor () async -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<200 {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("인증 상태가 제한 시간 안에 수렴하지 않았습니다.", sourceLocation: sourceLocation)
}
