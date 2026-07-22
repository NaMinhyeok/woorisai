import Foundation
import SwiftUI
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
  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaPreviewStore: PrivateMediaPreviewStore
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
        credentialStore: services.credentialStore
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
    mediaPreviewStore = PrivateMediaPreviewStore(service: services.mediaService)
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
        mediaPreviewStore: mediaPreviewStore
      )
      .task {
        appDelegate.pushCoordinator.attach(notificationModel: notificationModel)
      }
      let privacyProtectedRootView =
        rootView
        .overlay {
          if AppPrivacyCoverPolicy.shouldCover(scenePhase) {
            AppPrivacyCoverView()
          }
        }
        .animation(nil, value: scenePhase)
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

enum AppPrivacyCoverPolicy {
  static func shouldCover(_ scenePhase: ScenePhase) -> Bool {
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

private struct AppPrivacyCoverView: View {
  var body: some View {
    Color(uiColor: .systemBackground)
      .ignoresSafeArea()
      .accessibilityHidden(true)
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
  @State private var topLevelMediaSession: TopLevelMediaSessionCoordinator
  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaPreviewStore: PrivateMediaPreviewStore

  @MainActor
  init(
    loginOptionsModel: LoginOptionsModel,
    authenticationModel: AuthenticationModel,
    relationshipModel: RelationshipModel,
    diaryModel: DiaryModel,
    notificationModel: NotificationModel,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaPreviewStore: PrivateMediaPreviewStore
  ) {
    _loginOptionsModel = State(initialValue: loginOptionsModel)
    _authenticationModel = State(initialValue: authenticationModel)
    _relationshipModel = State(initialValue: relationshipModel)
    _diaryModel = State(initialValue: diaryModel)
    _notificationModel = State(initialValue: notificationModel)
    _topLevelMediaSession = State(
      initialValue: TopLevelMediaSessionCoordinator(
        service: mediaService,
        uploader: mediaUploader
      )
    )
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.mediaPreviewStore = mediaPreviewStore
  }

  var body: some View {
    if let participant = authenticationModel.authenticatedParticipant {
      authenticatedContent(participant: participant)
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
        scoreMediaModel: topLevelMediaSession.relationshipScoreComposer,
        participant: participant,
        onSignOut: signOut,
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
        newEntryMediaModel: topLevelMediaSession.diaryEntryComposer,
        participant: participant,
        onSignOut: signOut,
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
        onSignOut: signOut
      )
      .tabItem {
        Label("설정", systemImage: "gearshape")
      }
      .tag(AuthenticatedTab.settings)
    }
    .disabled(isEndingSession || isProtectedWriteInFlight)
    .overlay {
      if isEndingSession {
        ProgressView("안전하게 나가는 중이에요.")
          .padding()
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
      }
    }
    .task(id: participant.slot.rawValue) {
      notificationModel.authenticatedSessionDidStart()
      consumeNotificationIntents(notificationModel.pendingRefetchIntents)
    }
    .onChange(of: notificationModel.authenticationRequired) { _, required in
      if required { requirePINAgain(for: participant) }
    }
    .onChange(of: notificationModel.pendingRefetchIntents) { _, intents in
      consumeNotificationIntents(intents)
    }
    .onChange(of: isProtectedWriteInFlight) { _, isInFlight in
      if !isInFlight {
        consumeNotificationIntents(notificationModel.pendingRefetchIntents)
      }
    }
    .environment(\.privateMediaPreviewLoader, mediaPreviewStore)
  }

  private var isProtectedWriteInFlight: Bool {
    relationshipModel.scoreSubmissionState == .submitting
      || relationshipModel.commentSubmissionState == .submitting
      || diaryModel.mutationState == .submitting
  }

  private func signOut() {
    guard !isEndingSession else { return }
    isEndingSession = true
    let releaseRejectedScoreSubmission =
      relationshipModel.rejectedMediaMutation == .scoreChange
    let releaseRejectedDiarySubmission =
      diaryModel.rejectedMediaMutation == .createEntry
    notificationModel.discardPendingRefetchIntents()
    relationshipNavigationPath.removeAll()
    diaryNavigationPath.removeAll()
    loginOptionsModel.reset()
    relationshipModel.clear()
    diaryModel.clear()
    Task {
      await Task.yield()
      await prepareTopLevelMediaForSessionEnd(
        releaseRejectedScoreSubmission: releaseRejectedScoreSubmission,
        releaseRejectedDiarySubmission: releaseRejectedDiarySubmission
      )
      await notificationModel.unregisterBeforeSignOut()
      notificationModel.discardPendingRefetchIntents()
      relationshipModel.clear()
      diaryModel.clear()
      await authenticationModel.signOut()
      isEndingSession = false
    }
  }

  private func requirePINAgain(for participant: AuthenticatedParticipant) {
    guard !isEndingSession else { return }
    isEndingSession = true
    let releaseRejectedScoreSubmission =
      relationshipModel.rejectedMediaMutation == .scoreChange
    let releaseRejectedDiarySubmission =
      diaryModel.rejectedMediaMutation == .createEntry
    notificationModel.discardPendingRefetchIntents()
    relationshipNavigationPath.removeAll()
    diaryNavigationPath.removeAll()
    relationshipModel.clear()
    diaryModel.clear()
    Task {
      await Task.yield()
      await prepareTopLevelMediaForSessionEnd(
        releaseRejectedScoreSubmission: releaseRejectedScoreSubmission,
        releaseRejectedDiarySubmission: releaseRejectedDiarySubmission
      )
      await notificationModel.unregisterBeforeSignOut()
      notificationModel.discardPendingRefetchIntents()
      relationshipModel.clear()
      diaryModel.clear()
      await authenticationModel.requirePINAgain(for: participant)
      isEndingSession = false
    }
  }

  private func prepareTopLevelMediaForSessionEnd(
    releaseRejectedScoreSubmission: Bool,
    releaseRejectedDiarySubmission: Bool
  ) async {
    await mediaPreviewStore.clearSession()
    await topLevelMediaSession.prepareForCredentialRemoval(
      releaseRejectedScoreSubmission: releaseRejectedScoreSubmission,
      releaseRejectedDiarySubmission: releaseRejectedDiarySubmission
    )
  }

  private func consumeNotificationIntents(
    _ intents: [NotificationResourceRefetchIntent]
  ) {
    // A path replacement tears down the current destination. Keep the intent buffered while a
    // parent mutation owns READY media so screen cleanup can never race the backend attachment.
    guard !isEndingSession, !isProtectedWriteInFlight else { return }
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
  let participant: AuthenticatedParticipant
  let notificationState: NotificationModel.State
  let canRetryNotifications: Bool
  let onRetryNotifications: @MainActor () -> Void
  let onSignOut: @MainActor () -> Void

  var body: some View {
    NavigationStack {
      List {
        Section("현재 사용자") {
          LabeledContent("이름", value: participant.displayName)
          LabeledContent("참가자", value: "슬롯 \(participant.slot.rawValue)")
        }
        Section("알림") {
          Label(notificationLabel, systemImage: notificationSymbol)
          if canRetryNotifications {
            Button("알림 등록 다시 시도", action: onRetryNotifications)
          }
        }
        Section {
          Button("나가기", role: .destructive, action: onSignOut)
        }
      }
      .navigationTitle("설정")
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
          mediaService: unavailable,
          mediaUploader: mediaUploader,
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
        credentialStore: credentialStore
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

  private actor WoorisaiUITestService: LoginOptionsLoading, CredentialValidating,
    RelationshipServing, DiaryServing
  {
    static let argumentName = "--login-options-ui-test-scenario"
    static let verificationTokenArgumentName = "--login-options-ui-test-token"
    static let activeScenarioFileName = "woorisai-active-ui-test-scenario"

    private enum Scenario: String {
      case adaptiveContent
      case authenticationRejectedThenSuccess
      case failureThenSuccess
      case loading
      case longNames
      case longScoreReason
      case relationship
      case relationshipConflict
      case success
      case unavailableThenSuccess
    }

    private let scenario: Scenario
    private let credentialStore: InMemoryCredentialStore
    private var loginAttemptCount = 0
    private var credentialAttemptCount = 0
    private var scoreCreateAttemptCount = 0

    init?(arguments: [String], credentialStore: InMemoryCredentialStore) {
      guard let scenario = Self.scenario(arguments: arguments) else { return nil }
      self.scenario = scenario
      self.credentialStore = credentialStore
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
      let options = scenario == .adaptiveContent
        ? DebugRelationshipFixtures.longNameOptions
        : DebugRelationshipFixtures.options
      return DebugRelationshipFixtures.authenticatedParticipant(
        slot: credential.slot,
        options: options
      )
    }

    func loadRelationshipScores() async throws -> RelationshipScores {
      scenario == .adaptiveContent
        ? DebugRelationshipFixtures.adaptiveScores
        : DebugRelationshipFixtures.scores
    }

    func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
      DebugRelationshipFixtures.page(
        pageNumber: pageNumber,
        usesAdaptiveContent: scenario == .adaptiveContent,
        usesLongReason: scenario == .longScoreReason
      )
    }

    func createScoreChange(
      _ draft: RelationshipScoreChangeDraft
    ) async throws -> RelationshipScoreChangeCreated {
      scoreCreateAttemptCount += 1
      if scenario == .relationshipConflict, scoreCreateAttemptCount == 1 {
        throw WoorisaiAPIError.conflict
      }
      return DebugRelationshipFixtures.createdChange(draft: draft)
    }

    func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
      let thread: RelationshipScoreThread
      switch scenario {
      case .adaptiveContent:
        thread = DebugRelationshipFixtures.adaptiveThread
      case .longScoreReason:
        thread = DebugRelationshipFixtures.longReasonThread
      default:
        thread = DebugRelationshipFixtures.thread
      }
      guard id == thread.change.id else { throw InjectedUITestFailure() }
      return thread
    }

    func createScoreChangeComment(
      scoreChangeID: Int64,
      draft: RelationshipScoreCommentDraft
    ) async throws -> RelationshipScoreComment {
      DebugRelationshipFixtures.createdComment(content: draft.content)
    }

    func loadDiaryEntries(pageNumber: Int) async throws -> DiaryEntryPage {
      guard scenario == .adaptiveContent else { throw InjectedUITestFailure() }
      return DiaryEntryPage(
        entries: pageNumber == 1 ? [DebugDiaryFixtures.entry] : [],
        pageNumber: pageNumber,
        hasNext: false,
        totalCount: 1
      )
    }

    func createDiaryEntry(_ draft: DiaryEntryCreateDraft) async throws -> DiaryEntry {
      throw InjectedUITestFailure()
    }

    func loadDiaryEntry(id: Int64) async throws -> DiaryEntryDetail {
      guard scenario == .adaptiveContent, id == DebugDiaryFixtures.entry.id else {
        throw InjectedUITestFailure()
      }
      return DebugDiaryFixtures.detail
    }

    func updateDiaryEntry(id: Int64, draft: DiaryEntryUpdateDraft) async throws -> DiaryEntry {
      throw InjectedUITestFailure()
    }

    func deleteDiaryEntry(id: Int64) async throws {
      throw InjectedUITestFailure()
    }

    func createDiaryComment(
      entryID: Int64,
      draft: DiaryCommentDraft
    ) async throws -> DiaryComment {
      throw InjectedUITestFailure()
    }

    func updateDiaryComment(id: Int64, draft: DiaryCommentDraft) async throws -> DiaryComment {
      throw InjectedUITestFailure()
    }

    func deleteDiaryComment(id: Int64) async throws {
      throw InjectedUITestFailure()
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

    static func authenticatedParticipant(
      slot: ParticipantSlot,
      options: [LoginOption] = DebugRelationshipFixtures.options
    ) -> AuthenticatedParticipant {
      let option = options.first { $0.slot == slot.rawValue } ?? options[0]
      return AuthenticatedParticipant(slot: slot, displayName: option.displayName)
    }

    static func page(
      pageNumber: Int,
      usesAdaptiveContent: Bool = false,
      usesLongReason: Bool = false
    ) -> RelationshipScoreChangePage {
      let firstPageChange: RelationshipScoreChange
      if usesAdaptiveContent {
        firstPageChange = adaptiveChange
      } else if usesLongReason {
        firstPageChange = longReasonChange
      } else {
        firstPageChange = change
      }
      return RelationshipScoreChangePage(
        changes: pageNumber == 1 ? [firstPageChange] : [],
        pageNumber: pageNumber,
        hasNext: false,
        totalCount: 1
      )
    }

    static func createdChange(
      draft: RelationshipScoreChangeDraft
    ) -> RelationshipScoreChangeCreated {
      let target: Int
      switch draft.mutation {
      case .target(let value): target = value
      case .delta(let value): target = scores.outgoingScore + value
      }
      let created = RelationshipScoreChange(
        id: 202,
        sourceParticipant: current,
        targetParticipant: partner,
        changedBy: current,
        delta: target - scores.outgoingScore,
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

    static func createdComment(content: String?) -> RelationshipScoreComment {
      RelationshipScoreComment(
        id: 302,
        author: current,
        content: content,
        createdAt: timestamp.addingTimeInterval(20),
        attachments: []
      )
    }
  }

  private enum DebugDiaryFixtures {
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
      content: "긴 한국어 일기 내용이 작은 화면과 큰 글자에서도 카드 밖으로 밀려나지 않고 자연스럽게 이어져야 해요. 우리 둘의 기록은 중간에서 잘리지 않고 상세 화면에서 끝까지 읽을 수 있어야 합니다.",
      createdAt: DebugRelationshipFixtures.timestamp,
      updatedAt: DebugRelationshipFixtures.timestamp.addingTimeInterval(10),
      isMine: true,
      attachments: [],
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
  }

  private struct InjectedUITestFailure: Error, Sendable {}
#endif
