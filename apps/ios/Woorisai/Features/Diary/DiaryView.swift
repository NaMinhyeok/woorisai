import SwiftUI
import WoorisaiAPI

enum DiaryConflictEditorDisposition: Equatable, Sendable {
  case none
  case preserveEntryEditor
  case preserveCommentEditor

  static func resolve(conflict: DiaryModel.Conflict?, visibleEntryID: Int64) -> Self {
    switch conflict {
    case .entry(let entryID) where entryID == visibleEntryID:
      return .preserveEntryEditor
    case .comment(let entryID) where entryID == visibleEntryID:
      return .preserveCommentEditor
    default:
      return .none
    }
  }
}

struct DiaryView: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: DiaryModel
  @State private var newEntryMediaModel: MediaAttachmentComposerModel
  @State private var isCreatingEntry = false
  @State private var newEntryContent = ""
  @Binding private var navigationPath: [Int64]

  private let mediaService: any MediaServing
  private let mediaUploader: any PresignedMediaUploading
  private let mediaSessionCoordinator: TopLevelMediaSessionCoordinator

  let participant: AuthenticatedParticipant
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: DiaryModel,
    navigationPath: Binding<[Int64]>,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaSessionCoordinator: TopLevelMediaSessionCoordinator,
    newEntryMediaModel: MediaAttachmentComposerModel,
    participant: AuthenticatedParticipant,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _newEntryMediaModel = State(initialValue: newEntryMediaModel)
    _navigationPath = navigationPath
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.mediaSessionCoordinator = mediaSessionCoordinator
    self.participant = participant
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    modelObservedContent
  }

  private var navigationContent: some View {
    NavigationStack(path: $navigationPath) {
      listContent
        .navigationTitle("우리 일기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { createEntryToolbar }
        .navigationDestination(for: Int64.self) { entryID in
          DiaryDetailView(
            model: model,
            entryID: entryID,
            mediaService: mediaService,
            mediaUploader: mediaUploader,
            mediaSessionCoordinator: mediaSessionCoordinator,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
    }
    .accessibilityIdentifier("diary.screen")
    .task {
      model.loadIfNeeded()
    }
  }

  @ToolbarContentBuilder
  private var createEntryToolbar: some ToolbarContent {
    ToolbarItem(placement: .topBarTrailing) {
      Button {
        isCreatingEntry = true
      } label: {
        Label("새 일기", systemImage: "square.and.pencil")
      }
      .disabled(model.mutationState == .submitting || !canOpenNewEntryComposer)
      .tint(WoorisaiPalette.coralDark)
      .accessibilityIdentifier("diary.createEntry.open")
    }
  }

  private var composerPresentedContent: some View {
    navigationContent
      .sheet(isPresented: $isCreatingEntry) {
        DiaryEntryComposer(
          title: "새 일기",
          content: $newEntryContent,
          mediaModel: newEntryMediaModel,
          retainedAttachments: [],
          mediaService: mediaService,
          isSubmitting: model.mutationState == .submitting,
          hasDraftChanges: isNewEntryDraftDirty,
          canKeepDraft: true,
          requiresRetryConfirmation: hasUnknownNewEntryOutcome,
          reconciliation: nil,
          inspectionState: model.editorReconciliationState,
          allowsManualRetry: !model.reconciliationContentUnavailable,
          mutationMessage: model.mutationNotice,
          submitTitle: "기록하기",
          onRemoveRetainedAttachment: { _ in },
          onAuthenticationRequired: onAuthenticationRequired,
          onKeepDraft: {
            model.releaseManualRetryDraftProtection(context: .createEntry)
            model.updateLocalDraftProtection(context: .createEntry, isProtected: false)
            isCreatingEntry = false
          },
          onDismissMessage: model.dismissNotices,
          onReloadLatest: inspectUnknownNewEntryOutcome,
          onResolveAsSaved: resolveUnknownNewEntryAsSaved,
          onConfirmManualRetry: allowUnknownNewEntryRetry,
          onAbandonInconclusive: {},
          onDiscard: discardNewEntryDraft,
          onSubmit: submitNewEntry
        )
        .presentationDetents(entryComposerDetents)
        .interactiveDismissDisabled(
          model.mutationState == .submitting || isNewEntryDraftDirty
            || hasUnknownNewEntryOutcome
        )
      }
  }

  private var modelObservedContent: some View {
    composerPresentedContent
      .onAppear {
        syncNewEntryDraftProtection()
      }
      .onChange(of: isNewEntryDraftDirty) { _, _ in
        syncNewEntryDraftProtection()
      }
      .onChange(of: isCreatingEntry) { _, _ in
        syncNewEntryDraftProtection()
      }
      .onChange(of: model.lastCreatedEntryID) { _, entryID in
        guard entryID != nil else { return }
        newEntryMediaModel.consumeReadyUploads()
        newEntryContent = ""
        isCreatingEntry = false
      }
      .onChange(of: newEntryMediaModel.hasAuthenticationFailure) { _, required in
        if required {
          newEntryMediaModel.releaseSubmittedUploadOwnership()
          newEntryMediaModel.clear()
          onAuthenticationRequired()
        }
      }
      .onChange(of: model.authenticationRequired) { _, required in
        if required {
          newEntryMediaModel.releaseSubmittedUploadOwnership()
          newEntryMediaModel.clear()
          onAuthenticationRequired()
        }
      }
      .onChange(of: model.rejectedMediaMutation) { _, rejection in
        if rejection == .createEntry {
          newEntryMediaModel.releaseSubmittedUploadOwnership()
        }
      }
  }

  @ViewBuilder
  private var listContent: some View {
    switch model.listState {
    case .idle, .loading:
      diaryStateShell {
        BrandedStateCard {
          VStack(spacing: WoorisaiSpacing.medium) {
            ProgressView()
              .controlSize(.large)
              .tint(WoorisaiPalette.coral)
              .accessibilityHidden(true)
            Text("우리 일기를 불러오고 있어요.")
              .font(.body.weight(.medium))
              .foregroundStyle(WoorisaiPalette.muted)
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel("일기를 불러오고 있어요.")
          .accessibilityIdentifier("diary.loading")
        }
      }
    case .unavailable:
      listError("일기를 잠시 사용할 수 없어요.", "diary.unavailable")
    case .failed:
      listError("일기를 불러오지 못했어요.", "diary.failed")
    case .loaded:
      diaryList
    }
  }

  private var diaryList: some View {
    WarmBackground {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
          DiaryHero(
            eyebrow: "OUR DIARY",
            title: "우리 일기",
            message: "점수로는 다 담지 못한 오늘의 이야기를 함께 남겨요.",
            symbol: "book.pages.fill"
          )

          quickCreateCard

          if let notice = model.mutationNotice ?? model.listNotice {
            DiaryMutationStatusCard(
              message: notice,
              onDismiss: model.dismissNotices
            )
            .accessibilityIdentifier("diary.notice")
          }

          WoorisaiSectionHeading(
            "차곡차곡 쌓인 이야기",
            detail: model.entries.isEmpty ? nil : "\(model.totalCount)개의 기록",
            symbol: "heart.text.square"
          )
          .padding(.top, WoorisaiSpacing.small)

          if model.entries.isEmpty {
            emptyDiaryCard
          } else {
            ForEach(model.entries) { entry in
              DiaryEntryCard(
                entry: entry,
                mediaService: mediaService,
                onAuthenticationRequired: onAuthenticationRequired
              )
              .accessibilityIdentifier("diary.entry.\(entry.id)")
            }
          }

          if model.hasNextPage {
            Button {
              model.loadNextPage()
            } label: {
              Label("이전 일기 더 보기", systemImage: "arrow.down.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(WoorisaiPalette.coralDark)
                .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.primaryHeight)
                .background(WoorisaiPalette.surface)
                .clipShape(
                  RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
                )
                .overlay {
                  RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
                    .stroke(WoorisaiPalette.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("diary.nextPage")
          }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, WoorisaiSpacing.screenGutter)
        .padding(.top, WoorisaiSpacing.medium)
        .padding(.bottom, WoorisaiSpacing.xLarge)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        await model.refresh()
      }
    }
    .accessibilityIdentifier("diary.loaded")
  }

  private var quickCreateCard: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
            quickCreateCopy
            quickCreateButton
          }
        } else {
          HStack(spacing: WoorisaiSpacing.medium) {
            ParticipantAvatar(name: participant.displayName, size: 42)
            quickCreateCopy
            Spacer(minLength: WoorisaiSpacing.small)
            quickCreateButton
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .overlay(alignment: .top) {
      DiaryPaperTape()
        .offset(y: -8)
    }
  }

  private var quickCreateCopy: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text("\(participant.displayName)님의 오늘은 어땠나요?")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text(isNewEntryDraftDirty ? "작성 중인 이야기가 있어요." : "우리 둘만 보는 기록을 남겨요.")
        .font(.footnote)
        .foregroundStyle(WoorisaiPalette.muted)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var quickCreateButton: some View {
    Button {
      isCreatingEntry = true
    } label: {
      Label(
        isNewEntryDraftDirty ? "이어서 쓰기" : "이야기 쓰기",
        systemImage: isNewEntryDraftDirty ? "pencil.line" : "square.and.pencil"
      )
      .font(.subheadline.weight(.bold))
      .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
      .frame(
        maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil,
        minHeight: WoorisaiControlMetric.minimumTapTarget
      )
      .padding(.horizontal, WoorisaiSpacing.regular)
      .background(WoorisaiPalette.primaryButtonStart, in: Capsule())
    }
    .buttonStyle(.plain)
    .disabled(model.mutationState == .submitting || !canOpenNewEntryComposer)
    .accessibilityIdentifier("diary.createEntry.prompt")
  }

  private var emptyDiaryCard: some View {
    BrandedStateCard {
      VStack(spacing: WoorisaiSpacing.medium) {
        Image(systemName: "heart.text.square")
          .font(.system(size: 32, weight: .semibold))
          .foregroundStyle(WoorisaiPalette.coral)
          .accessibilityHidden(true)
        Text("아직 일기가 없어요")
          .font(.title3.bold())
          .foregroundStyle(WoorisaiPalette.ink)
        Text("지금 나누고 싶은 이야기를 첫 글로 남겨 보세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .multilineTextAlignment(.center)
        Button("첫 이야기 남기기") {
          isCreatingEntry = true
        }
        .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
        .buttonStyle(.bordered)
        .tint(WoorisaiPalette.coralDark)
        .disabled(!canOpenNewEntryComposer)
        .accessibilityIdentifier("diary.empty.create")
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("diary.empty")
    }
  }

  private var entryComposerDetents: Set<PresentationDetent> {
    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
  }

  private var isNewEntryDraftDirty: Bool {
    !WoorisaiTextInput.normalized(newEntryContent).isEmpty
      || !newEntryMediaModel.uploads.isEmpty
      || newEntryMediaModel.isImporting
  }

  private var hasUnknownNewEntryOutcome: Bool {
    model.mutationOutcomeRequiresConfirmation
      && model.unknownMutationContext == .createEntry
  }

  private var canOpenNewEntryComposer: Bool {
    !model.mutationOutcomeRequiresConfirmation || hasUnknownNewEntryOutcome
  }

  private func submitNewEntry() {
    let uploadIDs = newEntryMediaModel.readyUploadIDs
    let accepted = model.createEntry(
      content: newEntryContent,
      mediaUploadIDs: uploadIDs
    )
    if accepted {
      newEntryMediaModel.markReadyUploadsSubmitted()
    }
  }

  private func syncNewEntryDraftProtection() {
    model.updateLocalDraftProtection(
      context: .createEntry,
      isProtected: isCreatingEntry && isNewEntryDraftDirty
    )
  }

  private func discardNewEntryDraft() {
    model.releaseManualRetryDraftProtection(context: .createEntry)
    if model.rejectedMediaMutation == .createEntry {
      newEntryMediaModel.releaseSubmittedUploadOwnership()
    }
    newEntryMediaModel.clear()
    newEntryContent = ""
    isCreatingEntry = false
  }

  private func inspectUnknownNewEntryOutcome() {
    model.reconcileUnknownOutcomeList()
    isCreatingEntry = false
  }

  private func resolveUnknownNewEntryAsSaved() {
    guard model.resolveUnknownOutcomeAsCommitted(context: .createEntry) else { return }
    newEntryMediaModel.consumeReadyUploads()
    newEntryContent = ""
    isCreatingEntry = false
  }

  private func allowUnknownNewEntryRetry() {
    guard model.confirmManualRetryAfterUnknownOutcome(context: .createEntry) else { return }
    newEntryMediaModel.releaseSubmittedUploadOwnership()
  }

  private func diaryStateShell<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      ScrollView {
        VStack(spacing: WoorisaiSpacing.regular) {
          DiaryHero(
            eyebrow: "OUR DIARY",
            title: "우리 일기",
            message: "점수로는 다 담지 못한 오늘의 이야기를 함께 남겨요.",
            symbol: "book.pages.fill"
          )
          content()
        }
        .frame(maxWidth: 680)
        .padding(WoorisaiSpacing.screenGutter)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func listError(_ message: String, _ identifier: String) -> some View {
    diaryStateShell {
      BrandedStateCard {
        VStack(spacing: WoorisaiSpacing.medium) {
          Image(systemName: "book.closed")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(WoorisaiPalette.coral)
            .accessibilityHidden(true)
          Text("일기를 열 수 없어요")
            .font(.title3.bold())
            .foregroundStyle(WoorisaiPalette.ink)
          Text(message)
            .font(.callout)
            .foregroundStyle(WoorisaiPalette.muted)
            .multilineTextAlignment(.center)
          Button("다시 시도") {
            model.reload()
          }
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          .buttonStyle(.borderedProminent)
          .tint(WoorisaiPalette.primaryButtonStart)
          .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
          .accessibilityIdentifier("diary.retry")
        }
        .accessibilityElement(children: .contain)
      }
      .accessibilityIdentifier(identifier)
    }
  }
}
