import Foundation
import UIKit
import UserNotifications
import WoorisaiAPI

#if canImport(FirebaseCore) && canImport(FirebaseInstallations) && canImport(FirebaseMessaging)
  @preconcurrency import FirebaseCore
  @preconcurrency import FirebaseInstallations
  @preconcurrency import FirebaseMessaging
#endif

enum NotificationProviderUnavailableError: Error, Equatable, Sendable {
  case firebaseSDKUnavailable
  case firebaseConfigurationMissing
  case installationIDUnavailable
  case remoteRegistrationUnavailable
}

final class SystemNotificationPermissionAuthorizer: NotificationPermissionAuthorizing,
  @unchecked Sendable
{
  private let center: UNUserNotificationCenter

  init(center: UNUserNotificationCenter = .current()) {
    self.center = center
  }

  func currentStatus() async -> NotificationPermissionStatus {
    let settings = await center.notificationSettings()
    return Self.map(settings.authorizationStatus)
  }

  func requestAuthorization() async throws -> NotificationPermissionStatus {
    _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
    return await currentStatus()
  }

  private static func map(
    _ status: UNAuthorizationStatus
  ) -> NotificationPermissionStatus {
    switch status {
    case .notDetermined:
      .notDetermined
    case .denied:
      .denied
    case .authorized:
      .authorized
    case .provisional:
      .provisional
    case .ephemeral:
      .ephemeral
    @unknown default:
      .denied
    }
  }
}

final class FirebaseNotificationInstallationIDProvider: NotificationInstallationIDProviding,
  @unchecked Sendable
{
  func prepareRegistration() async throws {
    #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
      guard FirebaseApp.app() != nil else {
        throw NotificationProviderUnavailableError.firebaseConfigurationMissing
      }
      // This call is idempotent. Reasserting it here gives an explicit retry path after a
      // privacy-safe UIApplicationDelegate failure and lets a late APNs token drive the Firebase
      // registration callback below.
      await MainActor.run {
        UIApplication.shared.registerForRemoteNotifications()
      }
      try await withCheckedThrowingContinuation { continuation in
        Messaging.messaging().register { error in
          if error == nil {
            continuation.resume()
          } else {
            continuation.resume(
              throwing: NotificationProviderUnavailableError.remoteRegistrationUnavailable
            )
          }
        }
      }
    #else
      throw NotificationProviderUnavailableError.firebaseSDKUnavailable
    #endif
  }

  func currentInstallationID() async throws -> String {
    #if canImport(FirebaseCore) && canImport(FirebaseInstallations)
      guard FirebaseApp.app() != nil else {
        throw NotificationProviderUnavailableError.firebaseConfigurationMissing
      }
      do {
        let rawValue = try await Installations.installations().installationID()
        _ = try NotificationInstallationID(rawValue)
        return rawValue
      } catch {
        throw NotificationProviderUnavailableError.installationIDUnavailable
      }
    #else
      throw NotificationProviderUnavailableError.firebaseSDKUnavailable
    #endif
  }
}

@MainActor
final class FirebasePushLifecycleCoordinator: NSObject {
  enum Availability: Equatable, Sendable {
    case notConfigured
    case configured
    case configurationMissing
    case sdkUnavailable
  }

  enum RemoteRegistrationState: Equatable, Sendable {
    case idle
    case registering
    case ready
    case failed
  }

  private(set) var availability: Availability = .notConfigured
  private(set) var remoteRegistrationState: RemoteRegistrationState = .idle
  private weak var notificationModel: NotificationModel?
  private var pendingRefetchIntents: [NotificationResourceRefetchIntent] = []
  private var lastObservedInstallationID: NotificationInstallationID?
  private var providerReconciliationPending = false

  init(notificationModel: NotificationModel? = nil) {
    self.notificationModel = notificationModel
  }

  func attach(notificationModel: NotificationModel) {
    self.notificationModel = notificationModel
    if providerReconciliationPending {
      providerReconciliationPending = false
      notificationModel.installationIDDidChange()
    }
    for intent in pendingRefetchIntents {
      switch intent {
      case .scoreChange(let id):
        notificationModel.receiveNotification(
          eventType: "relationshipScoreChanged",
          resourceID: String(id)
        )
      case .diaryEntry(let id):
        notificationModel.receiveNotification(
          eventType: "diaryEntryCommentCreated",
          resourceID: String(id)
        )
      }
    }
    pendingRefetchIntents.removeAll()
  }

  /// Safe for `application(_:didFinishLaunchingWithOptions:)`: a missing plist is reported as an
  /// unavailable provider instead of asking Firebase to configure and terminating the process.
  @discardableResult
  func configureIfAvailable(bundle: Bundle = .main) -> Availability {
    #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
      if FirebaseApp.app() == nil {
        guard
          let configurationURL = bundle.url(
            forResource: "GoogleService-Info",
            withExtension: "plist"
          ), let options = FirebaseOptions(contentsOfFile: configurationURL.path)
        else {
          availability = .configurationMissing
          return availability
        }
        FirebaseApp.configure(options: options)
      }

      guard FirebaseApp.app() != nil else {
        availability = .configurationMissing
        return availability
      }
      Messaging.messaging().delegate = self
      availability = .configured
      return availability
    #else
      availability = .sdkUnavailable
      return availability
    #endif
  }

  func registerForRemoteNotifications(using application: UIApplication) {
    guard availability == .configured else { return }
    application.registerForRemoteNotifications()
  }

  func applicationDidBecomeActive(using application: UIApplication) {
    guard availability == .configured else { return }
    // Returning from Settings is the only reliable signal that a previously denied permission may
    // now be authorized. Reassert APNs registration and let the feature model read current status.
    application.registerForRemoteNotifications()
    notificationModel?.applicationDidBecomeActive()
  }

  func didRegisterForRemoteNotifications(deviceToken: Data) {
    #if canImport(FirebaseMessaging)
      guard availability == .configured else { return }
      remoteRegistrationState = .registering
      Messaging.messaging().apnsToken = deviceToken
      Messaging.messaging().register { [weak self] error in
        let succeeded = error == nil
        Task { @MainActor [weak self] in
          guard let self else { return }
          if succeeded {
            self.remoteRegistrationState = .ready
          } else {
            self.didFailToRegisterForRemoteNotifications()
          }
        }
      }
    #endif
  }

  func didFailToRegisterForRemoteNotifications() {
    remoteRegistrationState = .failed
    notificationModel?.remoteNotificationRegistrationDidFail()
  }

  func receiveProviderRegistration(installationID rawValue: String?) {
    guard let rawValue, let installationID = try? NotificationInstallationID(rawValue) else {
      return
    }
    let previous = lastObservedInstallationID
    lastObservedInstallationID = installationID
    remoteRegistrationState = .ready
    if previous == installationID {
      notificationModel?.remoteNotificationRegistrationDidSucceed()
    } else if let notificationModel {
      notificationModel.installationIDDidChange()
    } else {
      providerReconciliationPending = true
    }
  }

  /// AppDelegate/UNUserNotificationCenterDelegate can forward both foreground deliveries and taps
  /// here. Only the two routing strings are read; alert content is never retained.
  @discardableResult
  func receiveNotification(
    userInfo: [AnyHashable: Any]
  ) -> NotificationResourceRefetchIntent? {
    let eventType = userInfo["eventType"] as? String
    let resourceID = userInfo["resourceId"] as? String
    return receiveNotification(eventType: eventType, resourceID: resourceID)
  }

  /// Sendable delegate callbacks can extract these two strings before crossing to MainActor.
  @discardableResult
  func receiveNotification(
    eventType: String?,
    resourceID: String?
  ) -> NotificationResourceRefetchIntent? {
    let intent = NotificationPayloadRouter.refetchIntent(
      eventType: eventType,
      resourceID: resourceID
    )
    if let intent {
      if let notificationModel {
        notificationModel.receiveNotification(eventType: eventType, resourceID: resourceID)
      } else if !pendingRefetchIntents.contains(intent) {
        pendingRefetchIntents.append(intent)
      }
      return intent
    }
    return nil
  }
}

#if canImport(FirebaseMessaging)
  extension FirebasePushLifecycleCoordinator: MessagingDelegate {
    nonisolated func messaging(
      _ messaging: Messaging,
      didReceiveRegistration installationID: String?
    ) {
      // `Messaging.register()` invokes this delegate even when the FID did not change. Coalescing
      // in the coordinator prevents a register → callback → register feedback loop.
      Task { @MainActor [weak self] in
        self?.receiveProviderRegistration(installationID: installationID)
      }
    }
  }
#endif
