import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct NotificationModelTests {
  private let fid = "c123456789012345678901"

  @Test
  func authorizedSessionRegistersCurrentInstallation() async throws {
    let permissions = NotificationPermissionStub(status: .notDetermined, requested: .authorized)
    let provider = NotificationInstallationIDStub(values: [.success(fid)])
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: permissions,
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()

    await notificationExpectEventually { model.state == .registered }
    #expect(await permissions.requestCount == 1)
    #expect(await provider.requestCount == 1)
    #expect(await service.registeredRawValues == [fid])
    #expect(await service.unregisteredRawValues.isEmpty)
  }

  @Test
  func deniedPermissionKeepsCoreAppAvailableWithoutFetchingFID() async {
    let permissions = NotificationPermissionStub(status: .denied)
    let provider = NotificationInstallationIDStub(values: [.success(fid)])
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: permissions,
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()

    await notificationExpectEventually { model.state == .permissionDenied }
    #expect(await permissions.requestCount == 0)
    #expect(await provider.requestCount == 0)
    #expect(await service.registeredRawValues.isEmpty)
  }

  @Test
  func foregroundReconcilesPermissionGrantedInSettings() async {
    let permissions = NotificationPermissionStub(status: .denied)
    let provider = NotificationInstallationIDStub(values: [.success(fid)])
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: permissions,
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .permissionDenied }

    await permissions.setCurrentStatus(.authorized)
    model.applicationDidBecomeActive()

    await notificationExpectEventually { model.state == .registered }
    #expect(await permissions.requestCount == 0)
    #expect(await provider.requestCount == 1)
    #expect(await service.registeredRawValues == [fid])
  }

  @Test
  func foregroundDetectsPermissionRevokedAfterRegistrationWithoutReregistering() async {
    let permissions = NotificationPermissionStub(status: .authorized)
    let provider = NotificationInstallationIDStub(values: [.success(fid)])
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: permissions,
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }

    await permissions.setCurrentStatus(.denied)
    model.applicationDidBecomeActive()

    await notificationExpectEventually { model.state == .permissionDenied }
    #expect(await provider.requestCount == 1)
    #expect(await service.registeredRawValues == [fid])
  }

  @Test
  func malformedProviderFIDNeverReachesAuthenticatedAPI() async {
    let provider = NotificationInstallationIDStub(values: [.success("not-a-fid")])
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()

    await notificationExpectEventually { model.state == .failed }
    #expect(await service.registeredRawValues.isEmpty)
  }

  @Test
  func unavailableFirebaseConfigurationIsRecoverable() async {
    let provider = NotificationInstallationIDStub(
      values: [.failure(NotificationProviderUnavailableError.firebaseConfigurationMissing)]
    )
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: NotificationFIDServiceStub()
    )

    model.authenticatedSessionDidStart()

    await notificationExpectEventually { model.state == .unavailable }
    #expect(!model.authenticationRequired)
  }

  @Test
  func lateAPNsProviderCallbackRetriesFailedPreparationAndCoalescesDuplicates() async {
    let provider = PreparingNotificationInstallationIDStub(
      preparationResults: [
        .failure(NotificationProviderUnavailableError.remoteRegistrationUnavailable),
        .success(()),
      ],
      values: [.success(fid)]
    )
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )
    let coordinator = FirebasePushLifecycleCoordinator(notificationModel: model)

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .unavailable }

    coordinator.receiveProviderRegistration(installationID: fid)
    await notificationExpectEventually { model.state == .registered }
    coordinator.receiveProviderRegistration(installationID: fid)
    await Task.yield()

    #expect(await provider.prepareCount == 2)
    #expect(await provider.requestCount == 1)
    #expect(await service.registeredRawValues == [fid])
  }

  @Test
  func sameFIDSuccessRecoversAPNsFailureWithoutStartingARegistrationLoop() async {
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(fid)]
    )
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )
    let coordinator = FirebasePushLifecycleCoordinator(notificationModel: model)

    // Seed the coordinator before authentication so the recovery callback below is the same FID,
    // not a rotation.
    coordinator.receiveProviderRegistration(installationID: fid)
    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }

    coordinator.didFailToRegisterForRemoteNotifications()
    #expect(model.state == .unavailable)
    #expect(model.canRetryRegistration)

    coordinator.receiveProviderRegistration(installationID: fid)
    await notificationExpectEventually { model.state == .registered }
    coordinator.receiveProviderRegistration(installationID: fid)
    await Task.yield()

    #expect(await provider.requestCount == 2)
    #expect(await service.registeredRawValues == [fid, fid])
  }

  @Test
  func apnsFailureInvalidatesAnInFlightRegistrationUntilAProviderSuccessRetries() async {
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(fid)]
    )
    let service = SuspendedNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasSuspendedRegistration }

    model.remoteNotificationRegistrationDidFail()
    #expect(model.state == .unavailable)
    model.remoteNotificationRegistrationDidSucceed()
    await service.resumeFirstRegistration()

    await notificationExpectEventually {
      await service.registeredRawValues == [self.fid, self.fid]
        && model.state == .registered
    }
    #expect(await provider.requestCount == 2)
    #expect(await service.maximumConcurrentRegistrations == 1)
  }

  @Test
  func transientRegistrationFailureCanRetryWithoutStartingDuplicateWork() async {
    let provider = NotificationInstallationIDStub(values: [.success(fid), .success(fid)])
    let service = RecoveringNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .unavailable }
    #expect(model.canRetryRegistration)

    model.retryRegistration()
    model.retryRegistration()
    await notificationExpectEventually { model.state == .registered }

    #expect(!model.canRetryRegistration)
    #expect(await provider.requestCount == 2)
    #expect(await service.registerCount == 2)
  }

  @Test
  func rotationRegistersNewFIDBeforeBestEffortOldCleanup() async {
    let secondFID = "d123456789012345678901"
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(secondFID)]
    )
    let service = NotificationFIDServiceStub(unregisterFailures: [fid])
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }
    model.installationIDDidChange()

    await notificationExpectEventually {
      await service.registeredRawValues == [self.fid, secondFID]
        && model.state == .registered
    }
    #expect(await service.unregisteredRawValues == [fid])
  }

  @Test
  func providerRegistrationCallbackReconcilesTheFirstFIDAndThenOnlyRotations() async {
    let secondFID = "d123456789012345678901"
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(fid), .success(secondFID)]
    )
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )
    let coordinator = FirebasePushLifecycleCoordinator(notificationModel: model)

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }

    coordinator.receiveProviderRegistration(installationID: fid)
    await notificationExpectEventually { await provider.requestCount == 2 }
    coordinator.receiveProviderRegistration(installationID: fid)
    await Task.yield()
    #expect(await provider.requestCount == 2)

    coordinator.receiveProviderRegistration(installationID: secondFID)
    await notificationExpectEventually { await provider.requestCount == 3 }
    #expect(await service.registeredRawValues == [fid, fid, secondFID])
  }

  @Test
  func signOutUnregisterIsBestEffortAndAlwaysClearsLocalRegistrationState() async {
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(fid)]
    )
    let service = NotificationFIDServiceStub(unregisterFailures: [fid])
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )
    let coordinator = FirebasePushLifecycleCoordinator(notificationModel: model)
    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }

    await model.unregisterBeforeSignOut()

    #expect(model.state == .idle)
    #expect(!model.authenticationRequired)
    #expect(await service.unregisteredRawValues == [fid])

    coordinator.receiveProviderRegistration(installationID: fid)
    await Task.yield()

    #expect(await provider.requestCount == 2)
    #expect(await service.registeredRawValues == [fid])
  }

  @Test
  func signOutUnregisterHasAnAppLevelDeadline() async {
    let provider = NeverReturningNotificationInstallationIDStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .denied),
      installationIDs: provider,
      service: NotificationFIDServiceStub()
    )

    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      await model.unregisterBeforeSignOut(timeout: .milliseconds(20))
    }

    #expect(elapsed < .seconds(1))
    #expect(model.state == .idle)
  }

  @Test
  func signOutAttemptsKnownFIDBeforeAStalledCurrentLookup() async {
    let provider = InitialThenNeverNotificationInstallationIDStub(initial: fid)
    let service = NotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )
    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registered }

    await model.unregisterBeforeSignOut(timeout: .milliseconds(20))

    #expect(await service.unregisteredRawValues == [fid])
    #expect(model.state == .idle)
  }

  @Test
  func signOutWaitsForInFlightRegisterThenUnregistersTheCommittedFID() async {
    let provider = NotificationInstallationIDStub(values: [.success(fid), .success(fid)])
    let service = SuspendedNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasSuspendedRegistration }

    let signOutTask = Task { @MainActor in
      await model.unregisterBeforeSignOut(timeout: .seconds(1))
    }
    await Task.yield()
    #expect(await service.unregisteredRawValues.isEmpty)

    await service.resumeFirstRegistration()
    await signOutTask.value

    #expect(
      await service.events
        == ["register-start", "register-commit", "unregister", "unregister"]
    )
    #expect(model.state == .idle)
  }

  @Test
  func rotationQueuesBehindInFlightRegisterAndCleansUpThePreviousFIDLast() async {
    let secondFID = "d123456789012345678901"
    let provider = NotificationInstallationIDStub(values: [.success(fid), .success(secondFID)])
    let service = SuspendedNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasSuspendedRegistration }
    model.installationIDDidChange()
    model.installationIDDidChange()

    #expect(await provider.requestCount == 1)
    #expect(await service.maximumConcurrentRegistrations == 1)

    await service.resumeFirstRegistration()
    await notificationExpectEventually {
      let registered = await service.registeredRawValues
      let unregistered = await service.unregisteredRawValues
      return registered == [self.fid, secondFID]
        && unregistered == [self.fid]
        && model.state == .registered
    }

    #expect(await service.maximumConcurrentRegistrations == 1)
    #expect(
      await service.events == [
        "register-start", "register-commit", "register-start", "register-commit", "unregister",
      ]
    )
  }

  @Test
  func signOutDeadlineStillWinsWhenInFlightRegisterNeverSettles() async {
    let service = NeverReturningRegistrationNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: NotificationInstallationIDStub(
        values: [.success(fid), .success(fid), .success(fid)]
      ),
      service: service
    )
    model.authenticatedSessionDidStart()
    await notificationExpectEventually { model.state == .registering }

    let clock = ContinuousClock()
    let elapsed = await clock.measure {
      await model.unregisterBeforeSignOut(timeout: .milliseconds(20))
    }

    #expect(elapsed < .seconds(1))
    #expect(await service.unregisteredRawValues == [fid])
    #expect(model.state == .idle)

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.registerCount == 2 }
  }

  @Test
  func lateOldRegisterCannotWinOverTheNextAuthenticatedSession() async {
    let provider = NotificationInstallationIDStub(
      values: [.success(fid), .success(fid), .success(fid), .success(fid)]
    )
    let service = SuspendedNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasSuspendedRegistration }
    await model.unregisterBeforeSignOut(timeout: .milliseconds(20))

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.registeredRawValues.count == 1 }

    await service.resumeFirstRegistration()
    await notificationExpectEventually {
      await service.registeredRawValues.count == 3 && model.state == .registered
    }

    let events = await service.events
    #expect(
      Array(events.suffix(4))
        == ["register-commit", "unregister", "register-start", "register-commit"]
    )
    #expect(await service.maximumConcurrentRegistrations == 2)
  }

  @Test
  func registerCommittingAfterCandidateDeleteGetsACompensatingDeleteBeforeSignOutEnds() async {
    let provider = InitialThenNeverNotificationInstallationIDStub(initial: fid)
    let service = SuspendedNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasSuspendedRegistration }
    let signOutTask = Task { @MainActor in
      await model.unregisterBeforeSignOut(timeout: .milliseconds(100))
    }
    try? await Task.sleep(for: .milliseconds(60))
    #expect(await service.unregisteredRawValues.count == 1)

    await service.resumeFirstRegistration()
    await notificationExpectEventually { await service.unregisteredRawValues.count == 2 }
    await signOutTask.value

    #expect(model.state == .idle)
  }

  @Test
  func cancelledRegisterThatCommittedUsesAnUncancelledCompensatingDelete() async {
    let provider = NotificationInstallationIDStub(values: [.success(fid), .success(fid)])
    let service = CancellationCommittingNotificationFIDServiceStub()
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: provider,
      service: service
    )

    model.authenticatedSessionDidStart()
    await notificationExpectEventually { await service.hasStartedRegistration }

    await model.unregisterBeforeSignOut(timeout: .seconds(1))

    #expect(
      await service.events
        == [
          "register-start", "register-commit-after-cancel", "unregister-compensation",
          "unregister-signout",
        ]
    )
    #expect(await service.unregisterTaskCancellationStates == [false, false])
    #expect(model.state == .idle)
  }

  @Test
  func authenticationFailureIsSurfacedWithoutLeakingFIDIntoState() async {
    let service = NotificationFIDServiceStub(registerFailure: .credentialRejected)
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .authorized),
      installationIDs: NotificationInstallationIDStub(values: [.success(fid)]),
      service: service
    )

    model.authenticatedSessionDidStart()

    await notificationExpectEventually { model.authenticationRequired }
    #expect(model.state == .failed)
  }

  @Test
  func routesOnlyKnownPrivacySafePayloadFieldsToPositiveResourceRefetches() {
    #expect(
      NotificationPayloadRouter.refetchIntent(
        eventType: "relationshipScoreChanged",
        resourceID: "101"
      ) == .scoreChange(id: 101)
    )
    #expect(
      NotificationPayloadRouter.refetchIntent(
        eventType: "scoreChangeCommentCreated",
        resourceID: "101"
      ) == .scoreChange(id: 101)
    )
    #expect(
      NotificationPayloadRouter.refetchIntent(
        eventType: "diaryEntryCommentCreated",
        resourceID: "202"
      ) == .diaryEntry(id: 202)
    )
    #expect(
      NotificationPayloadRouter.refetchIntent(eventType: "unknown", resourceID: "101") == nil
    )
    #expect(
      NotificationPayloadRouter.refetchIntent(
        eventType: "relationshipScoreChanged",
        resourceID: "0"
      ) == nil
    )
    #expect(
      NotificationPayloadRouter.refetchIntent(
        eventType: "relationshipScoreChanged",
        resourceID: " private body "
      ) == nil
    )
  }

  @Test
  func sameVisiblePushRefetchesInsteadOfDependingOnNavigationTaskRestart() {
    #expect(
      NotificationNavigationDisposition.resolve(currentPath: [101], targetID: 101)
        == .refetchVisible
    )
    #expect(
      NotificationNavigationDisposition.resolve(currentPath: [], targetID: 101) == .navigate
    )
    #expect(
      NotificationNavigationDisposition.resolve(currentPath: [202], targetID: 101) == .navigate
    )
  }

  @Test
  func duplicateNotificationsCoalesceIntoOneRefetchIntent() {
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .denied),
      installationIDs: NotificationInstallationIDStub(values: []),
      service: NotificationFIDServiceStub()
    )

    model.receiveNotification(eventType: "relationshipScoreChanged", resourceID: "101")
    model.receiveNotification(eventType: "scoreChangeCommentCreated", resourceID: "101")
    model.receiveNotification(eventType: "relationshipScoreChanged", resourceID: "101")

    #expect(model.pendingRefetchIntents == [.scoreChange(id: 101)])

    model.consumeRefetchIntent(.scoreChange(id: 101))
    #expect(model.pendingRefetchIntents.isEmpty)

    model.receiveNotification(eventType: "diaryEntryCommentCreated", resourceID: "202")
    model.discardPendingRefetchIntents()
    #expect(model.pendingRefetchIntents.isEmpty)
  }

  @Test
  func launchNotificationIsBufferedUntilTheFeatureModelAttaches() {
    let model = NotificationModel(
      permissions: NotificationPermissionStub(status: .denied),
      installationIDs: NotificationInstallationIDStub(values: []),
      service: NotificationFIDServiceStub()
    )
    let coordinator = FirebasePushLifecycleCoordinator()

    coordinator.receiveNotification(
      eventType: "diaryEntryCommentCreated",
      resourceID: "202"
    )
    #expect(model.pendingRefetchIntents.isEmpty)

    coordinator.attach(notificationModel: model)

    #expect(model.pendingRefetchIntents == [.diaryEntry(id: 202)])
  }
}

private actor NotificationPermissionStub: NotificationPermissionAuthorizing {
  private var status: NotificationPermissionStatus
  private let requested: NotificationPermissionStatus
  private(set) var requestCount = 0

  init(
    status: NotificationPermissionStatus,
    requested: NotificationPermissionStatus? = nil
  ) {
    self.status = status
    self.requested = requested ?? status
  }

  func currentStatus() async -> NotificationPermissionStatus {
    status
  }

  func requestAuthorization() async throws -> NotificationPermissionStatus {
    requestCount += 1
    return requested
  }

  func setCurrentStatus(_ status: NotificationPermissionStatus) {
    self.status = status
  }
}

private actor NotificationInstallationIDStub: NotificationInstallationIDProviding {
  private var values: [Result<String, any Error>]
  private(set) var requestCount = 0

  init(values: [Result<String, any Error>]) {
    self.values = values
  }

  func currentInstallationID() async throws -> String {
    requestCount += 1
    guard !values.isEmpty else { throw NotificationModelTestFailure.unexpectedProviderCall }
    return try values.removeFirst().get()
  }
}

private actor PreparingNotificationInstallationIDStub: NotificationInstallationIDProviding {
  private var preparationResults: [Result<Void, any Error>]
  private var values: [Result<String, any Error>]
  private(set) var prepareCount = 0
  private(set) var requestCount = 0

  init(
    preparationResults: [Result<Void, any Error>],
    values: [Result<String, any Error>]
  ) {
    self.preparationResults = preparationResults
    self.values = values
  }

  func prepareRegistration() async throws {
    prepareCount += 1
    guard !preparationResults.isEmpty else {
      throw NotificationModelTestFailure.unexpectedProviderCall
    }
    try preparationResults.removeFirst().get()
  }

  func currentInstallationID() async throws -> String {
    requestCount += 1
    guard !values.isEmpty else { throw NotificationModelTestFailure.unexpectedProviderCall }
    return try values.removeFirst().get()
  }
}

private actor NeverReturningNotificationInstallationIDStub: NotificationInstallationIDProviding {
  func currentInstallationID() async throws -> String {
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    return "c123456789012345678901"
  }
}

private actor InitialThenNeverNotificationInstallationIDStub:
  NotificationInstallationIDProviding
{
  private let initial: String
  private var returnedInitial = false

  init(initial: String) {
    self.initial = initial
  }

  func currentInstallationID() async throws -> String {
    if !returnedInitial {
      returnedInitial = true
      return initial
    }
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
    return initial
  }
}

private actor NotificationFIDServiceStub: NotificationFIDServing {
  private(set) var registeredRawValues: [String] = []
  private(set) var unregisteredRawValues: [String] = []
  private let registerFailure: WoorisaiAPIError?
  private let unregisterFailures: Set<String>

  init(
    registerFailure: WoorisaiAPIError? = nil,
    unregisterFailures: Set<String> = []
  ) {
    self.registerFailure = registerFailure
    self.unregisterFailures = unregisterFailures
  }

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    registeredRawValues.append(fid.rawValue)
    if let registerFailure { throw registerFailure }
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    unregisteredRawValues.append(fid.rawValue)
    if unregisterFailures.contains(fid.rawValue) {
      throw WoorisaiAPIError.serviceUnavailable
    }
  }
}

private actor RecoveringNotificationFIDServiceStub: NotificationFIDServing {
  private(set) var registerCount = 0

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    registerCount += 1
    if registerCount == 1 { throw WoorisaiAPIError.serviceUnavailable }
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {}
}

private actor SuspendedNotificationFIDServiceStub: NotificationFIDServing {
  private(set) var registeredRawValues: [String] = []
  private(set) var unregisteredRawValues: [String] = []
  private(set) var events: [String] = []
  private(set) var maximumConcurrentRegistrations = 0
  private var concurrentRegistrations = 0
  private var shouldSuspendNextRegistration = true
  private var firstRegistrationContinuation: CheckedContinuation<Void, Never>?

  var hasSuspendedRegistration: Bool {
    firstRegistrationContinuation != nil
  }

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    concurrentRegistrations += 1
    maximumConcurrentRegistrations = max(maximumConcurrentRegistrations, concurrentRegistrations)
    events.append("register-start")
    if shouldSuspendNextRegistration {
      shouldSuspendNextRegistration = false
      await withCheckedContinuation { continuation in
        firstRegistrationContinuation = continuation
      }
    }
    registeredRawValues.append(fid.rawValue)
    events.append("register-commit")
    concurrentRegistrations -= 1
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    unregisteredRawValues.append(fid.rawValue)
    events.append("unregister")
  }

  func resumeFirstRegistration() {
    firstRegistrationContinuation?.resume()
    firstRegistrationContinuation = nil
  }
}

private actor CancellationCommittingNotificationFIDServiceStub: NotificationFIDServing {
  private(set) var events: [String] = []
  private(set) var unregisterTaskCancellationStates: [Bool] = []
  private var unregisterCount = 0

  var hasStartedRegistration: Bool {
    events.contains("register-start")
  }

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    events.append("register-start")
    do {
      try await Task.sleep(for: .seconds(10))
      Issue.record("Registration unexpectedly completed without cancellation")
    } catch is CancellationError {
      // Simulate a server commit whose transport response is observed as cancellation.
      events.append("register-commit-after-cancel")
      throw CancellationError()
    }
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    unregisterCount += 1
    unregisterTaskCancellationStates.append(Task.isCancelled)
    events.append(unregisterCount == 1 ? "unregister-compensation" : "unregister-signout")
  }
}

private actor NeverReturningRegistrationNotificationFIDServiceStub: NotificationFIDServing {
  private(set) var unregisteredRawValues: [String] = []
  private(set) var registerCount = 0

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    registerCount += 1
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    unregisteredRawValues.append(fid.rawValue)
  }
}

private enum NotificationModelTestFailure: Error {
  case unexpectedProviderCall
}

@MainActor
private func notificationExpectEventually(
  attempts: Int = 200,
  condition: @escaping @MainActor () async -> Bool
) async {
  for _ in 0..<attempts {
    if await condition() { return }
    await Task.yield()
  }
  Issue.record("Condition did not become true")
}
