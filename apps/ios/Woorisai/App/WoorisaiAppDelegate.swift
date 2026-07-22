import UIKit
import UserNotifications

@MainActor
final class WoorisaiAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  let pushCoordinator = FirebasePushLifecycleCoordinator()
  private let snapshotPrivacyShield = AppSnapshotPrivacyShield()

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    try? ProtectedTemporaryMediaPreview.purgeStaleFiles()
    try? ProtectedTemporaryMediaUpload.purgeStaleFiles()
    UNUserNotificationCenter.current().delegate = self
    if pushCoordinator.configureIfAvailable() == .configured {
      pushCoordinator.registerForRemoteNotifications(using: application)
    }
    if let userInfo = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      pushCoordinator.receiveNotification(
        eventType: userInfo["eventType"] as? String,
        resourceID: userInfo["resourceId"] as? String
      )
    }
    return true
  }

  func applicationWillResignActive(_ application: UIApplication) {
    snapshotPrivacyShield.show(in: application.visiblePrivacyShieldWindows)
    AppPrivacyAccessibilityController.setContentHidden(true)
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    snapshotPrivacyShield.show(in: application.visiblePrivacyShieldWindows)
    AppPrivacyAccessibilityController.setContentHidden(true)
  }

  func applicationDidBecomeActive(_ application: UIApplication) {
    snapshotPrivacyShield.hide()
    AppPrivacyAccessibilityController.setContentHidden(false)
    pushCoordinator.applicationDidBecomeActive(using: application)
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    pushCoordinator.didRegisterForRemoteNotifications(deviceToken: deviceToken)
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    // Provider details can contain device/runtime metadata. Reduce the callback to a retryable,
    // privacy-safe availability state without logging or retaining the error.
    pushCoordinator.didFailToRegisterForRemoteNotifications()
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    // Foreground delivery may show a banner, but navigation is user-driven. Only the response
    // callback below turns a tapped notification into a refetch intent.
    return [.banner, .badge, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo
    let eventType = userInfo["eventType"] as? String
    let resourceID = userInfo["resourceId"] as? String
    _ = await MainActor.run {
      pushCoordinator.receiveNotification(
        eventType: eventType,
        resourceID: resourceID
      )
    }
  }
}

@MainActor
final class AppSnapshotPrivacyShield {
  static let accessibilityIdentifier = "privacy.snapshotCover"

  private var covers: [ObjectIdentifier: UIView] = [:]

  func show(in windows: [UIWindow]) {
    for window in windows {
      let windowID = ObjectIdentifier(window)
      let cover: UIView
      if let existingCover = covers[windowID] {
        cover = existingCover
      } else {
        cover = UIView(frame: window.bounds)
        cover.backgroundColor = .systemBackground
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.accessibilityIdentifier = Self.accessibilityIdentifier
        covers[windowID] = cover
        window.addSubview(cover)
      }
      cover.frame = window.bounds
      window.bringSubviewToFront(cover)
    }
  }

  func hide() {
    for cover in covers.values {
      cover.removeFromSuperview()
    }
    covers.removeAll()
  }

  func isCovering(_ window: UIWindow) -> Bool {
    covers[ObjectIdentifier(window)]?.superview === window
  }
}

extension UIApplication {
  fileprivate var visiblePrivacyShieldWindows: [UIWindow] {
    connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .filter { !$0.isHidden }
  }
}
