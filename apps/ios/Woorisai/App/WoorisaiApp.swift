import Foundation
import SwiftUI
import UIKit
import WoorisaiAPI

@main
struct WoorisaiApp: App {
  @UIApplicationDelegateAdaptor(WoorisaiAppDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var loginOptionsModel: LoginOptionsModel
  @State private var authenticationModel: AuthenticationModel
  @State private var relationshipModel: RelationshipModel
  @State private var diaryModel: DiaryModel
  @State private var notificationModel: NotificationModel
  @State private var hasPresentedActiveScene = false
  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaPreviewLoader: any PrivateMediaPreviewLoading
  #if DEBUG
    private let uiTestDynamicTypeSize: DynamicTypeSize?
  #endif

  @MainActor
  init() {
    let arguments = ProcessInfo.processInfo.arguments
    let services = AppDependencies.makeServices(arguments: arguments)
    _loginOptionsModel = State(
      initialValue: LoginOptionsModel(loader: services.loginOptionsLoader)
    )
    _authenticationModel = State(
      initialValue: AuthenticationModel(
        validator: services.credentialValidator,
        credentialStore: services.credentialStore,
        vault: services.credentialVault,
        biometricProbe: services.biometricProbe,
        restoresSession: services.shouldRestoreSession
      )
    )
    _relationshipModel = State(
      initialValue: RelationshipModel(service: services.relationshipService)
    )
    _diaryModel = State(
      initialValue: DiaryModel(service: services.diaryService)
    )
    _notificationModel = State(
      initialValue: NotificationModel(
        permissions: services.notificationPermissions,
        installationIDs: services.notificationInstallationIDs,
        service: services.notificationFIDService
      )
    )
    mediaService = services.mediaService
    mediaUploader = services.mediaUploader
    #if DEBUG
      if WoorisaiUITestService.isUITest(arguments: arguments) {
        mediaPreviewLoader = WoorisaiUITestMediaPreviewLoader(
          corruptsFirstVideoLoad: WoorisaiUITestService.corruptsFirstVideoLoad(
            arguments: arguments
          )
        )
      } else {
        mediaPreviewLoader = PrivateMediaPreviewStore(service: services.mediaService)
      }
    #else
      mediaPreviewLoader = PrivateMediaPreviewStore(service: services.mediaService)
    #endif
    #if DEBUG
      uiTestDynamicTypeSize = WoorisaiUITestService.dynamicTypeSize(arguments: arguments)
    #endif
  }

  var body: some Scene {
    WindowGroup {
      let rootView = AppRootView(
        loginOptionsModel: loginOptionsModel,
        authenticationModel: authenticationModel,
        relationshipModel: relationshipModel,
        diaryModel: diaryModel,
        notificationModel: notificationModel,
        mediaService: mediaService,
        mediaUploader: mediaUploader,
        mediaPreviewLoader: mediaPreviewLoader
      )
      .task {
        appDelegate.pushCoordinator.attach(notificationModel: notificationModel)
        appDelegate.attachPrivacyCoverPolicy(authenticationModel: authenticationModel)
      }
      .task {
        await authenticationModel.restoreLockedSessionIfAvailable()
      }
      let contentIsPrivate = !authenticationModel.isAwaitingBiometricUnlock
      let privacyProtectedRootView =
        rootView
        .background {
          AppPrivacyAccessibilityBridge(
            contentHidden: hasPresentedActiveScene
              && AppPrivacyCoverPolicy.shouldCover(scenePhase, contentIsPrivate: contentIsPrivate)
          )
          .frame(width: 0, height: 0)
          .accessibilityHidden(true)
        }
        .overlay {
          if hasPresentedActiveScene,
            AppPrivacyCoverPolicy.shouldCover(scenePhase, contentIsPrivate: contentIsPrivate)
          {
            AppPrivacyCoverView()
              .ignoresSafeArea()
          }
        }
        .animation(nil, value: scenePhase)
        .onChange(of: scenePhase, initial: true) { _, phase in
          if phase == .active {
            hasPresentedActiveScene = true
            AppPrivacyAccessibilityController.setContentHidden(false)
          } else if hasPresentedActiveScene && contentIsPrivate {
            AppPrivacyAccessibilityController.setContentHidden(true)
          } else {
            AppPrivacyAccessibilityController.setContentHidden(false)
          }
        }
      #if DEBUG
        if let uiTestDynamicTypeSize {
          privacyProtectedRootView.dynamicTypeSize(uiTestDynamicTypeSize)
        } else {
          privacyProtectedRootView
        }
      #else
        privacyProtectedRootView
      #endif
    }
  }
}

/// The single decision point for BOTH privacy covers — the SwiftUI overlay below and the UIKit
/// `AppSnapshotPrivacyShield` in `WoorisaiAppDelegate`. Content is covered only while the scene is
/// not active AND the visible content is actually private. The biometric lock flow is exempt: that
/// screen is itself the non-sensitive cover, and covering it blanks the app behind the Face ID
/// sheet (the system prompt drives the scene to `.inactive`/resign-active).
enum AppPrivacyCoverPolicy {
  static func shouldCover(_ scenePhase: ScenePhase, contentIsPrivate: Bool) -> Bool {
    guard contentIsPrivate else { return false }
    switch scenePhase {
    case .active:
      return false
    case .inactive, .background:
      return true
    @unknown default:
      return true
    }
  }
}

private struct AppPrivacyCoverView: UIViewRepresentable {
  func makeUIView(context: Context) -> AppPrivacyCoverUIView {
    AppPrivacyCoverUIView()
  }

  func updateUIView(_ uiView: AppPrivacyCoverUIView, context: Context) {}

  static func dismantleUIView(_ uiView: AppPrivacyCoverUIView, coordinator: ()) {
    uiView.isAccessibilityElement = false
  }
}

/// The shared branded privacy cover, used by both the SwiftUI overlay and the UIKit
/// `AppSnapshotPrivacyShield`. Brand background + lock mark so a cover triggered by everyday
/// `.inactive` events (제어 센터, 전화 수신, 권한 팝업) reads as a deliberate screen, not a
/// black/white glitch — never `.systemBackground` here.
final class AppPrivacyCoverUIView: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = WoorisaiPalette.creamUIColor
    isAccessibilityElement = false
    accessibilityElementsHidden = true

    let markConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
    let mark = UIImageView(
      image: UIImage(systemName: "lock.heart", withConfiguration: markConfiguration)
    )
    mark.tintColor = WoorisaiPalette.coralUIColor
    mark.isAccessibilityElement = false
    mark.translatesAutoresizingMaskIntoConstraints = false
    addSubview(mark)
    NSLayoutConstraint.activate([
      mark.centerXAnchor.constraint(equalTo: centerXAnchor),
      mark.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
enum AppPrivacyAccessibilityController {
  static func setContentHidden(_ isHidden: Bool) {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        window.accessibilityElementsHidden = isHidden
      }
    }
    UIAccessibility.post(notification: .screenChanged, argument: nil)
  }
}

private struct AppPrivacyAccessibilityBridge: UIViewRepresentable {
  let contentHidden: Bool

  func makeUIView(context: Context) -> AppPrivacyAccessibilityBridgeUIView {
    let view = AppPrivacyAccessibilityBridgeUIView()
    view.contentHidden = contentHidden
    return view
  }

  func updateUIView(_ uiView: AppPrivacyAccessibilityBridgeUIView, context: Context) {
    uiView.contentHidden = contentHidden
  }
}

private final class AppPrivacyAccessibilityBridgeUIView: UIView {
  var contentHidden = false {
    didSet {
      applyAccessibilityState()
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isAccessibilityElement = false
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    applyAccessibilityState()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func applyAccessibilityState() {
    window?.accessibilityElementsHidden = contentHidden
  }
}

private struct AppRootView: View {
  @State private var loginOptionsModel: LoginOptionsModel
  @State private var authenticationModel: AuthenticationModel
  @State private var relationshipModel: RelationshipModel
  @State private var diaryModel: DiaryModel
  @State private var notificationModel: NotificationModel
  @State private var selectedTab = AuthenticatedTab.relationship
  @State private var relationshipNavigationPath: [Int64] = []
  @State private var diaryNavigationPath: [Int64] = []
  @State private var isEndingSession = false
  @State private var hasInjectedUnknownOutcomeNotification = false
  @State private var topLevelMediaSession: TopLevelMediaSessionCoordinator
  #if DEBUG
    @State private var hasPreparedSyntheticMedia = false
  #endif
  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaPreviewLoader: any PrivateMediaPreviewLoading

  @MainActor
  init(
    loginOptionsModel: LoginOptionsModel,
    authenticationModel: AuthenticationModel,
    relationshipModel: RelationshipModel,
    diaryModel: DiaryModel,
    notificationModel: NotificationModel,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaPreviewLoader: any PrivateMediaPreviewLoading
  ) {
    _loginOptionsModel = State(initialValue: loginOptionsModel)
    _authenticationModel = State(initialValue: authenticationModel)
    _relationshipModel = State(initialValue: relationshipModel)
    _diaryModel = State(initialValue: diaryModel)
    _notificationModel = State(initialValue: notificationModel)
    let mediaSession = TopLevelMediaSessionCoordinator(
      service: mediaService,
      uploader: mediaUploader
    )
    _topLevelMediaSession = State(initialValue: mediaSession)
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.mediaPreviewLoader = mediaPreviewLoader
  }

  var body: some View {
    if let participant = authenticationModel.authenticatedParticipant {
      authenticatedContent(participant: participant)
    } else if authenticationModel.isAwaitingBiometricUnlock {
      BiometricUnlockView(authenticationModel: authenticationModel)
    } else {
      LoginOptionsView(
        model: loginOptionsModel,
        authenticationModel: authenticationModel
      )
    }
  }

  private func authenticatedContent(
    participant: AuthenticatedParticipant
  ) -> some View {
    TabView(selection: $selectedTab) {
      RelationshipView(
        model: relationshipModel,
        navigationPath: $relationshipNavigationPath,
        mediaService: mediaService,
        mediaUploader: mediaUploader,
        mediaSessionCoordinator: topLevelMediaSession,
        scoreMediaModel: topLevelMediaSession.relationshipScoreComposer,
        participant: participant,
        onAuthenticationRequired: { requirePINAgain(for: participant) }
      )
      .tabItem {
        Label("우리 사이", systemImage: "heart.text.square")
      }
      .tag(AuthenticatedTab.relationship)

      DiaryView(
        model: diaryModel,
        navigationPath: $diaryNavigationPath,
        mediaService: mediaService,
        mediaUploader: mediaUploader,
        mediaSessionCoordinator: topLevelMediaSession,
        newEntryMediaModel: topLevelMediaSession.diaryEntryComposer,
        participant: participant,
        onAuthenticationRequired: { requirePINAgain(for: participant) }
      )
      .tabItem {
        Label("일기", systemImage: "book.closed")
      }
      .tag(AuthenticatedTab.diary)

      AppSettingsView(
        participant: participant,
        notificationState: notificationModel.state,
        canRetryNotifications: notificationModel.canRetryRegistration,
        onRetryNotifications: notificationModel.retryRegistration,
        canRememberSession: authenticationModel.canOfferRemembering,
        isSessionRemembered: Binding(
          get: { authenticationModel.isSessionRemembered },
          set: { remember in
            Task {
              if remember {
                await authenticationModel.rememberCurrentSession()
              } else {
                await authenticationModel.forgetRememberedSession()
              }
            }
          }
        ),
        onLock: lockSession,
        onForget: forgetSession
      )
      .tabItem {
        Label("설정", systemImage: "gearshape")
      }
      .tag(AuthenticatedTab.settings)
    }
    .disabled(isEndingSession || isWriteInFlight)
    .overlay {
      if isEndingSession {
        ProgressView("안전하게 나가는 중이에요.")
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
    }
    .task(id: participant.slot.rawValue) {
      #if DEBUG
        prepareSyntheticMediaIfNeeded()
      #endif
      notificationModel.authenticatedSessionDidStart()
      consumeNotificationIntents(notificationModel.pendingRefetchIntents)
      await authenticationModel.refreshRememberedSessionStatus()
    }
    .onChange(of: notificationModel.authenticationRequired) { _, required in
      if required { requirePINAgain(for: participant) }
    }
    .onChange(of: notificationModel.pendingRefetchIntents) { _, intents in
      consumeNotificationIntents(intents)
    }
    .onChange(of: relationshipModel.scoreOutcomeRequiresConfirmation) { _, requiresConfirmation in
      injectUnknownOutcomeNotificationIfNeeded(requiresConfirmation: requiresConfirmation)
    }
    .onChange(of: relationshipModel.commentOutcomeRequiresConfirmation) {
      _, requiresConfirmation in
      injectRelationshipCommentUnknownOutcomeNotificationIfNeeded(
        requiresConfirmation: requiresConfirmation
      )
    }
    .onChange(of: diaryModel.mutationOutcomeRequiresConfirmation) { _, requiresConfirmation in
      injectDiaryUnknownOutcomeNotificationIfNeeded(requiresConfirmation: requiresConfirmation)
    }
    .onChange(of: isProtectedMutationActive) { _, isProtected in
      if !isProtected {
        consumeNotificationIntents(notificationModel.pendingRefetchIntents)
      }
    }
    .environment(\.privateMediaPreviewLoader, mediaPreviewLoader)
  }

  private var isWriteInFlight: Bool {
    relationshipModel.scoreSubmissionState == .submitting
      || relationshipModel.commentSubmissionState == .submitting
      || diaryModel.mutationState == .submitting
  }

  private var isProtectedMutationActive: Bool {
    isWriteInFlight
      || relationshipModel.scoreOutcomeRequiresConfirmation
      || relationshipModel.commentOutcomeRequiresConfirmation
      || relationshipModel.hasProtectedManualRetryDraft
      || relationshipModel.hasProtectedLocalCommentDraft
      || relationshipModel.hasProtectedLocalScoreDraft
      || diaryModel.mutationOutcomeRequiresConfirmation
      || diaryModel.hasProtectedManualRetryDraft
      || diaryModel.hasProtectedLocalDraft
  }

  #if DEBUG
    private func prepareSyntheticMediaIfNeeded() {
      guard !hasPreparedSyntheticMedia,
        WoorisaiUITestService.usesSyntheticMedia(
          arguments: ProcessInfo.processInfo.arguments
        ),
        let imageData = WoorisaiUITestFixtureImage.jpegData()
      else { return }
      hasPreparedSyntheticMedia = true
      try? topLevelMediaSession.relationshipScoreComposer.addPreparedAttachment(
        kind: .image,
        fileName: "portrait-selected.jpg",
        contentType: "image/jpeg",
        data: imageData
      )
      try? topLevelMediaSession.diaryEntryComposer.addPreparedAttachment(
        kind: .image,
        fileName: "landscape-selected.jpg",
        contentType: "image/jpeg",
        data: imageData
      )
    }
  #endif

  /// Lock the app: clear the in-memory session but keep the Keychain vault so Face ID can reopen
  /// it, and keep the push FID registered so notifications keep arriving while locked.
  private func lockSession() {
    endSession(
      resetsLoginOptions: true,
      notificationTeardown: { notificationModel.pauseRegistrationForLock() },
      authenticationTeardown: { await authenticationModel.lock() }
    )
  }

  /// Full sign-out: purge the Keychain vault and unregister the push FID. Next launch needs a PIN.
  private func forgetSession() {
    endSession(
      resetsLoginOptions: true,
      notificationTeardown: { await notificationModel.unregisterBeforeSignOut() },
      authenticationTeardown: { await authenticationModel.signOutAndForget() }
    )
  }

  private func requirePINAgain(for participant: AuthenticatedParticipant) {
    // The server rejected this credential, so unregister the FID and purge the vault (done inside
    // `authenticationModel.requirePINAgain`) — the stored session is no longer valid.
    endSession(
      resetsLoginOptions: false,
      notificationTeardown: { await notificationModel.unregisterBeforeSignOut() },
      authenticationTeardown: { await authenticationModel.requirePINAgain(for: participant) }
    )
  }

  /// Shared session-teardown: quiesce feature models and media, run the notification and
  /// authentication teardown steps in order, then release the ending-session gate.
  private func endSession(
    resetsLoginOptions: Bool,
    notificationTeardown: @escaping @MainActor () async -> Void,
    authenticationTeardown: @escaping @MainActor () async -> Void
  ) {
    guard !isEndingSession else { return }
    isEndingSession = true
    #if DEBUG
      hasPreparedSyntheticMedia = false
    #endif
    let releaseRejectedScoreSubmission =
      relationshipModel.rejectedMediaMutation == .scoreChange
    let releaseRejectedDiarySubmission =
      diaryModel.rejectedMediaMutation == .createEntry
    notificationModel.discardPendingRefetchIntents()
    relationshipNavigationPath.removeAll()
    diaryNavigationPath.removeAll()
    selectedTab = .relationship
    if resetsLoginOptions { loginOptionsModel.reset() }
    relationshipModel.clear()
    diaryModel.clear()
    Task {
      await Task.yield()
      await prepareTopLevelMediaForSessionEnd(
        releaseRejectedScoreSubmission: releaseRejectedScoreSubmission,
        releaseRejectedDiarySubmission: releaseRejectedDiarySubmission
      )
      await notificationTeardown()
      notificationModel.discardPendingRefetchIntents()
      relationshipModel.clear()
      diaryModel.clear()
      await authenticationTeardown()
      isEndingSession = false
    }
  }

  private func prepareTopLevelMediaForSessionEnd(
    releaseRejectedScoreSubmission: Bool,
    releaseRejectedDiarySubmission: Bool
  ) async {
    await mediaPreviewLoader.clearSession()
    await topLevelMediaSession.prepareForCredentialRemoval(
      releaseRejectedScoreSubmission: releaseRejectedScoreSubmission,
      releaseRejectedDiarySubmission: releaseRejectedDiarySubmission
    )
  }

  private func injectUnknownOutcomeNotificationIfNeeded(requiresConfirmation: Bool) {
    #if DEBUG
      guard requiresConfirmation,
        !hasInjectedUnknownOutcomeNotification,
        WoorisaiUITestService.injectsNotificationDuringUnknownOutcome(
          arguments: ProcessInfo.processInfo.arguments
        )
      else { return }
      hasInjectedUnknownOutcomeNotification = true
      notificationModel.receiveNotification(
        eventType: "scoreChangeCommentCreated",
        resourceID: "101"
      )
    #endif
  }

  private func injectDiaryUnknownOutcomeNotificationIfNeeded(requiresConfirmation: Bool) {
    #if DEBUG
      guard requiresConfirmation,
        !hasInjectedUnknownOutcomeNotification,
        WoorisaiUITestService.injectsDiaryNotificationDuringUnknownOutcome(
          arguments: ProcessInfo.processInfo.arguments
        )
      else { return }
      hasInjectedUnknownOutcomeNotification = true
      notificationModel.receiveNotification(
        eventType: "diaryEntryCommentCreated",
        resourceID: "999"
      )
    #endif
  }

  private func injectRelationshipCommentUnknownOutcomeNotificationIfNeeded(
    requiresConfirmation: Bool
  ) {
    #if DEBUG
      guard requiresConfirmation,
        !hasInjectedUnknownOutcomeNotification,
        WoorisaiUITestService.injectsRelationshipCommentNotificationDuringUnknownOutcome(
          arguments: ProcessInfo.processInfo.arguments
        )
      else { return }
      hasInjectedUnknownOutcomeNotification = true
      notificationModel.receiveNotification(
        eventType: "scoreChangeCommentCreated",
        resourceID: "999"
      )
    #endif
  }

  private func consumeNotificationIntents(
    _ intents: [NotificationResourceRefetchIntent]
  ) {
    // A path replacement tears down the current destination. Keep the intent buffered while a
    // parent mutation owns READY media so screen cleanup can never race the backend attachment.
    guard !isEndingSession, !isProtectedMutationActive else { return }
    for intent in intents {
      switch intent {
      case .scoreChange(let id):
        selectedTab = .relationship
        relationshipModel.reload()
        if NotificationNavigationDisposition.resolve(
          currentPath: relationshipNavigationPath,
          targetID: id
        ) == .refetchVisible {
          relationshipModel.loadThread(scoreChangeID: id)
        } else {
          relationshipNavigationPath = [id]
        }
      case .diaryEntry(let id):
        selectedTab = .diary
        diaryModel.reload()
        if NotificationNavigationDisposition.resolve(
          currentPath: diaryNavigationPath,
          targetID: id
        ) == .refetchVisible {
          diaryModel.loadDetail(entryID: id)
        } else {
          diaryNavigationPath = [id]
        }
      }
      notificationModel.consumeRefetchIntent(intent)
    }
  }
}

private enum AuthenticatedTab: Hashable {
  case relationship
  case diary
  case settings
}

private struct AppSettingsView: View {
  @Environment(\.openURL) private var openURL
  @State private var confirmsSessionLock = false
  @State private var confirmsForget = false

  let participant: AuthenticatedParticipant
  let notificationState: NotificationModel.State
  let canRetryNotifications: Bool
  let onRetryNotifications: @MainActor () -> Void
  let canRememberSession: Bool
  @Binding var isSessionRemembered: Bool
  let onLock: @MainActor () -> Void
  let onForget: @MainActor () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: WoorisaiSpacing.medium) {
            ParticipantAvatar(name: participant.displayName, size: 48)
            VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
              Text(participant.displayName)
                .font(.headline)
                .foregroundStyle(WoorisaiPalette.ink)
              Text("우리 둘만의 공간에 들어와 있어요")
                .font(.footnote)
                .foregroundStyle(WoorisaiPalette.muted)
            }
          }
          .padding(.vertical, WoorisaiSpacing.xSmall)
          .accessibilityElement(children: .combine)
          .accessibilityIdentifier("settings.currentParticipant")
        } header: {
          Text("현재 사용자")
        }
        Section("알림") {
          Label(notificationLabel, systemImage: notificationSymbol)
            .accessibilityIdentifier("settings.notification.status")
          if notificationState == .permissionDenied {
            Text("알림을 다시 켜려면 iOS 설정에서 우리사이의 알림 권한을 허용해 주세요.")
              .font(.footnote)
              .foregroundStyle(WoorisaiPalette.muted)
            Button {
              guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
                return
              }
              openURL(settingsURL)
            } label: {
              Label("시스템 설정 열기", systemImage: "gear")
                .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
            }
            .accessibilityIdentifier("settings.notification.openSettings")
          }
          if canRetryNotifications {
            Button("알림 등록 다시 시도", action: onRetryNotifications)
              .accessibilityIdentifier("settings.notification.retry")
          }
        }
        Section {
          if canRememberSession {
            Toggle(isOn: $isSessionRemembered) {
              Label("Face ID로 빠르게 열기", systemImage: "faceid")
            }
            .tint(WoorisaiPalette.coral)
            .accessibilityHint("이 기기에 로그인 정보를 저장하고 다음부터 Face ID로 들어옵니다.")
            .accessibilityIdentifier("settings.rememberSession")
          }

          Button {
            confirmsSessionLock = true
          } label: {
            Label("앱 잠그기", systemImage: "lock.fill")
              .foregroundStyle(WoorisaiPalette.coralDark)
          }
          .accessibilityHint("작성 중인 글과 첨부를 정리하고 앱을 잠급니다.")
          .accessibilityIdentifier("settings.lock")

          Button(role: .destructive) {
            confirmsForget = true
          } label: {
            Label("이 기기에서 로그인 정보 지우기", systemImage: "trash")
              .foregroundStyle(WoorisaiPalette.coralDark)
          }
          .accessibilityHint("이 기기에 저장된 로그인 정보를 삭제하고 로그아웃합니다.")
          .accessibilityIdentifier("settings.forget")
        } header: {
          Text("보안")
        } footer: {
          Text("잠그면 저장해 둔 경우 Face ID로, 아니면 PIN으로 다시 들어와요. 로그인 정보를 지우면 다음에 PIN을 다시 입력해야 해요.")
        }
      }
      .scrollContentBackground(.hidden)
      .background(WoorisaiPalette.cream)
      .navigationTitle("설정")
      .navigationBarTitleDisplayMode(.inline)
      .accessibilityIdentifier("settings.screen")
      .confirmationDialog(
        "앱을 잠글까요?",
        isPresented: $confirmsSessionLock,
        titleVisibility: .visible
      ) {
        Button("잠그기", role: .destructive, action: onLock)
          .accessibilityIdentifier("settings.lock.confirm")
        Button("계속 사용하기", role: .cancel) {}
      } message: {
        Text("작성 중인 글과 첨부가 정리돼요. 다시 들어올 땐 Face ID(설정해 둔 경우) 또는 PIN을 사용합니다.")
      }
      .confirmationDialog(
        "로그인 정보를 지울까요?",
        isPresented: $confirmsForget,
        titleVisibility: .visible
      ) {
        Button("지우기", role: .destructive, action: onForget)
          .accessibilityIdentifier("settings.forget.confirm")
        Button("취소", role: .cancel) {}
      } message: {
        Text("이 기기에 저장된 로그인 정보가 삭제돼요. 다시 들어오려면 PIN을 입력해야 해요.")
      }
    }
  }

  private var notificationLabel: String {
    switch notificationState {
    case .idle, .checkingPermission, .registering:
      "알림 설정 확인 중"
    case .registered:
      "알림 사용 중"
    case .permissionDenied:
      "알림 권한 꺼짐"
    case .unavailable:
      "알림 서비스 일시 중단"
    case .failed:
      "알림 등록 실패"
    }
  }

  private var notificationSymbol: String {
    switch notificationState {
    case .registered:
      "bell.badge"
    case .permissionDenied:
      "bell.slash"
    case .unavailable, .failed:
      "exclamationmark.triangle"
    case .idle, .checkingPermission, .registering:
      "bell"
    }
  }
}

@MainActor
private enum AppDependencies {
  static let credentialStore = InMemoryCredentialStore()

  static func makeServices(arguments: [String]) -> AppServices {
    let unavailable = ConfigurationFailureService()
    let disabledNotifications = DisabledNotificationPermissionAuthorizer()
    let unavailableInstallationIDs = UnavailableNotificationInstallationIDProvider()
    let mediaUploader = URLSessionPresignedMediaUploader()

    #if DEBUG
      if let service = WoorisaiUITestService(
        arguments: arguments,
        credentialStore: credentialStore
      ) {
        return AppServices(
          loginOptionsLoader: service,
          credentialValidator: service,
          relationshipService: service,
          diaryService: service,
          mediaService: service,
          mediaUploader: WoorisaiUITestPresignedMediaUploader(),
          notificationFIDService: unavailable,
          notificationPermissions: disabledNotifications,
          notificationInstallationIDs: unavailableInstallationIDs,
          credentialStore: credentialStore
        )
      }
      if NSClassFromString("XCTestCase") != nil {
        let service = AppTestHostService(credentialStore: credentialStore)
        return AppServices(
          loginOptionsLoader: service,
          credentialValidator: service,
          relationshipService: service,
          diaryService: unavailable,
          mediaService: unavailable,
          mediaUploader: mediaUploader,
          notificationFIDService: unavailable,
          notificationPermissions: disabledNotifications,
          notificationInstallationIDs: unavailableInstallationIDs,
          credentialStore: credentialStore
        )
      }
    #endif

    do {
      let client = try RuntimeConfiguration().makeAPIClient(
        credentialStore: credentialStore
      )
      let mediaService = try WoorisaiMediaAPI(apiClient: client)
      return AppServices(
        loginOptionsLoader: client,
        credentialValidator: client,
        relationshipService: client,
        diaryService: client,
        mediaService: mediaService,
        mediaUploader: mediaUploader,
        notificationFIDService: client,
        notificationPermissions: SystemNotificationPermissionAuthorizer(),
        notificationInstallationIDs: FirebaseNotificationInstallationIDProvider(),
        credentialStore: credentialStore,
        credentialVault: KeychainCredentialVault(),
        biometricProbe: LocalAuthenticationBiometricProbe(),
        shouldRestoreSession: true
      )
    } catch {
      let service = ConfigurationFailureService()
      return AppServices(
        loginOptionsLoader: service,
        credentialValidator: service,
        relationshipService: service,
        diaryService: service,
        mediaService: service,
        mediaUploader: mediaUploader,
        notificationFIDService: service,
        notificationPermissions: disabledNotifications,
        notificationInstallationIDs: unavailableInstallationIDs,
        credentialStore: credentialStore
      )
    }
  }
}

private struct AppServices {
  let loginOptionsLoader: any LoginOptionsLoading
  let credentialValidator: any CredentialValidating
  let relationshipService: any RelationshipServing
  let diaryService: any DiaryServing
  let mediaService: any MediaServing
  let mediaUploader: any PresignedMediaUploading
  let notificationFIDService: any NotificationFIDServing
  let notificationPermissions: any NotificationPermissionAuthorizing
  let notificationInstallationIDs: any NotificationInstallationIDProviding
  let credentialStore: InMemoryCredentialStore
  // Defaulted so only the real-client branch opts into biometric session persistence; every
  // test / UI-test / failure branch inherits inert values, keeping session restore a no-op.
  var credentialVault: any CredentialVaultStoring = InertCredentialVault()
  var biometricProbe: any BiometricAvailabilityProbing = UnavailableBiometricProbe()
  var shouldRestoreSession = false
}

private struct ConfigurationFailureService: LoginOptionsLoading, CredentialValidating,
  RelationshipServing, DiaryServing, MediaServing, NotificationFIDServing
{
  func loadLoginOptions() async throws -> [LoginOption] {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func validateCredential(
    _ credential: ParticipantCredential
  ) async throws -> AuthenticatedParticipant {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func loadRelationshipScores() async throws -> RelationshipScores {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func updateDiaryEntry(
    id: Int64,
    draft: DiaryEntryUpdateDraft
  ) async throws -> DiaryEntry {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func deleteDiaryEntry(id: Int64) async throws {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func createDiaryComment(
    entryID: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func updateDiaryComment(
    id: Int64,
    draft: DiaryCommentDraft
  ) async throws -> DiaryComment {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func deleteDiaryComment(id: Int64) async throws {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func discardUpload(id: UUID) async throws {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func registerNotificationFID(_ fid: NotificationInstallationID) async throws {
    throw RuntimeConfigurationError.invalidAPIHost
  }

  func unregisterNotificationFID(_ fid: NotificationInstallationID) async throws {
    throw RuntimeConfigurationError.invalidAPIHost
  }
}

private struct DisabledNotificationPermissionAuthorizer: NotificationPermissionAuthorizing {
  func currentStatus() async -> NotificationPermissionStatus { .denied }
  func requestAuthorization() async throws -> NotificationPermissionStatus { .denied }
}

private struct UnavailableNotificationInstallationIDProvider:
  NotificationInstallationIDProviding
{
  func currentInstallationID() async throws -> String {
    throw NotificationProviderUnavailableError.firebaseConfigurationMissing
  }
}

#if DEBUG
  private actor AppTestHostService: LoginOptionsLoading, CredentialValidating,
    RelationshipServing
  {
    let credentialStore: InMemoryCredentialStore

    init(credentialStore: InMemoryCredentialStore) {
      self.credentialStore = credentialStore
    }

    func loadLoginOptions() async throws -> [LoginOption] {
      DebugRelationshipFixtures.options
    }

    func validateCredential(
      _ credential: ParticipantCredential
    ) async throws -> AuthenticatedParticipant {
      await credentialStore.replace(with: credential)
      return DebugRelationshipFixtures.authenticatedParticipant(slot: credential.slot)
    }

    func loadRelationshipScores() async throws -> RelationshipScores {
      DebugRelationshipFixtures.scores
    }

    func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
      DebugRelationshipFixtures.page(pageNumber: pageNumber)
    }

    func createScoreChange(
      _ draft: RelationshipScoreChangeDraft
    ) async throws -> RelationshipScoreChangeCreated {
      DebugRelationshipFixtures.createdChange(draft: draft)
    }

    func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
      DebugRelationshipFixtures.thread
    }

    func createScoreChangeComment(
      scoreChangeID: Int64,
      draft: RelationshipScoreCommentDraft
    ) async throws -> RelationshipScoreComment {
      DebugRelationshipFixtures.createdComment(content: draft.content)
    }
  }

  actor WoorisaiUITestService: LoginOptionsLoading, CredentialValidating,
    RelationshipServing, DiaryServing, MediaServing
  {
    static let argumentName = "--login-options-ui-test-scenario"
    static let verificationTokenArgumentName = "--login-options-ui-test-token"
    static let activeScenarioFileName = "woorisai-active-ui-test-scenario"

    static func isUITest(arguments: [String]) -> Bool {
      scenario(arguments: arguments) != nil
    }

    static func usesSyntheticMedia(arguments: [String]) -> Bool {
      let scenario = scenario(arguments: arguments)
      return scenario == .mediaRich || scenario == .diaryMediaEditorUnknownOutcome
    }

    static func corruptsFirstVideoLoad(arguments: [String]) -> Bool {
      scenario(arguments: arguments) == .mediaCorruptVideoThenRecovery
    }

    static func injectsNotificationDuringUnknownOutcome(arguments: [String]) -> Bool {
      scenario(arguments: arguments) == .relationshipUnknownOutcomeWithPush
    }

    static func injectsDiaryNotificationDuringUnknownOutcome(arguments: [String]) -> Bool {
      scenario(arguments: arguments) == .diaryEditorUnknownOutcomeWithPush
    }

    static func injectsRelationshipCommentNotificationDuringUnknownOutcome(
      arguments: [String]
    ) -> Bool {
      scenario(arguments: arguments) == .relationshipCommentUnknownOutcomeWithPush
    }

    private enum Scenario: String {
      case adaptiveContent
      case authenticationRejectedThenSuccess
      case diaryConflict
      case diaryCRUD
      case diaryEditorUnknownOutcome
      case diaryEditorInconclusiveOutcome
      case diaryEditorUnknownOutcomeWithPush
      case diaryMediaEditorUnknownOutcome
      case diaryUnknownOutcome
      case emptyContent
      case failureThenSuccess
      case loading
      case longNames
      case longScoreReason
      case manyHistory
      case pagedHistoryFailure
      case mediaRich
      case mediaCorruptVideoThenRecovery
      case relationship
      case relationshipCommentUnknownOutcomeWithPush
      case relationshipConflict
      case relationshipUnknownOutcomeWithPush
      case sessionCredentialRejected
      case success
      case unavailableThenSuccess
    }

    private let scenario: Scenario
    private let credentialStore: InMemoryCredentialStore
    private var loginAttemptCount = 0
    private var credentialAttemptCount = 0
    private var relationshipLoadAttemptCount = 0
    private var scoreCreateAttemptCount = 0
    private var scorePageTwoAttemptCount = 0
    private var relationshipCommentCreateAttemptCount = 0
    private var authenticatedSlot = ParticipantSlot.one
    private var diaryEntry: DiaryEntry?
    private var diaryComments: [DiaryComment]
    private var diaryMutationAttemptCount = 0
    private var diaryEntryUpdateAttemptCount = 0
    private var diaryCommentUpdateAttemptCount = 0
    private var mediaDrafts: [UUID: MediaUploadDraft] = [:]

    init?(arguments: [String], credentialStore: InMemoryCredentialStore) {
      guard let scenario = Self.scenario(arguments: arguments) else { return nil }
      self.scenario = scenario
      self.credentialStore = credentialStore
      diaryEntry = DebugDiaryFixtures.entry
      diaryComments = DebugDiaryFixtures.comments
      if scenario == .diaryMediaEditorUnknownOutcome {
        diaryEntry = DebugDiaryFixtures.mediaEntry
      }
      if let verificationToken = Self.argumentValue(
        named: Self.verificationTokenArgumentName,
        arguments: arguments
      ) {
        let markerURL = FileManager.default.temporaryDirectory
          .appendingPathComponent(Self.activeScenarioFileName)
        try? "\(scenario.rawValue):\(verificationToken)".write(
          to: markerURL,
          atomically: true,
          encoding: .utf8
        )
      }
    }

    static func dynamicTypeSize(arguments: [String]) -> DynamicTypeSize? {
      switch scenario(arguments: arguments) {
      case .adaptiveContent, .longNames:
        return .accessibility5
      case .longScoreReason:
        return .large
      default:
        return nil
      }
    }

    func loadLoginOptions() async throws -> [LoginOption] {
      loginAttemptCount += 1
      switch scenario {
      case .unavailableThenSuccess where loginAttemptCount == 1:
        throw WoorisaiAPIError.loginOptionsUnavailable
      case .failureThenSuccess where loginAttemptCount == 1:
        throw InjectedUITestFailure()
      case .adaptiveContent, .longNames:
        return DebugRelationshipFixtures.longNameOptions
      case .loading:
        while true { try await Task.sleep(for: .seconds(60)) }
      default:
        return DebugRelationshipFixtures.options
      }
    }

    func validateCredential(
      _ credential: ParticipantCredential
    ) async throws -> AuthenticatedParticipant {
      credentialAttemptCount += 1
      await credentialStore.replace(with: credential)
      if scenario == .authenticationRejectedThenSuccess, credentialAttemptCount == 1 {
        await credentialStore.clear()
        throw WoorisaiAPIError.credentialRejected
      }
      let options =
        scenario == .adaptiveContent
        ? DebugRelationshipFixtures.longNameOptions
        : DebugRelationshipFixtures.options
      authenticatedSlot = credential.slot
      return DebugRelationshipFixtures.authenticatedParticipant(
        slot: credential.slot,
        options: options
      )
    }

    func loadRelationshipScores() async throws -> RelationshipScores {
      relationshipLoadAttemptCount += 1
      if scenario == .sessionCredentialRejected, relationshipLoadAttemptCount == 1 {
        await credentialStore.clear()
        throw WoorisaiAPIError.credentialRejected
      }
      return DebugRelationshipFixtures.orientedScores(
        currentSlot: authenticatedSlot,
        usesAdaptiveContent: scenario == .adaptiveContent
      )
    }

    func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
      if scenario == .pagedHistoryFailure, pageNumber == 2 {
        scorePageTwoAttemptCount += 1
        if scorePageTwoAttemptCount == 1 {
          try await Task.sleep(for: .seconds(3))
          throw WoorisaiAPIError.serviceUnavailable
        }
      }
      return DebugRelationshipFixtures.page(
        pageNumber: pageNumber,
        usesAdaptiveContent: scenario == .adaptiveContent,
        usesLongReason: scenario == .longScoreReason,
        usesManyHistory: scenario == .manyHistory,
        usesPagedHistory: scenario == .pagedHistoryFailure,
        usesMedia: scenario == .mediaRich || scenario == .mediaCorruptVideoThenRecovery,
        currentSlot: authenticatedSlot
      )
    }

    func createScoreChange(
      _ draft: RelationshipScoreChangeDraft
    ) async throws -> RelationshipScoreChangeCreated {
      scoreCreateAttemptCount += 1
      if scenario == .relationshipConflict, scoreCreateAttemptCount == 1 {
        throw WoorisaiAPIError.conflict
      }
      if scenario == .relationshipUnknownOutcomeWithPush, scoreCreateAttemptCount == 1 {
        throw WoorisaiAPIError.transport
      }
      return DebugRelationshipFixtures.createdChange(
        draft: draft,
        currentSlot: authenticatedSlot
      )
    }

    func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
      if scenario == .relationshipCommentUnknownOutcomeWithPush, id == 999 {
        throw WoorisaiAPIError.notFound
      }
      let thread: RelationshipScoreThread
      switch scenario {
      case .adaptiveContent:
        thread = DebugRelationshipFixtures.adaptiveThread
      case .longScoreReason:
        thread = DebugRelationshipFixtures.longReasonThread
      case .mediaRich, .mediaCorruptVideoThenRecovery:
        thread = DebugRelationshipFixtures.mediaThread
      default:
        thread = DebugRelationshipFixtures.thread
      }
      let orientedThread = DebugRelationshipFixtures.thread(
        thread,
        currentSlot: authenticatedSlot
      )
      guard id == orientedThread.change.id else { throw InjectedUITestFailure() }
      return orientedThread
    }

    func createScoreChangeComment(
      scoreChangeID: Int64,
      draft: RelationshipScoreCommentDraft
    ) async throws -> RelationshipScoreComment {
      if scenario == .relationshipCommentUnknownOutcomeWithPush {
        relationshipCommentCreateAttemptCount += 1
        if relationshipCommentCreateAttemptCount == 1 {
          throw WoorisaiAPIError.transport
        }
      }
      return DebugRelationshipFixtures.createdComment(
        content: draft.content,
        currentSlot: authenticatedSlot
      )
    }

    func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
      let baseEntry: DiaryEntry?
      switch scenario {
      case .adaptiveContent:
        baseEntry = DebugDiaryFixtures.entry
      case .mediaRich:
        baseEntry = DebugDiaryFixtures.mediaEntry
      case .diaryCRUD, .diaryConflict, .diaryEditorUnknownOutcome,
        .diaryEditorInconclusiveOutcome,
        .diaryEditorUnknownOutcomeWithPush, .diaryMediaEditorUnknownOutcome,
        .diaryUnknownOutcome:
        baseEntry = diaryEntry
      case .emptyContent:
        baseEntry = nil
      default:
        throw InjectedUITestFailure()
      }
      let entries =
        baseEntry.map {
          [DebugDiaryFixtures.entry($0, currentSlot: authenticatedSlot)]
        } ?? []
      return DiaryEntryPage(
        entries: pageNumber == 1 ? entries : [],
        pageNumber: pageNumber,
        hasNext: false,
        totalCount: Int64(entries.count)
      )
    }

    func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry {
      guard
        scenario == .diaryCRUD || scenario == .emptyContent
          || scenario == .diaryUnknownOutcome
      else {
        throw InjectedUITestFailure()
      }
      diaryMutationAttemptCount += 1
      if scenario == .diaryUnknownOutcome, diaryMutationAttemptCount == 1 {
        throw WoorisaiAPIError.transport
      }
      let created = DiaryEntry(
        id: 901,
        author: DebugDiaryFixtures.participant(slot: authenticatedSlot),
        content: draft.content,
        createdAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(100),
        updatedAt: nil,
        isMine: true,
        attachments: [],
        commentCount: 0
      )
      diaryEntry = created
      diaryComments = []
      return created
    }

    func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
      let baseDetail: DiaryEntryDetail
      switch scenario {
      case .adaptiveContent:
        baseDetail = DebugDiaryFixtures.detail
      case .mediaRich:
        baseDetail = DebugDiaryFixtures.mediaDetail
      case .diaryCRUD, .diaryConflict, .diaryEditorUnknownOutcome,
        .diaryEditorInconclusiveOutcome,
        .diaryEditorUnknownOutcomeWithPush, .diaryMediaEditorUnknownOutcome,
        .diaryUnknownOutcome, .emptyContent:
        guard let diaryEntry else { throw WoorisaiAPIError.notFound }
        baseDetail = DiaryEntryDetail(entry: diaryEntry, comments: diaryComments)
      default:
        throw InjectedUITestFailure()
      }
      let detail = DebugDiaryFixtures.detail(baseDetail, currentSlot: authenticatedSlot)
      guard id == detail.entry.id else { throw WoorisaiAPIError.notFound }
      return detail
    }

    func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) async throws -> DiaryEntry {
      guard
        scenario == .diaryCRUD || scenario == .diaryConflict
          || scenario == .diaryEditorUnknownOutcome
          || scenario == .diaryEditorInconclusiveOutcome
          || scenario == .diaryEditorUnknownOutcomeWithPush
          || scenario == .diaryMediaEditorUnknownOutcome,
        let current = diaryEntry,
        current.id == id,
        current.author.slot == authenticatedSlot
      else {
        throw WoorisaiAPIError.forbidden
      }
      diaryMutationAttemptCount += 1
      if scenario == .diaryConflict, diaryMutationAttemptCount == 1 {
        throw WoorisaiAPIError.conflict
      }
      diaryEntryUpdateAttemptCount += 1
      if scenario == .diaryEditorInconclusiveOutcome,
        diaryEntryUpdateAttemptCount == 1
      {
        diaryEntry = DiaryEntry(
          id: current.id,
          author: current.author,
          content: "다른 기기에서 먼저 저장된 최신 일기",
          createdAt: current.createdAt,
          updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(105),
          isMine: true,
          attachments: current.attachments,
          commentCount: current.commentCount
        )
        throw WoorisaiAPIError.transport
      }
      if scenario == .diaryEditorUnknownOutcome
        || scenario == .diaryEditorUnknownOutcomeWithPush
        || scenario == .diaryMediaEditorUnknownOutcome,
        diaryEntryUpdateAttemptCount == 1
      {
        throw WoorisaiAPIError.transport
      }
      let attachments: [DiaryAttachment]
      switch draft.attachments {
      case .preserve:
        attachments = current.attachments
      case .replace(let ids):
        attachments = ids.enumerated().map { index, id in
          DiaryAttachment(
            id: id,
            kind: .image,
            fileName: "square-new-\(index + 1).jpg",
            contentType: "image/jpeg",
            byteSize: 32_000
          )
        }
      }
      let updated = DiaryEntry(
        id: current.id,
        author: current.author,
        content: draft.content ?? current.content,
        createdAt: current.createdAt,
        updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(110),
        isMine: true,
        attachments: attachments,
        commentCount: current.commentCount
      )
      diaryEntry = updated
      return updated
    }

    func deleteDiaryEntry(id: Int64) async throws {
      guard scenario == .diaryCRUD,
        let current = diaryEntry,
        current.id == id,
        current.author.slot == authenticatedSlot
      else {
        throw WoorisaiAPIError.forbidden
      }
      diaryEntry = nil
      diaryComments = []
    }

    func createDiaryComment(
      entryID: Int64,
      draft: DiaryCommentDraft
    ) async throws -> DiaryComment {
      guard scenario == .diaryCRUD, diaryEntry?.id == entryID else {
        throw InjectedUITestFailure()
      }
      let created = DiaryComment(
        id: 903,
        author: DebugDiaryFixtures.participant(slot: authenticatedSlot),
        content: draft.content,
        createdAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(120),
        updatedAt: nil,
        isMine: true
      )
      diaryComments.append(created)
      return created
    }

    func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) async throws -> DiaryComment {
      guard scenario == .diaryCRUD || scenario == .diaryEditorUnknownOutcome,
        let index = diaryComments.firstIndex(where: { $0.id == id }),
        diaryComments[index].author.slot == authenticatedSlot
      else {
        throw WoorisaiAPIError.forbidden
      }
      diaryCommentUpdateAttemptCount += 1
      if scenario == .diaryEditorUnknownOutcome, diaryCommentUpdateAttemptCount == 1 {
        throw WoorisaiAPIError.transport
      }
      let current = diaryComments[index]
      let updated = DiaryComment(
        id: current.id,
        author: current.author,
        content: draft.content,
        createdAt: current.createdAt,
        updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(130),
        isMine: true
      )
      diaryComments[index] = updated
      return updated
    }

    func deleteDiaryComment(id: Int64) async throws {
      guard scenario == .diaryCRUD,
        let index = diaryComments.firstIndex(where: { $0.id == id }),
        diaryComments[index].author.slot == authenticatedSlot
      else {
        throw WoorisaiAPIError.forbidden
      }
      diaryComments.remove(at: index)
    }

    func initiateUpload(_ draft: MediaUploadDraft) async throws -> MediaUploadGrant {
      let id = UUID()
      mediaDrafts[id] = draft
      return try MediaUploadGrant(
        uploadID: id,
        uploadURL: URL(string: "https://upload.invalid/\(id.uuidString)")!,
        requiredHeaders: MediaUploadRequiredHeaders(
          contentType: draft.contentType,
          cacheControl: MediaUploadRequiredHeaders.privateNoStore
        ),
        expiresAt: Date().addingTimeInterval(300)
      )
    }

    func completeUpload(id: UUID) async throws -> CompletedMediaUpload {
      guard let draft = mediaDrafts[id] else { throw WoorisaiAPIError.notFound }
      return try CompletedMediaUpload(
        id: id,
        kind: draft.kind,
        fileName: draft.fileName,
        contentType: draft.contentType,
        byteSize: draft.byteSize
      )
    }

    func discardUpload(id: UUID) async throws {
      mediaDrafts.removeValue(forKey: id)
    }

    func issueDownloadGrant(attachmentID: UUID) async throws -> MediaDownloadGrant {
      try MediaDownloadGrant(
        downloadURL: URL(string: "https://download.invalid/\(attachmentID.uuidString)")!,
        expiresAt: Date().addingTimeInterval(300)
      )
    }

    private static func scenario(arguments: [String]) -> Scenario? {
      guard let value = argumentValue(named: argumentName, arguments: arguments) else { return nil }
      return Scenario(rawValue: value)
    }

    private static func argumentValue(named name: String, arguments: [String]) -> String? {
      guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
      }
      return arguments[index + 1]
    }
  }

  private enum DebugRelationshipFixtures {
    static let options = [
      LoginOption(slot: 1, displayName: "봄"),
      LoginOption(slot: 2, displayName: "여름"),
    ]

    static let longNameOptions = [
      LoginOption(slot: 1, displayName: "가나다라마바사아자차카타파하가나다라마바사아자차카타파하"),
      LoginOption(slot: 2, displayName: "우리사이에서사용하는아주긴두번째참가자이름"),
    ]

    static let current = RelationshipParticipant(
      slot: .one,
      displayName: "봄",
      isCurrentParticipant: true
    )
    static let partner = RelationshipParticipant(
      slot: .two,
      displayName: "여름",
      isCurrentParticipant: false
    )
    static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
    static let adaptiveCurrent = RelationshipParticipant(
      slot: .one,
      displayName: longNameOptions[0].displayName,
      isCurrentParticipant: true
    )
    static let adaptivePartner = RelationshipParticipant(
      slot: .two,
      displayName: longNameOptions[1].displayName,
      isCurrentParticipant: false
    )
    static let scores = RelationshipScores(
      currentParticipant: current,
      partner: partner,
      outgoingScore: 70,
      incomingScore: 82,
      outgoingUpdatedAt: timestamp,
      incomingUpdatedAt: timestamp.addingTimeInterval(1)
    )
    static let adaptiveScores = RelationshipScores(
      currentParticipant: adaptiveCurrent,
      partner: adaptivePartner,
      outgoingScore: 70,
      incomingScore: 82,
      outgoingUpdatedAt: timestamp,
      incomingUpdatedAt: timestamp.addingTimeInterval(1)
    )
    static let change = RelationshipScoreChange(
      id: 101,
      sourceParticipant: current,
      targetParticipant: partner,
      changedBy: current,
      delta: 5,
      resultingScore: 70,
      reason: "고마운 하루",
      createdAt: timestamp,
      commentCount: 1,
      attachments: []
    )
    static let comment = RelationshipScoreComment(
      id: 301,
      author: partner,
      content: "나도 고마워",
      createdAt: timestamp.addingTimeInterval(1),
      attachments: []
    )
    static let thread = RelationshipScoreThread(change: change, comments: [comment])
    static let historyChanges = (0..<4).map { index in
      RelationshipScoreChange(
        id: 101 + Int64(index),
        sourceParticipant: current,
        targetParticipant: partner,
        changedBy: current,
        delta: index.isMultiple(of: 2) ? 2 : -1,
        resultingScore: 70 - index,
        reason: "마음 기록 \(index + 1)",
        createdAt: timestamp.addingTimeInterval(TimeInterval(-index * 3_600)),
        commentCount: index == 0 ? 1 : 0,
        attachments: []
      )
    }
    static let adaptiveChange = RelationshipScoreChange(
      id: 401,
      sourceParticipant: adaptiveCurrent,
      targetParticipant: adaptivePartner,
      changedBy: adaptiveCurrent,
      delta: 5,
      resultingScore: 70,
      reason: "오래 읽어도 잘리지 않아야 하는 마음의 이유를 충분히 길게 적어 두었어요. 작은 화면과 큰 글자에서도 전체 내용을 천천히 읽을 수 있어야 해요.",
      createdAt: timestamp,
      commentCount: 1,
      attachments: []
    )
    static let adaptiveComment = RelationshipScoreComment(
      id: 402,
      author: adaptivePartner,
      content: "긴 댓글도 글자가 겹치거나 버튼을 밀어내지 않고 자연스럽게 여러 줄로 보여야 해요.",
      createdAt: timestamp.addingTimeInterval(1),
      attachments: []
    )
    static let adaptiveThread = RelationshipScoreThread(
      change: adaptiveChange,
      comments: [adaptiveComment]
    )
    static let longReasonChange = RelationshipScoreChange(
      id: 701,
      sourceParticipant: current,
      targetParticipant: partner,
      changedBy: current,
      delta: 5,
      resultingScore: 70,
      reason: """
        첫 번째 줄에는 오늘의 마음을 남겨요.
        두 번째 줄도 숨기지 않고 보여 줘요.
        세 번째 줄은 목록에서 미리 볼 수 있어요.
        네 번째 줄 다음에는 더 많은 이야기가 있어요.
        다섯 번째 줄은 상세 화면에서 이어져요.
        여섯 번째 줄까지 키보드가 떠도 보여야 해요.
        """,
      createdAt: timestamp,
      commentCount: 1,
      attachments: []
    )
    static let longReasonThread = RelationshipScoreThread(
      change: longReasonChange,
      comments: [comment]
    )
    static let portraitMedia = RelationshipMedia(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
      kind: .image,
      fileName: "portrait-heart.jpg",
      contentType: "image/jpeg",
      byteSize: 32_000
    )
    static let landscapeMedia = RelationshipMedia(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
      kind: .image,
      fileName: "landscape-picnic.jpg",
      contentType: "image/jpeg",
      byteSize: 32_000
    )
    static let panoramaMedia = RelationshipMedia(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
      kind: .image,
      fileName: "panorama-sunset.jpg",
      contentType: "image/jpeg",
      byteSize: 32_000
    )
    static let squareMedia = RelationshipMedia(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
      kind: .image,
      fileName: "square-cookie.jpg",
      contentType: "image/jpeg",
      byteSize: 32_000
    )
    static let videoMedia = RelationshipMedia(
      id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
      kind: .video,
      fileName: "tiny-memory.mp4",
      contentType: "video/mp4",
      byteSize: 2_679
    )
    static let mediaChange = RelationshipScoreChange(
      id: 801,
      sourceParticipant: current,
      targetParticipant: partner,
      changedBy: current,
      delta: 4,
      resultingScore: 74,
      reason: "함께 산책해서 마음이 몽글몽글해졌어",
      createdAt: timestamp,
      commentCount: 2,
      attachments: [landscapeMedia]
    )
    static let mediaComment = RelationshipScoreComment(
      id: 802,
      author: partner,
      content: "서로 다른 모양의 사진도 가지런히 보여요.",
      createdAt: timestamp.addingTimeInterval(1),
      attachments: [portraitMedia, landscapeMedia, panoramaMedia, squareMedia]
    )
    static let mediaVideoComment = RelationshipScoreComment(
      id: 803,
      author: current,
      content: "짧은 영상도 원본 비율로 안전하게 열어요.",
      createdAt: timestamp.addingTimeInterval(2),
      attachments: [videoMedia]
    )
    static let mediaThread = RelationshipScoreThread(
      change: mediaChange,
      comments: [mediaComment, mediaVideoComment]
    )

    static func authenticatedParticipant(
      slot: ParticipantSlot,
      options: [LoginOption] = DebugRelationshipFixtures.options
    ) -> AuthenticatedParticipant {
      let option = options.first { $0.slot == slot.rawValue } ?? options[0]
      return AuthenticatedParticipant(slot: slot, displayName: option.displayName)
    }

    static func orientedScores(
      currentSlot: ParticipantSlot,
      usesAdaptiveContent: Bool = false
    ) -> RelationshipScores {
      let base = usesAdaptiveContent ? adaptiveScores : DebugRelationshipFixtures.scores
      guard currentSlot == .two else { return base }
      return RelationshipScores(
        currentParticipant: participant(base.partner, currentSlot: currentSlot),
        partner: participant(base.currentParticipant, currentSlot: currentSlot),
        outgoingScore: base.incomingScore,
        incomingScore: base.outgoingScore,
        outgoingUpdatedAt: base.incomingUpdatedAt,
        incomingUpdatedAt: base.outgoingUpdatedAt
      )
    }

    static func thread(
      _ base: RelationshipScoreThread,
      currentSlot: ParticipantSlot
    ) -> RelationshipScoreThread {
      RelationshipScoreThread(
        change: change(base.change, currentSlot: currentSlot),
        comments: base.comments.map { comment($0, currentSlot: currentSlot) }
      )
    }

    static func page(
      pageNumber: Int,
      usesAdaptiveContent: Bool = false,
      usesLongReason: Bool = false,
      usesManyHistory: Bool = false,
      usesPagedHistory: Bool = false,
      usesMedia: Bool = false,
      currentSlot: ParticipantSlot = .one
    ) -> RelationshipScoreChangePage {
      let firstPageChange: RelationshipScoreChange
      if usesAdaptiveContent {
        firstPageChange = adaptiveChange
      } else if usesLongReason {
        firstPageChange = longReasonChange
      } else if usesMedia {
        firstPageChange = mediaChange
      } else {
        firstPageChange = change
      }
      let orientedHistory = historyChanges.map { change($0, currentSlot: currentSlot) }
      let pageChanges: [RelationshipScoreChange]
      if usesPagedHistory {
        pageChanges =
          pageNumber == 1
          ? Array(orientedHistory.prefix(3)) : Array(orientedHistory.dropFirst(3))
      } else if usesManyHistory {
        pageChanges = pageNumber == 1 ? orientedHistory : []
      } else {
        pageChanges = pageNumber == 1 ? [change(firstPageChange, currentSlot: currentSlot)] : []
      }
      return RelationshipScoreChangePage(
        changes: pageChanges,
        pageNumber: pageNumber,
        hasNext: usesPagedHistory && pageNumber == 1,
        totalCount: Int64(
          usesPagedHistory || usesManyHistory ? orientedHistory.count : pageChanges.count
        )
      )
    }

    static func createdChange(
      draft: RelationshipScoreChangeDraft,
      currentSlot: ParticipantSlot = .one
    ) -> RelationshipScoreChangeCreated {
      let currentScores = orientedScores(currentSlot: currentSlot)
      let target: Int
      switch draft.mutation {
      case .target(let value): target = value
      case .delta(let value): target = currentScores.outgoingScore + value
      }
      let created = RelationshipScoreChange(
        id: 202,
        sourceParticipant: currentScores.currentParticipant,
        targetParticipant: currentScores.partner,
        changedBy: currentScores.currentParticipant,
        delta: target - currentScores.outgoingScore,
        resultingScore: target,
        reason: draft.reason,
        createdAt: timestamp.addingTimeInterval(10),
        commentCount: 0,
        attachments: []
      )
      return RelationshipScoreChangeCreated(
        change: created,
        outgoingScore: target,
        outgoingUpdatedAt: created.createdAt
      )
    }

    static func createdComment(
      content: String?,
      currentSlot: ParticipantSlot = .one
    ) -> RelationshipScoreComment {
      let currentScores = orientedScores(currentSlot: currentSlot)
      return RelationshipScoreComment(
        id: 302,
        author: currentScores.currentParticipant,
        content: content,
        createdAt: timestamp.addingTimeInterval(20),
        attachments: []
      )
    }

    private static func participant(
      _ base: RelationshipParticipant,
      currentSlot: ParticipantSlot
    ) -> RelationshipParticipant {
      RelationshipParticipant(
        slot: base.slot,
        displayName: base.displayName,
        isCurrentParticipant: base.slot == currentSlot
      )
    }

    private static func change(
      _ base: RelationshipScoreChange,
      currentSlot: ParticipantSlot
    ) -> RelationshipScoreChange {
      RelationshipScoreChange(
        id: base.id,
        sourceParticipant: participant(base.sourceParticipant, currentSlot: currentSlot),
        targetParticipant: participant(base.targetParticipant, currentSlot: currentSlot),
        changedBy: participant(base.changedBy, currentSlot: currentSlot),
        delta: base.delta,
        resultingScore: base.resultingScore,
        reason: base.reason,
        createdAt: base.createdAt,
        commentCount: base.commentCount,
        attachments: base.attachments
      )
    }

    private static func comment(
      _ base: RelationshipScoreComment,
      currentSlot: ParticipantSlot
    ) -> RelationshipScoreComment {
      RelationshipScoreComment(
        id: base.id,
        author: participant(base.author, currentSlot: currentSlot),
        content: base.content,
        createdAt: base.createdAt,
        attachments: base.attachments
      )
    }
  }

  private enum DebugDiaryFixtures {
    static func participant(slot: ParticipantSlot) -> DiaryParticipant {
      switch slot {
      case .one:
        return DiaryParticipant(slot: .one, displayName: "봄")
      case .two:
        return DiaryParticipant(slot: .two, displayName: "여름")
      }
    }

    static let author = DiaryParticipant(
      slot: .one,
      displayName: DebugRelationshipFixtures.longNameOptions[0].displayName
    )
    static let partner = DiaryParticipant(
      slot: .two,
      displayName: DebugRelationshipFixtures.longNameOptions[1].displayName
    )
    static let entry = DiaryEntry(
      id: 501,
      author: author,
      content:
        "긴 한국어 일기 내용이 작은 화면과 큰 글자에서도 카드 밖으로 밀려나지 않고 자연스럽게 이어져야 해요. 우리 둘의 기록은 중간에서 잘리지 않고 상세 화면에서 끝까지 읽을 수 있어야 합니다.",
      createdAt: DebugRelationshipFixtures.timestamp,
      updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(10),
      isMine: true,
      attachments: [],
      commentCount: 2
    )
    static let mediaAttachments = [
      DiaryAttachment(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        kind: .image,
        fileName: "portrait-flower.jpg",
        contentType: "image/jpeg",
        byteSize: 32_000
      ),
      DiaryAttachment(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        kind: .image,
        fileName: "landscape-table.jpg",
        contentType: "image/jpeg",
        byteSize: 32_000
      ),
      DiaryAttachment(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
        kind: .image,
        fileName: "panorama-river.jpg",
        contentType: "image/jpeg",
        byteSize: 32_000
      ),
      DiaryAttachment(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000004")!,
        kind: .image,
        fileName: "square-dessert.jpg",
        contentType: "image/jpeg",
        byteSize: 32_000
      ),
    ]
    static let mediaEntry = DiaryEntry(
      id: 551,
      author: author,
      content: "세로, 가로, 파노라마 사진을 한 장의 작은 스크랩북처럼 모았어요.",
      createdAt: DebugRelationshipFixtures.timestamp,
      updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(10),
      isMine: true,
      attachments: mediaAttachments,
      commentCount: 2
    )
    static let comments = [
      DiaryComment(
        id: 601,
        author: partner,
        content: "상대방의 긴 댓글도 이름과 시각, 본문이 서로 겹치지 않아야 해요.",
        createdAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(20),
        updatedAt: nil,
        isMine: false
      ),
      DiaryComment(
        id: 602,
        author: author,
        content: "내가 남긴 답장 역시 큰 글자에서 충분한 폭을 사용하고 관리 버튼을 누를 수 있어야 해요.",
        createdAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(30),
        updatedAt: nil,
        isMine: true
      ),
    ]
    static let detail = DiaryEntryDetail(entry: entry, comments: comments)
    static let mediaDetail = DiaryEntryDetail(entry: mediaEntry, comments: comments)

    static func entry(
      _ base: DiaryEntry,
      currentSlot: ParticipantSlot
    ) -> DiaryEntry {
      DiaryEntry(
        id: base.id,
        author: base.author,
        content: base.content,
        createdAt: base.createdAt,
        updatedAt: base.updatedAt,
        isMine: base.author.slot == currentSlot,
        attachments: base.attachments,
        commentCount: base.commentCount
      )
    }

    static func detail(
      _ base: DiaryEntryDetail,
      currentSlot: ParticipantSlot
    ) -> DiaryEntryDetail {
      DiaryEntryDetail(
        entry: entry(base.entry, currentSlot: currentSlot),
        comments: base.comments.map { comment in
          DiaryComment(
            id: comment.id,
            author: comment.author,
            content: comment.content,
            createdAt: comment.createdAt,
            updatedAt: comment.updatedAt,
            isMine: comment.author.slot == currentSlot
          )
        }
      )
    }
  }

  private actor WoorisaiUITestMediaPreviewLoader: PrivateMediaPreviewLoading {
    private var files: [UUID: URL] = [:]
    private var corruptedVideoAttachmentIDs: Set<UUID> = []
    private let corruptsFirstVideoLoad: Bool

    init(corruptsFirstVideoLoad: Bool = false) {
      self.corruptsFirstVideoLoad = corruptsFirstVideoLoad
    }

    func load(_ descriptor: PrivateMediaPreviewDescriptor) async throws
      -> PrivateMediaPreviewLease
    {
      let url: URL
      if let existing = files[descriptor.attachmentID] {
        url = existing
      } else {
        let shouldCorrupt =
          corruptsFirstVideoLoad && !descriptor.isImage
          && corruptedVideoAttachmentIDs.insert(descriptor.attachmentID).inserted
        let data =
          if shouldCorrupt {
            Data(repeating: 0, count: Int(descriptor.byteSize))
          } else {
            try await syntheticData(for: descriptor)
          }
        url = try ProtectedTemporaryMediaPreview.write(data, fileName: descriptor.fileName)
        files[descriptor.attachmentID] = url
      }
      return PrivateMediaPreviewLease(
        token: UUID(),
        attachmentID: descriptor.attachmentID,
        localURL: url,
        fileName: descriptor.fileName,
        contentType: descriptor.contentType,
        byteSize: descriptor.byteSize
      )
    }

    func release(_ lease: PrivateMediaPreviewLease) async {}

    func discard(_ lease: PrivateMediaPreviewLease) async {
      guard files[lease.attachmentID] == lease.localURL else { return }
      files.removeValue(forKey: lease.attachmentID)
      ProtectedTemporaryMediaPreview.remove(lease.localURL)
    }

    func clearSession() async {
      let urls = Array(files.values)
      files.removeAll()
      corruptedVideoAttachmentIDs.removeAll()
      for url in urls {
        ProtectedTemporaryMediaPreview.remove(url)
      }
    }

    private func syntheticData(for descriptor: PrivateMediaPreviewDescriptor) async throws
      -> Data
    {
      guard descriptor.isImage else {
        return try WoorisaiUITestFixtureVideo.mp4Data()
      }

      let fileName = descriptor.fileName.lowercased()
      let size: CGSize
      if fileName.contains("portrait") {
        size = CGSize(width: 360, height: 640)
      } else if fileName.contains("panorama") {
        size = CGSize(width: 960, height: 240)
      } else if fileName.contains("square") {
        size = CGSize(width: 480, height: 480)
      } else {
        size = CGSize(width: 640, height: 360)
      }

      return try await MainActor.run {
        let image = UIGraphicsImageRenderer(size: size).image { context in
          UIColor(red: 0.96, green: 0.70, blue: 0.66, alpha: 1).setFill()
          context.fill(CGRect(origin: .zero, size: size))
          UIColor(red: 0.72, green: 0.84, blue: 0.74, alpha: 1).setFill()
          context.fill(
            CGRect(
              x: size.width * 0.08,
              y: size.height * 0.1,
              width: size.width * 0.84,
              height: size.height * 0.8
            )
          )
          UIColor.white.setFill()
          context.cgContext.fillEllipse(
            in: CGRect(
              x: size.width * 0.38,
              y: size.height * 0.34,
              width: size.width * 0.24,
              height: size.width * 0.24
            )
          )
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
          throw PrivateMediaPreviewError.invalidImage
        }
        return data
      }
    }
  }

  @MainActor
  private enum WoorisaiUITestFixtureImage {
    static func jpegData() -> Data? {
      let size = CGSize(width: 360, height: 640)
      let image = UIGraphicsImageRenderer(size: size).image { context in
        UIColor(red: 0.96, green: 0.70, blue: 0.66, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
        UIColor(red: 0.72, green: 0.84, blue: 0.74, alpha: 1).setFill()
        context.fill(CGRect(x: 36, y: 64, width: 288, height: 512))
      }
      return image.jpegData(compressionQuality: 0.9)
    }
  }

  private enum WoorisaiUITestFixtureVideo {
    private static let base64 = """
      AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAATKbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAE4gAAQAAAQAA
      AAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAA
      A/R0cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAE4gAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAA
      AAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAABOIAAAIAAABAAAAAANsbWRpYQAAACBtZGhk
      AAAAAAAAAAAAAAAAAAAoAAAAyABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAADF21p
      bmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAtdzdGJsAAAAv3N0c2QA
      AAAAAAAAAQAAAK9hdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAACAAIABIAAAASAAAAAAAAAABFUxhdmM2Mi4yOC4xMDEgbGli
      eDI2NAAAAAAAAAAAAAAAGP//AAAANWF2Y0MBZAAK/+EAGGdkAAqscgRJbARAAAADAEAAAAUDxIlhGAEABmjoQ4ksi/34+AAAAAAQ
      cGFzcAAAAAEAAAABAAAAFGJ0cnQAAAAAAAAIyAAAAAAAAAAYc3R0cwAAAAAAAAABAAAAMgAABAAAAAAUc3RzcwAAAAAAAAABAAAA
      AQAAANhjdHRzAAAAAAAAABkAAAABAAAIAAAAAAEAACgAAAAAAQAAEAAAAAADAAAAAAAAAAQAAAQAAAAAAQAAKAAAAAABAAAQAAAA
      AAMAAAAAAAAABAAABAAAAAABAAAoAAAAAAEAABAAAAAAAwAAAAAAAAAEAAAEAAAAAAEAACgAAAAAAQAAEAAAAAADAAAAAAAAAAQA
      AAQAAAAAAQAAKAAAAAABAAAQAAAAAAMAAAAAAAAABAAABAAAAAABAAAUAAAAAAEAAAgAAAAAAQAAAAAAAAABAAAEAAAAABxzdHNj
      AAAAAAAAAAEAAAABAAAAMgAAAAEAAADcc3RzegAAAAAAAAAAAAAAMgAAAtIAAAAOAAAADQAAAA0AAAANAAAADQAAAA0AAAANAAAA
      DQAAAA0AAAAUAAAADQAAAA0AAAANAAAADQAAAA0AAAANAAAADQAAAA0AAAAUAAAADQAAAA0AAAANAAAADQAAAA0AAAANAAAADQAA
      AA0AAAAWAAAADQAAAA0AAAANAAAADQAAAA0AAAANAAAADQAAAA0AAAAXAAAADQAAAA0AAAANAAAADQAAAA0AAAANAAAADQAAAA0A
      AAAZAAAADQAAAA0AAAANAAAAFHN0Y28AAAAAAAAAAQAABPoAAABidWR0YQAAAFptZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGly
      YXBwbAAAAAAAAAAAAAAAAC1pbHN0AAAAJal0b28AAAAdZGF0YQAAAAEAAAAATGF2ZjYyLjEyLjEwMQAAAAhmcmVlAAAFhW1kYXQA
      AAKwBgX//6zcRem95tlIt5Ys2CDZI+7veDI2NCAtIGNvcmUgMTY1IHIzMjIyIGIzNTYwNWEgLSBILjI2NC9NUEVHLTQgQVZDIGNv
      ZGVjIC0gQ29weWxlZnQgMjAwMy0yMDI1IC0gaHR0cDovL3d3dy52aWRlb2xhbi5vcmcveDI2NC5odG1sIC0gb3B0aW9uczogY2Fi
      YWM9MSByZWY9MTYgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDEzMyBtZT11bWggc3VibWU9MTAgcHN5PTEgcHN5X3JkPTEu
      MDA6MC4wMCBtaXhlZF9yZWY9MSBtZV9yYW5nZT0yNCBjaHJvbWFfbWU9MSB0cmVsbGlzPTIgOHg4ZGN0PTEgY3FtPTAgZGVhZHpv
      bmU9MjEsMTEgZmFzdF9wc2tpcD0xIGNocm9tYV9xcF9vZmZzZXQ9LTIgdGhyZWFkcz0xIGxvb2thaGVhZF90aHJlYWRzPTEgc2xp
      Y2VkX3RocmVhZHM9MCBucj0wIGRlY2ltYXRlPTEgaW50ZXJsYWNlZD0wIGJsdXJheV9jb21wYXQ9MCBjb25zdHJhaW5lZF9pbnRy
      YT0wIGJmcmFtZXM9OCBiX3B5cmFtaWQ9MiBiX2FkYXB0PTIgYl9iaWFzPTAgZGlyZWN0PTMgd2VpZ2h0Yj0xIG9wZW5fZ29wPTAg
      d2VpZ2h0cD0yIGtleWludD0yNTAga2V5aW50X21pbj0xMCBzY2VuZWN1dD00MCBpbnRyYV9yZWZyZXNoPTAgcmNfbG9va2FoZWFk
      PTYwIHJjPWNyZiBtYnRyZWU9MSBjcmY9MjguMCBxY29tcD0wLjYwIHFwbWluPTAgcXBtYXg9NjkgcXBzdGVwPTQgaXBfcmF0aW89
      MS40MCBhcT0xOjEuMDAAgAAAABpliIEAAn/+46v4FNWbinK09EjZ90YwqhO/gQAAAApBmgktiCf//quAAAAACUGeEIcQQ/9VwQAA
      AAkBnhgmiG//ZkAAAAAJAZ4YRohv/2ZBAAAACQGeGGaIb/9mQQAAAAkBnhitSG//ZkEAAAAJAZ4YzUhv/2ZBAAAACQGeGO1Ib/9m
      QAAAAAkBnhkNSG//ZkAAAAAQQZoaSTUCAtEymBBP//6rgQAAAAlBniGlxBD/VcAAAAAJAZ4pRaIb/2ZAAAAACQGeKWWiG/9mQQAA
      AAkBnimFohv/ZkEAAAAJAZ4pzJIb/2ZBAAAACQGeKeySG/9mQAAAAAkBnioMkhv/ZkAAAAAJAZ4qLJIb/2ZBAAAAEEGaK2m1AgLa
      0TKYAQS//qsAAAAJQZ4yxLEEP1XAAAAACQGeOmSohv9mQQAAAAkBnjqEqIb/ZkAAAAAJAZ46pKiG/2ZBAAAACQGeOuzSG/9mQQAA
      AAkBnjsM0hv/ZkAAAAAJAZ47LNIb/2ZBAAAACQGeO0zSG/9mQAAAABJBmjyIjUCAtra0TKYABBL//qsAAAAJQZ5D5PEEP1XBAAAA
      CQGeS4Tohv9mQAAAAAkBnkuk6Ib/ZkAAAAAJAZ5LxOiG/2ZBAAAACQGeTAxEhv9mQAAAAAkBnkwsRIb/ZkEAAAAJAZ5MTESG/2ZA
      AAAACQGeTGxEhv9mQQAAABNBmk2orUCAtra2tEymAABBD/6XAAAACUGeVQRMQQ9VwQAAAAkBnlykSiG/ZkEAAAAJAZ5cxEohv2ZA
      AAAACQGeXORKIb9mQAAAAAkBnl0sVIb/ZkEAAAAJAZ5dTFSG/2ZAAAAACQGeXWxUhv9mQAAAAAkBnl2MVIb/ZkEAAAAVQZpeKM1A
      gLa2tra0TKYAAAQ3//5PAAAACUGeZeRcQ79jQQAAAAkBnm3EWiG/ZkAAAAAJAZ5uDGSG/2ZA
      """

    static func mp4Data() throws -> Data {
      let compact = base64.filter { !$0.isWhitespace }
      guard let data = Data(base64Encoded: compact), !data.isEmpty else {
        throw PrivateMediaPreviewError.temporaryFile
      }
      return data
    }
  }

  private struct WoorisaiUITestPresignedMediaUploader: PresignedMediaUploading {
    func put(
      _ data: Data,
      using grant: MediaUploadGrant,
      progress: @escaping @Sendable (Double) -> Void
    ) async throws {
      guard !data.isEmpty, !grant.isExpired() else {
        throw PresignedMediaUploadError.invalidGrant
      }
      progress(0.25)
      await Task.yield()
      try Task.checkCancellation()
      progress(1)
    }

    func put(
      fileAt fileURL: URL,
      byteSize: Int64,
      using grant: MediaUploadGrant,
      progress: @escaping @Sendable (Double) -> Void
    ) async throws {
      let values = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      guard fileURL.isFileURL,
        values.isRegularFile == true,
        values.fileSize.map(Int64.init) == byteSize,
        byteSize > 0,
        !grant.isExpired()
      else {
        throw PresignedMediaUploadError.invalidGrant
      }
      progress(0.25)
      await Task.yield()
      try Task.checkCancellation()
      progress(1)
    }
  }

  private struct InjectedUITestFailure: Error, Sendable {}
#endif
