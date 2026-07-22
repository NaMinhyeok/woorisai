import Observation
import WoorisaiAPI

private actor NotificationDeadlineGate<Value: Sendable> {
  private var continuation: CheckedContinuation<Value, Never>?

  init(_ continuation: CheckedContinuation<Value, Never>) {
    self.continuation = continuation
  }

  @discardableResult
  func resolve(_ value: Value) -> Bool {
    guard let continuation else { return false }
    self.continuation = nil
    continuation.resume(returning: value)
    return true
  }
}

enum NotificationPermissionStatus: Equatable, Sendable {
  case notDetermined
  case denied
  case authorized
  case provisional
  case ephemeral

  var permitsRegistration: Bool {
    switch self {
    case .authorized, .provisional, .ephemeral:
      true
    case .notDetermined, .denied:
      false
    }
  }
}

protocol NotificationPermissionAuthorizing: Sendable {
  func currentStatus() async -> NotificationPermissionStatus
  func requestAuthorization() async throws -> NotificationPermissionStatus
}

/// Firebase remains behind this app-owned boundary. The implementation may rotate values, but it
/// must not persist or log them in feature code.
protocol NotificationInstallationIDProviding: Sendable {
  func prepareRegistration() async throws
  func currentInstallationID() async throws -> String
}

extension NotificationInstallationIDProviding {
  func prepareRegistration() async throws {}
}

@MainActor
@Observable
final class NotificationModel {
  enum State: Equatable, Sendable {
    case idle
    case checkingPermission
    case registering
    case registered
    case permissionDenied
    case unavailable
    case failed
  }

  private(set) var state: State = .idle
  private(set) var authenticationRequired = false
  private(set) var pendingRefetchIntents: [NotificationResourceRefetchIntent] = []

  @ObservationIgnored
  private let permissions: any NotificationPermissionAuthorizing

  @ObservationIgnored
  private let installationIDs: any NotificationInstallationIDProviding

  @ObservationIgnored
  private let service: any NotificationFIDServing

  @ObservationIgnored
  private var registrationTask: Task<Void, Never>?

  @ObservationIgnored
  private var currentRegistrationAttempt: UInt?

  @ObservationIgnored
  private var registrationAttemptSequence: UInt = 0

  @ObservationIgnored
  private var registrationRefreshPending = false

  @ObservationIgnored
  private var sessionGeneration: UInt = 0

  @ObservationIgnored
  private var remoteRegistrationFailureSequence: UInt = 0

  @ObservationIgnored
  private var registeredInstallationID: NotificationInstallationID?

  @ObservationIgnored
  private var registrationCandidate: NotificationInstallationID?

  @ObservationIgnored
  private var authenticatedSessionIsActive = false

  var canRetryRegistration: Bool {
    guard authenticatedSessionIsActive else { return false }
    return state == .unavailable || state == .failed
  }

  init(
    permissions: any NotificationPermissionAuthorizing,
    installationIDs: any NotificationInstallationIDProviding,
    service: any NotificationFIDServing
  ) {
    self.permissions = permissions
    self.installationIDs = installationIDs
    self.service = service
  }

  /// Call only after Basic credential validation succeeds.
  func authenticatedSessionDidStart() {
    authenticatedSessionIsActive = true
    refreshRegistration()
  }

  /// Firebase can rotate its installation identifier while the app is installed.
  func installationIDDidChange() {
    guard authenticatedSessionIsActive else { return }
    refreshRegistration()
  }

  /// Reconcile permission and provider state when the user returns from Settings or a transient
  /// remote-registration failure. Permission is read again instead of relying on the previous
  /// in-memory result.
  func applicationDidBecomeActive() {
    guard authenticatedSessionIsActive else { return }
    switch state {
    case .permissionDenied, .unavailable, .failed:
      refreshRegistration()
    case .idle, .checkingPermission, .registering, .registered:
      break
    }
  }

  /// APNs errors are deliberately reduced to a privacy-safe availability state. The provider
  /// callback or the next foreground reconciliation is the retry trigger; no device identifier or
  /// provider error detail enters observable feature state.
  func remoteNotificationRegistrationDidFail() {
    guard authenticatedSessionIsActive else { return }
    remoteRegistrationFailureSequence &+= 1
    state = .unavailable
  }

  /// A successful APNs/FCM callback can arrive after an earlier failure and may reuse the same FID.
  /// Retry only from the unavailable state so routine duplicate callbacks cannot form a feedback
  /// loop with `prepareRegistration()`.
  func remoteNotificationRegistrationDidSucceed() {
    guard authenticatedSessionIsActive, state == .unavailable else { return }
    refreshRegistration()
  }

  func retryRegistration() {
    guard canRetryRegistration else { return }
    refreshRegistration()
  }

  /// Must be awaited before the authentication model clears its in-memory Basic credential.
  /// Backend unregister is intentionally best effort: local sign-out always completes.
  func unregisterBeforeSignOut(timeout: Duration = .seconds(3)) async {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    authenticatedSessionIsActive = false
    sessionGeneration &+= 1
    registrationRefreshPending = false

    let pendingRegistration = registrationTask
    let pendingAttempt = currentRegistrationAttempt
    // Cancel the transport before the final candidate DELETE. If the register reached the server
    // despite cancellation, the attempt performs its own uncancelled compensating DELETE before
    // settling. The bounded wait preserves the app-level sign-out deadline.
    pendingRegistration?.cancel()
    if let pendingRegistration {
      let waitBudget = remaining(until: deadline, clock: clock) / 2
      _ = await valueBeforeDeadline(timeout: waitBudget, timeoutValue: false) {
        await pendingRegistration.value
        return true
      }
    }

    var candidates: [NotificationInstallationID] = []
    appendUnique(registrationCandidate, to: &candidates)
    appendUnique(registeredInstallationID, to: &candidates)

    if !candidates.isEmpty {
      let knownBudget = min(
        remaining(until: deadline, clock: clock),
        .seconds(1)
      )
      await unregister(candidates, timeout: knownBudget)
    }

    if let rawValue = await currentInstallationID(
      timeout: remaining(until: deadline, clock: clock)),
      let current = try? NotificationInstallationID(rawValue)
    {
      if !candidates.contains(current) {
        await unregister(
          [current],
          timeout: remaining(until: deadline, clock: clock)
        )
      }
    }

    registeredInstallationID = nil
    registrationCandidate = nil
    pendingRegistration?.cancel()
    if currentRegistrationAttempt == pendingAttempt {
      registrationTask = nil
      currentRegistrationAttempt = nil
    }
    authenticationRequired = false
    state = .idle
  }

  func receiveNotification(eventType: String?, resourceID: String?) {
    guard
      let intent = NotificationPayloadRouter.refetchIntent(
        eventType: eventType,
        resourceID: resourceID
      ), !pendingRefetchIntents.contains(intent)
    else {
      return
    }
    pendingRefetchIntents.append(intent)
  }

  func consumeRefetchIntent(_ intent: NotificationResourceRefetchIntent) {
    pendingRefetchIntents.removeAll { $0 == intent }
  }

  func discardPendingRefetchIntents() {
    pendingRefetchIntents.removeAll()
  }

  private func refreshRegistration() {
    guard authenticatedSessionIsActive else { return }
    if registrationTask != nil {
      registrationRefreshPending = true
      if state == .idle { state = .checkingPermission }
      return
    }

    sessionGeneration &+= 1
    let generation = sessionGeneration
    let remoteFailureSequence = remoteRegistrationFailureSequence
    registrationAttemptSequence &+= 1
    let attempt = registrationAttemptSequence
    authenticationRequired = false
    state = .checkingPermission

    let permissions = permissions
    let installationIDs = installationIDs
    let service = service
    let previousFID = registeredInstallationID

    currentRegistrationAttempt = attempt
    registrationTask = Task { @MainActor [weak self] in
      var attemptedFID: NotificationInstallationID?
      var registrationRequestWasIssued = false

      do {
        var permission = await permissions.currentStatus()
        try Task.checkCancellation()
        if permission == .notDetermined {
          permission = try await permissions.requestAuthorization()
          try Task.checkCancellation()
        }

        guard let self, self.sessionGeneration == generation else { return }
        guard permission.permitsRegistration else {
          self.state = .permissionDenied
          self.registrationRefreshPending = false
          self.finishRegistrationAttempt(generation: generation, attempt: attempt)
          return
        }

        try await installationIDs.prepareRegistration()
        try Task.checkCancellation()
        let rawValue = try await installationIDs.currentInstallationID()
        let fid = try NotificationInstallationID(rawValue)
        try Task.checkCancellation()
        guard self.sessionGeneration == generation else { return }
        guard self.remoteRegistrationFailureSequence == remoteFailureSequence else {
          self.state = .unavailable
          self.finishRegistrationAttempt(generation: generation, attempt: attempt)
          return
        }
        self.registrationCandidate = fid
        self.state = .registering

        attemptedFID = fid
        registrationRequestWasIssued = true
        try await service.registerNotificationFID(fid)
        guard
          !Task.isCancelled,
          self.sessionGeneration == generation,
          self.authenticatedSessionIsActive
        else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: fid,
            registrationRequestWasIssued: true,
            service: service
          )
          return
        }

        // Register first so a cleanup failure never creates a notification coverage gap.
        if let previousFID, previousFID != fid {
          try? await service.unregisterNotificationFID(previousFID)
        }

        guard
          self.sessionGeneration == generation,
          self.authenticatedSessionIsActive
        else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: fid,
            registrationRequestWasIssued: true,
            service: service
          )
          return
        }
        guard self.remoteRegistrationFailureSequence == remoteFailureSequence else {
          self.registrationCandidate = nil
          self.state = .unavailable
          self.finishRegistrationAttempt(generation: generation, attempt: attempt)
          return
        }
        self.registeredInstallationID = fid
        self.registrationCandidate = nil
        self.state = .registered
        self.finishRegistrationAttempt(generation: generation, attempt: attempt)
      } catch is CancellationError {
        guard let self else { return }
        if self.sessionGeneration == generation {
          self.finishRegistrationAttempt(generation: generation, attempt: attempt)
        } else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: attemptedFID,
            registrationRequestWasIssued: registrationRequestWasIssued,
            service: service
          )
        }
      } catch WoorisaiAPIError.credentialMissing,
        WoorisaiAPIError.credentialRejected
      {
        guard let self else { return }
        guard self.sessionGeneration == generation else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: attemptedFID,
            registrationRequestWasIssued: registrationRequestWasIssued,
            service: service
          )
          return
        }
        self.authenticatedSessionIsActive = false
        self.registrationRefreshPending = false
        self.authenticationRequired = true
        self.state = .failed
        self.finishRegistrationAttempt(generation: generation, attempt: attempt)
      } catch WoorisaiAPIError.serviceUnavailable {
        guard let self else { return }
        guard self.sessionGeneration == generation else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: attemptedFID,
            registrationRequestWasIssued: registrationRequestWasIssued,
            service: service
          )
          return
        }
        self.state = .unavailable
        self.finishRegistrationAttempt(generation: generation, attempt: attempt)
      } catch is NotificationProviderUnavailableError {
        guard let self else { return }
        guard self.sessionGeneration == generation else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: attemptedFID,
            registrationRequestWasIssued: registrationRequestWasIssued,
            service: service
          )
          return
        }
        self.state = .unavailable
        self.finishRegistrationAttempt(generation: generation, attempt: attempt)
      } catch {
        guard let self else { return }
        guard self.sessionGeneration == generation else {
          await self.finishOutdatedRegistrationAttempt(
            generation: generation,
            attempt: attempt,
            possiblyCommittedFID: attemptedFID,
            registrationRequestWasIssued: registrationRequestWasIssued,
            service: service
          )
          return
        }
        self.state = .failed
        self.finishRegistrationAttempt(generation: generation, attempt: attempt)
      }
    }
  }

  private func finishRegistrationAttempt(generation: UInt, attempt: UInt) {
    guard sessionGeneration == generation, currentRegistrationAttempt == attempt else { return }
    registrationTask = nil
    currentRegistrationAttempt = nil
    guard authenticatedSessionIsActive, registrationRefreshPending else { return }
    registrationRefreshPending = false
    refreshRegistration()
  }

  private func finishOutdatedRegistrationAttempt(
    generation: UInt,
    attempt: UInt,
    possiblyCommittedFID: NotificationInstallationID?,
    registrationRequestWasIssued: Bool,
    service: any NotificationFIDServing
  ) async {
    guard sessionGeneration != generation else { return }
    if registrationRequestWasIssued, let possiblyCommittedFID {
      // An unstructured detached task does not inherit cancellation from the register transport.
      // Await it before reasserting a newer session so a late DELETE cannot erase that upsert.
      let compensation = Task.detached {
        try? await service.unregisterNotificationFID(possiblyCommittedFID)
      }
      await compensation.value
    }

    if currentRegistrationAttempt == attempt {
      registrationTask = nil
      currentRegistrationAttempt = nil
    }
    guard authenticatedSessionIsActive else { return }
    if registrationTask != nil {
      registrationRefreshPending = true
    } else {
      registrationRefreshPending = false
      // Reassert the current session after a detached old register settles. The backend FID
      // upsert is unique, so this guarantees the newest authenticated participant wins.
      refreshRegistration()
    }
  }

  private func appendUnique(
    _ fid: NotificationInstallationID?,
    to candidates: inout [NotificationInstallationID]
  ) {
    guard let fid, !candidates.contains(fid) else { return }
    candidates.append(fid)
  }

  private func currentInstallationID(timeout: Duration) async -> String? {
    let installationIDs = installationIDs
    return await valueBeforeDeadline(timeout: timeout, timeoutValue: nil) {
      try? await installationIDs.currentInstallationID()
    }
  }

  private func unregister(
    _ fids: [NotificationInstallationID],
    timeout: Duration
  ) async {
    guard !fids.isEmpty else { return }
    let service = service
    _ = await valueBeforeDeadline(timeout: timeout, timeoutValue: false) {
      await withTaskGroup(of: Void.self) { group in
        for fid in fids {
          group.addTask {
            try? await service.unregisterNotificationFID(fid)
          }
        }
      }
      return true
    }
  }

  private func valueBeforeDeadline<Value: Sendable>(
    timeout: Duration,
    timeoutValue: Value,
    operation: @escaping @Sendable () async -> Value
  ) async -> Value {
    guard timeout > .zero else { return timeoutValue }
    return await withCheckedContinuation { continuation in
      let gate = NotificationDeadlineGate(continuation)
      let operationTask = Task {
        let value = await operation()
        await gate.resolve(value)
      }
      Task {
        try? await Task.sleep(for: timeout)
        guard !Task.isCancelled else { return }
        if await gate.resolve(timeoutValue) {
          operationTask.cancel()
        }
      }
    }
  }

  private func remaining(
    until deadline: ContinuousClock.Instant,
    clock: ContinuousClock
  ) -> Duration {
    max(.zero, clock.now.duration(to: deadline))
  }
}
