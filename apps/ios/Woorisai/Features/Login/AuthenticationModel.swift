import Observation
import WoorisaiAPI

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
  }

  private(set) var state: State = .choosingParticipant
  private(set) var pin = ""

  var canSubmit: Bool {
    pin.utf8.count == 4 && pin.utf8.allSatisfy(Self.isASCIIDigit)
      && selectedOption != nil
      && !isValidating
  }

  var isValidating: Bool {
    if case .validating = state { return true }
    return false
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
    case .choosingParticipant, .authenticated:
      return nil
    }
  }

  @ObservationIgnored
  private let validator: any CredentialValidating

  @ObservationIgnored
  private let credentialStore: InMemoryCredentialStore

  @ObservationIgnored
  private var validationTask: Task<Void, Never>?

  @ObservationIgnored
  private var requestGeneration: UInt = 0

  init(
    validator: any CredentialValidating,
    credentialStore: InMemoryCredentialStore
  ) {
    self.validator = validator
    self.credentialStore = credentialStore
  }

  func select(_ option: LoginOption) async {
    guard ParticipantSlot(rawValue: option.slot) != nil else {
      state = .failed(option)
      return
    }

    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
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
    validationTask?.cancel()
    state = .validating(option)

    validationTask = Task { @MainActor [weak self] in
      do {
        let participant = try await validator.validateCredential(credential)
        try Task.checkCancellation()
        guard let self, self.requestGeneration == generation else { return }
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
    pin = ""
    state = .choosingParticipant
    await credentialStore.clear()
  }

  func signOut() async {
    await cancel()
  }

  func requirePINAgain(for participant: AuthenticatedParticipant) async {
    requestGeneration &+= 1
    validationTask?.cancel()
    validationTask = nil
    pin = ""
    await credentialStore.clear()
    state = .credentialRejected(
      LoginOption(slot: participant.slot.rawValue, displayName: participant.displayName)
    )
  }

  private static func isASCIIDigit(_ byte: UInt8) -> Bool {
    (0x30...0x39).contains(byte)
  }
}
