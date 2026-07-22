import SwiftUI
import WoorisaiAPI

enum DiaryCommentUpdatePolicy {
  static func newlyAppendedCommentID(
    oldIDs: [Int64],
    newIDs: [Int64]
  ) -> Int64? {
    guard newIDs.count > oldIDs.count,
      Array(newIDs.prefix(oldIDs.count)) == oldIDs
    else {
      return nil
    }
    return newIDs.last
  }
}

struct DiaryDetailView: View {
  private enum FocusedField: Hashable {
    case comment
  }

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: DiaryModel
  @State private var entryEditMediaModel: MediaAttachmentComposerModel
  @State private var isEditingEntry = false
  @State private var entryEditContent = ""
  @State private var initialEntryContent = ""
  @State private var entryEditDraftEntryID: Int64?
  @State private var editingComment: DiaryComment?
  @State private var commentEditContent = ""
  @State private var confirmsEntryDeletion = false
  @State private var commentPendingDeletion: DiaryComment?
  @State private var initialEntryAttachmentIDs: [UUID] = []
  @State private var retainedEntryAttachments: [DiaryAttachment] = []
  @State private var hasPositionedInitialComments = false
  @State private var pendingNewCommentID: Int64?
  @FocusState private var focusedField: FocusedField?

  let entryID: Int64
  let onAuthenticationRequired: @MainActor () -> Void
  private let mediaService: any MediaServing
  private let mediaSessionCoordinator: TopLevelMediaSessionCoordinator

  @MainActor
  init(
    model: DiaryModel,
    entryID: Int64,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaSessionCoordinator: TopLevelMediaSessionCoordinator,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    let entryEditMediaModel = MediaAttachmentComposerModel(
      purpose: .diaryEntry,
      service: mediaService,
      uploader: mediaUploader
    )
    _entryEditMediaModel = State(initialValue: entryEditMediaModel)
    self.entryID = entryID
    self.mediaService = mediaService
    self.mediaSessionCoordinator = mediaSessionCoordinator
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    conflictPresentedContent
  }

  @ViewBuilder
  private var stateContent: some View {
    Group {
      switch model.detailState {
      case .idle, .loading:
        detailStateShell(identifier: "diary.detail.loading") {
          BrandedStateCard {
            VStack(spacing: WoorisaiSpacing.medium) {
              ProgressView()
                .controlSize(.large)
                .tint(WoorisaiPalette.coral)
                .accessibilityHidden(true)
              Text("일기를 여는 중이에요.")
                .font(.body.weight(.medium))
                .foregroundStyle(WoorisaiPalette.muted)
            }
            .accessibilityElement(children: .combine)
          }
        }
      case .loaded:
        detailList
      case .notFound:
        detailNotFound
      case .unavailable:
        detailError("일기를 잠시 사용할 수 없어요.", "diary.detail.unavailable")
      case .failed:
        detailError("일기를 불러오지 못했어요.", "diary.detail.failed")
      }
    }
  }

  private var navigationConfiguredContent: some View {
    stateContent
      .navigationTitle("일기 대화")
      .navigationBarTitleDisplayMode(.inline)
      .navigationBarBackButtonHidden(
        model.mutationState == .submitting || hasUnknownOutcomeForEntry
      )
      .task(id: entryID) {
        model.loadDetail(entryID: entryID)
      }
      .onAppear {
        mediaSessionCoordinator.registerTransient(entryEditMediaModel)
      }
      .onDisappear {
        focusedField = nil
        // Inline comment drafts live in DiaryModel. Once the user explicitly leaves this
        // detail, the screen-scoped manual-retry fence is no longer needed to preserve them.
        model.releaseManualRetryDraftProtection(
          context: .createComment(entryID: entryID)
        )
        model.cancelDetailReadForScreenExit(entryID: entryID)
        if model.mutationState != .submitting && !hasUnknownOutcomeForEntry {
          if model.rejectedMediaMutation == .updateEntry(entryID: entryID) {
            entryEditMediaModel.releaseSubmittedUploadOwnership()
          }
          entryEditMediaModel.clear()
          mediaSessionCoordinator.unregisterTransient(entryEditMediaModel)
        }
      }
      .onChange(of: model.selectedEntryID) { oldValue, newValue in
        if oldValue == entryID, newValue == nil, model.mutationNotice == "일기를 삭제했어요." {
          dismiss()
        }
      }
  }

  private var entryEditorPresentedContent: some View {
    navigationConfiguredContent
      .sheet(isPresented: $isEditingEntry) {
        entryEditorContent
      }
      .onChange(of: isEditingEntry) { oldValue, newValue in
        if oldValue, !newValue, !isEntryEditDraftDirty {
          model.releaseManualRetryDraftProtection(context: .updateEntry(entryID: entryID))
          resetEntryEditDraft(clearMedia: true)
        }
        syncEntryEditDraftProtection()
      }
      .onChange(of: isEntryEditDraftDirty, initial: true) { _, _ in
        syncEntryEditDraftProtection()
      }
  }

  private var commentEditorPresentedContent: some View {
    entryEditorPresentedContent
      .sheet(item: $editingComment) { comment in
        commentEditorContent(comment)
      }
      .onChange(of: editingComment?.id) { oldValue, newValue in
        if let oldValue, oldValue != newValue {
          let oldContext = DiaryModel.UnknownMutationContext.updateComment(
            entryID: entryID,
            commentID: oldValue
          )
          model.updateLocalDraftProtection(context: oldContext, isProtected: false)
          model.releaseManualRetryDraftProtection(context: oldContext)
          if newValue == nil { commentEditContent = "" }
        }
        syncCommentEditDraftProtection()
      }
      .onChange(of: commentEditContent, initial: true) { _, _ in
        syncCommentEditDraftProtection()
      }
  }

  private var deletionDialogsContent: some View {
    commentEditorPresentedContent
      .confirmationDialog(
        "이 일기와 댓글을 모두 삭제할까요?",
        isPresented: $confirmsEntryDeletion,
        titleVisibility: .visible
      ) {
        Button("일기 삭제", role: .destructive) {
          model.deleteEntry(entryID: entryID)
        }
        Button("취소", role: .cancel) {}
      }
      .confirmationDialog(
        "이 댓글을 삭제할까요?",
        isPresented: Binding(
          get: { commentPendingDeletion != nil },
          set: { if !$0 { commentPendingDeletion = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("댓글 삭제", role: .destructive) {
          guard let commentPendingDeletion else { return }
          model.deleteComment(entryID: entryID, commentID: commentPendingDeletion.id)
          self.commentPendingDeletion = nil
        }
        Button("취소", role: .cancel) {
          commentPendingDeletion = nil
        }
      }
  }

  private var mutationObservedContent: some View {
    deletionDialogsContent
      .onChange(of: model.lastUpdatedEntryID) { _, updatedID in
        guard updatedID == entryID else { return }
        entryEditMediaModel.consumeReadyUploads()
        isEditingEntry = false
        resetEntryEditDraft(clearMedia: false)
      }
      .onChange(of: entryEditMediaModel.uploads.map(\.id), initial: true) { _, _ in
        syncEntryEditDraftProtection()
      }
      .onChange(of: entryEditMediaModel.isImporting, initial: true) { _, _ in
        syncEntryEditDraftProtection()
      }
      .onChange(of: entryEditMediaModel.hasAuthenticationFailure) { _, required in
        if required {
          entryEditMediaModel.releaseSubmittedUploadOwnership()
          entryEditMediaModel.clear()
          onAuthenticationRequired()
        }
      }
      .onChange(of: model.authenticationRequired) { _, required in
        if required {
          entryEditMediaModel.releaseSubmittedUploadOwnership()
          entryEditMediaModel.clear()
        }
      }
      .onChange(of: model.rejectedMediaMutation) { _, rejection in
        if rejection == .updateEntry(entryID: entryID) {
          entryEditMediaModel.releaseSubmittedUploadOwnership()
        }
      }
      .onChange(of: model.lastConflictEditorInvalidation) { _, conflict in
        switch DiaryConflictEditorDisposition.resolve(
          conflict: conflict,
          visibleEntryID: entryID
        ) {
        case .preserveEntryEditor:
          entryEditMediaModel.releaseSubmittedUploadOwnership()
        case .preserveCommentEditor:
          break
        case .none:
          break
        }
      }
  }

  private var conflictPresentedContent: some View {
    mutationObservedContent
      .alert(
        "최신 일기가 필요해요",
        isPresented: detailConflictBinding
      ) {
        detailConflictReloadButton
      } message: {
        conflictMessage
      }
  }

  private var entryEditorContent: some View {
    DiaryEntryComposer(
      title: "일기 수정",
      content: $entryEditContent,
      mediaModel: entryEditMediaModel,
      retainedAttachments: retainedEntryAttachments,
      mediaService: mediaService,
      isSubmitting: model.mutationState == .submitting,
      hasDraftChanges: isEntryEditDraftDirty,
      canKeepDraft: false,
      requiresRetryConfirmation: hasUnknownEntryEditOutcome,
      reconciliation: entryEditReconciliation,
      inspectionState: model.editorReconciliationState,
      allowsManualRetry: entryEditReconciliation?.allowsManualRetry ?? false,
      mutationMessage: model.mutationNotice,
      submitTitle: "수정하기",
      onRemoveRetainedAttachment: { attachmentID in
        removeRetainedAttachment(attachmentID)
      },
      onAuthenticationRequired: onAuthenticationRequired,
      onKeepDraft: {
        isEditingEntry = false
      },
      onDismissMessage: {
        model.dismissNotices()
      },
      onReloadLatest: {
        reloadDetailPreservingEditor()
      },
      onResolveAsSaved: {
        resolveUnknownEntryEditAsSaved()
      },
      onConfirmManualRetry: {
        allowUnknownEntryEditRetry()
      },
      onAbandonInconclusive: {
        abandonUnknownEntryEdit()
      },
      onDiscard: {
        discardEntryEditDraft()
      },
      onSubmit: {
        submitEntryEdit()
      }
    )
    .presentationDetents(entryEditorDetents)
    .interactiveDismissDisabled(
      model.mutationState == .submitting || isEntryEditDraftDirty
        || hasUnknownEntryEditOutcome
    )
    .alert(
      "최신 일기가 필요해요",
      isPresented: entryEditorConflictBinding
    ) {
      editorConflictReloadButton
    } message: {
      conflictMessage
    }
  }

  private func commentEditorContent(_ comment: DiaryComment) -> some View {
    DiaryCommentEditor(
      comment: comment,
      content: $commentEditContent,
      isSubmitting: model.mutationState == .submitting,
      requiresRetryConfirmation: hasUnknownCommentEditOutcome(commentID: comment.id),
      reconciliation: commentReconciliation(for: comment),
      inspectionState: model.editorReconciliationState,
      allowsManualRetry: commentReconciliation(for: comment)?.allowsManualRetry ?? false,
      mutationMessage: model.mutationNotice,
      onCancel: {
        let context = DiaryModel.UnknownMutationContext.updateComment(
          entryID: entryID,
          commentID: comment.id
        )
        model.updateLocalDraftProtection(context: context, isProtected: false)
        model.releaseManualRetryDraftProtection(context: context)
        commentEditContent = ""
        editingComment = nil
      },
      onDismissMessage: {
        model.dismissNotices()
      },
      onReloadLatest: {
        reloadDetailPreservingEditor()
      },
      onResolveAsSaved: {
        resolveUnknownCommentEditAsSaved()
      },
      onConfirmManualRetry: {
        allowUnknownCommentEditRetry()
      },
      onAbandonInconclusive: {
        abandonUnknownCommentEdit()
      },
      onSubmit: {
        model.updateComment(
          entryID: entryID,
          commentID: comment.id,
          content: commentEditContent
        )
      }
    )
    .presentationDetents(commentEditorDetents)
    .interactiveDismissDisabled(
      model.mutationState == .submitting || commentEditContent != comment.content
        || hasUnknownCommentEditOutcome(commentID: comment.id)
    )
    .alert(
      "최신 일기가 필요해요",
      isPresented: commentEditorConflictBinding
    ) {
      editorConflictReloadButton
    } message: {
      conflictMessage
    }
  }

  private var entryEditorConflictBinding: Binding<Bool> {
    Binding(
      get: {
        isEditingEntry && model.conflict == .entry(entryID: entryID)
      },
      set: { isPresented in
        dismissConflictWhenNeeded(isPresented)
      }
    )
  }

  private var commentEditorConflictBinding: Binding<Bool> {
    Binding(
      get: {
        editingComment != nil && model.conflict == .comment(entryID: entryID)
      },
      set: { isPresented in
        dismissConflictWhenNeeded(isPresented)
      }
    )
  }

  private var detailConflictBinding: Binding<Bool> {
    Binding(
      get: {
        !isEditingEntry && editingComment == nil && model.conflict != nil
      },
      set: { isPresented in
        dismissConflictWhenNeeded(isPresented)
      }
    )
  }

  private var editorConflictReloadButton: some View {
    Button("최신 내용 불러오기") {
      model.reloadAfterConflict(preservingVisibleContent: true)
    }
  }

  private var detailConflictReloadButton: some View {
    Button("최신 내용 불러오기") {
      model.reloadAfterConflict(preservingVisibleContent: false)
    }
  }

  private var conflictMessage: Text {
    Text("다른 변경과 겹쳐 저장하지 못했습니다. 작성 중인 내용은 남겨 두고 최신 내용을 불러옵니다.")
  }

  private func dismissConflictWhenNeeded(_ isPresented: Bool) {
    if !isPresented, model.conflict != nil {
      model.dismissConflict()
    }
  }

  private var detailList: some View {
    WarmBackground {
      ScrollViewReader { proxy in
        ScrollView {
          if let detail = model.selectedDetail {
            LazyVStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
              DiaryHero(
                eyebrow: "DIARY TALK",
                title: "이 이야기에 대한 대화",
                message: "함께 남긴 순간에 천천히 답장을 건네 보세요.",
                symbol: "bubble.left.and.text.bubble.right.fill"
              )

              diaryOriginCard(detail.entry)

              WoorisaiSectionHeading(
                "둘만의 대화",
                detail: "댓글 \(detail.comments.count)",
                symbol: "bubble.left.and.bubble.right.fill"
              )
              .padding(.top, WoorisaiSpacing.small)

              if chronologicalComments.isEmpty {
                emptyCommentsCard
              } else {
                ForEach(chronologicalComments) { comment in
                  DiaryCommentBubble(
                    comment: comment,
                    isMutationBlocked: model.mutationState == .submitting
                      || model.mutationOutcomeRequiresConfirmation,
                    onEdit: {
                      focusedField = nil
                      commentEditContent = comment.content
                      editingComment = comment
                    },
                    onDelete: {
                      commentPendingDeletion = comment
                    }
                  )
                  .id(comment.id)
                  .accessibilityIdentifier("diary.comment.\(comment.id)")
                }
              }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, WoorisaiSpacing.screenGutter)
            .padding(.top, WoorisaiSpacing.medium)
            .padding(.bottom, WoorisaiSpacing.xLarge)
            .frame(maxWidth: .infinity)
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
          await model.refreshDetail(entryID: entryID)
        }
        .task(id: entryID) {
          await Task.yield()
          if let lastID = chronologicalComments.last?.id {
            proxy.scrollTo(lastID, anchor: .bottom)
          }
          hasPositionedInitialComments = true
        }
        .onChange(of: chronologicalComments.map(\.id)) { oldIDs, newIDs in
          if let pendingNewCommentID, !newIDs.contains(pendingNewCommentID) {
            self.pendingNewCommentID = nil
          }
          guard hasPositionedInitialComments,
            let newID = DiaryCommentUpdatePolicy.newlyAppendedCommentID(
              oldIDs: oldIDs,
              newIDs: newIDs
            )
          else {
            return
          }
          if model.mutationNotice == "댓글을 남겼어요." {
            pendingNewCommentID = nil
            scrollToComment(newID, using: proxy)
          } else {
            pendingNewCommentID = newID
          }
        }
        .overlay(alignment: .bottomTrailing) {
          if let pendingNewCommentID {
            Button {
              scrollToComment(pendingNewCommentID, using: proxy)
              self.pendingNewCommentID = nil
            } label: {
              Label("새 댓글 보기", systemImage: "arrow.down.circle.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
                .padding(.horizontal, WoorisaiSpacing.medium)
                .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
                .background(WoorisaiPalette.coralDark, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(WoorisaiSpacing.screenGutter)
            .accessibilityIdentifier("diary.comments.jumpToNew")
          }
        }
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      commentComposerBar
    }
    .onChange(of: model.mutationNotice) { _, notice in
      if notice == "댓글을 남겼어요." {
        focusedField = nil
      }
      if notice == "일기를 수정했어요." {
        isEditingEntry = false
      }
      if notice == "댓글을 수정했어요." {
        commentEditContent = ""
        editingComment = nil
      }
    }
    .accessibilityIdentifier("diary.detail.loaded")
  }

  private var chronologicalComments: [DiaryComment] {
    // The API adapter rejects non-chronological detail responses, and model mutations preserve
    // that order. Re-sorting here would otherwise run for every observable draft keystroke.
    model.selectedDetail?.comments ?? []
  }

  private func scrollToComment(_ commentID: Int64, using proxy: ScrollViewProxy) {
    if reduceMotion {
      proxy.scrollTo(commentID, anchor: .bottom)
    } else {
      withAnimation(.easeOut(duration: 0.22)) {
        proxy.scrollTo(commentID, anchor: .bottom)
      }
    }
  }

  private var emptyCommentsCard: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.medium) {
      VStack(spacing: WoorisaiSpacing.small) {
        Image(systemName: "bubble.left")
          .font(.title2)
          .foregroundStyle(WoorisaiPalette.sage)
          .accessibilityHidden(true)
        Text("아직 댓글이 없어요.")
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.ink)
        Text("아래에서 먼저 다정한 이야기를 건네 보세요.")
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.muted)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(WoorisaiSpacing.large)
    }
    .accessibilityIdentifier("diary.comments.empty")
  }

  private func diaryOriginCard(_ entry: DiaryEntry) -> some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
        diaryOriginHeader(entry)

        Text(entry.content)
          .font(.body)
          .foregroundStyle(WoorisaiPalette.ink)
          .lineSpacing(5)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)

        if !entry.attachments.isEmpty {
          DiaryAttachmentGallery(
            attachments: entry.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        if entry.isMine {
          Divider()
            .overlay(WoorisaiPalette.line)
          if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: WoorisaiSpacing.small) {
              diaryActionButtons(entry)
            }
          } else {
            HStack(spacing: WoorisaiSpacing.medium) {
              diaryActionButtons(entry)
            }
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .overlay(alignment: .top) {
      DiaryPaperTape()
        .offset(y: -8)
    }
    .overlay {
      RoundedRectangle(cornerRadius: WoorisaiRadius.large, style: .continuous)
        .stroke(
          entry.isMine ? WoorisaiPalette.coral.opacity(0.24) : WoorisaiPalette.line,
          lineWidth: 1
        )
    }
    .padding(.top, WoorisaiSpacing.small)
  }

  @ViewBuilder
  private func diaryOriginHeader(_ entry: DiaryEntry) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        ParticipantAvatar(name: entry.author.displayName, size: 42)
        diaryOriginIdentity(entry)
        if entry.updatedAt != nil {
          Text("수정됨")
            .font(.caption2)
            .foregroundStyle(WoorisaiPalette.muted)
        }
      }
    } else {
      HStack(alignment: .top, spacing: WoorisaiSpacing.medium) {
        ParticipantAvatar(name: entry.author.displayName, size: 42)
        diaryOriginIdentity(entry)
        Spacer(minLength: 0)
        if entry.updatedAt != nil {
          Text("수정됨")
            .font(.caption2)
            .foregroundStyle(WoorisaiPalette.muted)
        }
      }
    }
  }

  private func diaryOriginIdentity(_ entry: DiaryEntry) -> some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      HStack(spacing: WoorisaiSpacing.small) {
        Text(entry.author.displayName)
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if entry.isMine {
          Text("내 기록")
            .font(.caption2.bold())
            .foregroundStyle(WoorisaiPalette.coralDark)
            .padding(.horizontal, WoorisaiSpacing.small)
            .padding(.vertical, WoorisaiSpacing.xSmall)
            .background(WoorisaiPalette.coralSoft, in: Capsule())
        }
      }
      Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
    }
  }

  @ViewBuilder
  private func diaryActionButtons(_ entry: DiaryEntry) -> some View {
    Button {
      beginEditing(entry)
    } label: {
      Label("일기 수정", systemImage: "pencil")
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
    }
    .buttonStyle(.bordered)
    .tint(WoorisaiPalette.coralDark)
    .disabled(
      model.mutationState == .submitting || model.mutationOutcomeRequiresConfirmation
    )
    .accessibilityIdentifier("diary.entry.edit")

    Button(role: .destructive) {
      confirmsEntryDeletion = true
    } label: {
      Label("일기 삭제", systemImage: "trash")
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
    }
    .buttonStyle(.bordered)
    .disabled(
      model.mutationState == .submitting || model.mutationOutcomeRequiresConfirmation
    )
    .accessibilityIdentifier("diary.entry.delete")
  }

  private var commentComposerBar: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      if let mutationNotice = model.mutationNotice {
        DiaryMutationStatusCard(
          message: mutationNotice,
          onDismiss: model.dismissNotices
        )
        .accessibilityIdentifier("diary.detail.notice")
      }

      if hasUnknownInlineOutcome {
        DiaryUnknownOutcomeRecovery(
          inspectionState: model.editorReconciliationState,
          allowsResolveAsSaved: true,
          allowsManualRetry: !model.reconciliationContentUnavailable,
          onReloadLatest: reloadDetailPreservingEditor,
          onResolveAsSaved: resolveUnknownInlineMutationAsSaved,
          onConfirmManualRetry: allowUnknownInlineMutationRetry,
          onAbandonInconclusive: {}
        )
      }

      HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
        Text("댓글 달기")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(WoorisaiPalette.ink)
        Spacer(minLength: WoorisaiSpacing.small)
        Text("\(commentCodePointCount)/\(DiaryCommentDraft.maximumContentCharacterCount)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(
            commentCodePointCount > DiaryCommentDraft.maximumContentCharacterCount
              ? WoorisaiPalette.error : WoorisaiPalette.muted
          )
      }

      if dynamicTypeSize.isAccessibilitySize {
        VStack(spacing: WoorisaiSpacing.small) {
          commentInput
          HStack(spacing: WoorisaiSpacing.small) {
            if focusedField == .comment {
              KeyboardDismissButton {
                focusedField = nil
              }
            }
            commentSubmitButton
          }
        }
      } else {
        HStack(alignment: .bottom, spacing: WoorisaiSpacing.small) {
          commentInput
          if focusedField == .comment {
            KeyboardDismissButton {
              focusedField = nil
            }
          }
          commentSubmitButton
        }
      }
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.small)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider()
        .overlay(WoorisaiPalette.line)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("diary.comment.composer")
  }

  private var commentInput: some View {
    TextField("이 일기에 답장을 남겨 보세요", text: commentContentBinding, axis: .vertical)
      .lineLimit(1...4)
      .focused($focusedField, equals: .comment)
      .foregroundStyle(WoorisaiPalette.ink)
      .tint(WoorisaiPalette.coralDark)
      .padding(.horizontal, WoorisaiSpacing.medium)
      .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
      .background(WoorisaiPalette.field)
      .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
          .stroke(WoorisaiPalette.line, lineWidth: 1)
      }
      .accessibilityIdentifier("diary.comment.input")
      .disabled(isInlineDraftEditingLocked)
  }

  private var commentSubmitButton: some View {
    Button {
      focusedField = nil
      model.createComment(entryID: entryID, content: commentContent)
    } label: {
      Group {
        if model.mutationState == .submitting {
          ProgressView()
            .tint(.white)
        } else {
          Image(systemName: "arrow.up")
            .font(.body.weight(.bold))
            .foregroundStyle(.white)
        }
      }
      .frame(
        width: WoorisaiControlMetric.minimumTapTarget,
        height: WoorisaiControlMetric.minimumTapTarget
      )
      .background(
        commentCanSubmit
          ? WoorisaiPalette.primaryButtonStart : WoorisaiPalette.primaryButtonDisabled,
        in: Circle()
      )
    }
    .buttonStyle(.plain)
    .disabled(!commentCanSubmit || model.mutationState == .submitting)
    .accessibilityLabel(model.mutationState == .submitting ? "댓글 저장 중" : "댓글 남기기")
    .accessibilityValue(commentSubmitAccessibilityValue)
    .accessibilityIdentifier("diary.comment.create")
  }

  private var commentCanSubmit: Bool {
    !WoorisaiTextInput.normalized(commentContent).isEmpty
      && commentCodePointCount <= DiaryCommentDraft.maximumContentCharacterCount
      && !model.mutationOutcomeRequiresConfirmation
  }

  private var isInlineDraftEditingLocked: Bool {
    SubmittedDraftEditingPolicy.isLocked(
      isSubmitting: model.mutationState == .submitting,
      requiresOutcomeConfirmation: hasUnknownInlineOutcome
    )
  }

  private var hasUnknownOutcomeForEntry: Bool {
    guard model.mutationOutcomeRequiresConfirmation,
      let context = model.unknownMutationContext
    else { return false }
    switch context {
    case .updateEntry(let contextEntryID), .deleteEntry(let contextEntryID),
      .createComment(let contextEntryID), .updateComment(let contextEntryID, _),
      .deleteComment(let contextEntryID, _):
      return contextEntryID == entryID
    case .createEntry:
      return false
    }
  }

  private var hasUnknownEntryEditOutcome: Bool {
    model.mutationOutcomeRequiresConfirmation
      && model.unknownMutationContext == .updateEntry(entryID: entryID)
  }

  private func hasUnknownCommentEditOutcome(commentID: Int64) -> Bool {
    model.mutationOutcomeRequiresConfirmation
      && model.unknownMutationContext
        == .updateComment(entryID: entryID, commentID: commentID)
  }

  private var hasUnknownInlineOutcome: Bool {
    guard model.mutationOutcomeRequiresConfirmation,
      let context = model.unknownMutationContext
    else { return false }
    return isInlineUnknownContext(context)
  }

  private func isInlineUnknownContext(_ context: DiaryModel.UnknownMutationContext) -> Bool {
    switch context {
    case .deleteEntry(let contextEntryID), .createComment(let contextEntryID),
      .deleteComment(let contextEntryID, _):
      return contextEntryID == entryID
    case .createEntry, .updateEntry, .updateComment:
      return false
    }
  }

  private var commentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(commentContent)
  }

  private var commentSubmitAccessibilityValue: String {
    if model.mutationState == .submitting {
      return "저장 중"
    }
    if model.mutationOutcomeRequiresConfirmation {
      return "이전 저장 결과를 먼저 확인해야 해요"
    }
    if WoorisaiTextInput.normalized(commentContent).isEmpty {
      return "댓글을 입력하세요"
    }
    if commentCodePointCount > DiaryCommentDraft.maximumContentCharacterCount {
      return "댓글이 최대 글자 수를 넘었어요"
    }
    return "입력한 댓글 저장 가능"
  }

  private var commentContent: String {
    model.commentDraft(entryID: entryID)
  }

  private var commentContentBinding: Binding<String> {
    Binding(
      get: { model.commentDraft(entryID: entryID) },
      set: { model.updateCommentDraft(entryID: entryID, content: $0) }
    )
  }

  private var isEntryEditDraftDirty: Bool {
    guard entryEditDraftEntryID == entryID else { return false }
    return entryEditContent != initialEntryContent
      || retainedEntryAttachments.map(\.id) != initialEntryAttachmentIDs
      || !entryEditMediaModel.uploads.isEmpty
      || entryEditMediaModel.isImporting
  }

  private func syncEntryEditDraftProtection() {
    let context = DiaryModel.UnknownMutationContext.updateEntry(entryID: entryID)
    let isProtected = isEditingEntry && isEntryEditDraftDirty
    model.updateLocalDraftProtection(context: context, isProtected: isProtected)
    if !isProtected {
      model.releaseManualRetryDraftProtection(context: context)
    }
  }

  private func syncCommentEditDraftProtection() {
    guard let editingComment else { return }
    let context = DiaryModel.UnknownMutationContext.updateComment(
      entryID: entryID,
      commentID: editingComment.id
    )
    let isProtected = commentEditContent != editingComment.content
    model.updateLocalDraftProtection(context: context, isProtected: isProtected)
    if !isProtected {
      model.releaseManualRetryDraftProtection(context: context)
    }
  }

  private var entryEditReconciliation: DiaryReconciliationPresentation? {
    let title: String
    if model.lastConflictEditorInvalidation == .entry(entryID: entryID) {
      title = "서버의 최신 일기"
    } else if hasUnknownEntryEditOutcome,
      model.editorReconciliationState != .idle
    {
      title = "저장 여부를 확인한 최신 일기"
    } else {
      return nil
    }
    return DiaryReconciliationPresentation(
      title: title,
      latestServerContent: reconciledContent(model.selectedDetail?.entry.content),
      latestServerAttachments: reconciledAttachments(model.selectedDetail?.entry.attachments),
      state: model.editorReconciliationState,
      allowsResolveAsSaved: latestEntryMatchesSubmittedEdit,
      allowsManualRetry: latestEntryMatchesOriginalEdit
    )
  }

  private func commentReconciliation(
    for comment: DiaryComment
  ) -> DiaryReconciliationPresentation? {
    let title: String
    if model.lastConflictEditorInvalidation == .comment(entryID: entryID) {
      title = "서버의 최신 댓글"
    } else if hasUnknownCommentEditOutcome(commentID: comment.id),
      model.editorReconciliationState != .idle
    {
      title = "저장 여부를 확인한 최신 댓글"
    } else {
      return nil
    }
    let latestComment = model.selectedDetail?.comments.first { $0.id == comment.id }
    return DiaryReconciliationPresentation(
      title: title,
      latestServerContent: reconciledContent(latestComment?.content),
      latestServerAttachments: nil,
      state: model.editorReconciliationState,
      allowsResolveAsSaved: latestCommentMatchesSubmittedEdit(latestComment),
      allowsManualRetry: latestCommentMatchesOriginalEdit(latestComment)
    )
  }

  private func reconciledContent(_ content: String?) -> String? {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable
    else { return nil }
    return content
  }

  private func reconciledAttachments(
    _ attachments: [DiaryAttachment]?
  ) -> [DiaryAttachment]? {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable
    else { return nil }
    return attachments
  }

  private var latestEntryMatchesSubmittedEdit: Bool {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable,
      let entry = model.selectedDetail?.entry,
      case .updateEntry(
        let submittedEntryID,
        let submittedContent,
        let submittedAttachmentIDs,
        let originalContent,
        let originalAttachmentIDs,
        let originalRevision
      ) = model.submittedMutationSnapshot,
      submittedEntryID == entryID,
      let originalContent,
      let originalAttachmentIDs,
      let originalRevision,
      revision(of: entry) != originalRevision
    else { return false }
    return DiaryReconciliationMatcher.entryMatches(
      serverContent: entry.content,
      serverAttachmentIDs: entry.attachments.map(\.id),
      expectedContent: submittedContent ?? originalContent,
      expectedAttachmentIDs: submittedAttachmentIDs ?? originalAttachmentIDs
    )
  }

  private var latestEntryMatchesOriginalEdit: Bool {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable,
      let entry = model.selectedDetail?.entry,
      case .updateEntry(
        let submittedEntryID,
        _,
        _,
        let originalContent,
        let originalAttachmentIDs,
        let originalRevision
      ) = model.submittedMutationSnapshot,
      submittedEntryID == entryID,
      let originalContent,
      let originalAttachmentIDs,
      let originalRevision,
      revision(of: entry) == originalRevision
    else { return false }
    return DiaryReconciliationMatcher.entryMatches(
      serverContent: entry.content,
      serverAttachmentIDs: entry.attachments.map(\.id),
      expectedContent: originalContent,
      expectedAttachmentIDs: originalAttachmentIDs
    )
  }

  private func latestCommentMatchesSubmittedEdit(_ comment: DiaryComment?) -> Bool {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable,
      let comment,
      case .updateComment(
        let submittedEntryID,
        let submittedCommentID,
        let submittedContent,
        _,
        let originalRevision
      ) = model.submittedMutationSnapshot,
      submittedEntryID == entryID,
      submittedCommentID == comment.id,
      let originalRevision,
      revision(of: comment) != originalRevision
    else { return false }
    return DiaryReconciliationMatcher.commentMatches(
      serverContent: comment.content,
      expectedContent: submittedContent
    )
  }

  private func latestCommentMatchesOriginalEdit(_ comment: DiaryComment?) -> Bool {
    guard model.editorReconciliationState == .loaded,
      !model.reconciliationContentUnavailable,
      let comment,
      case .updateComment(
        let submittedEntryID,
        let submittedCommentID,
        _,
        let originalContent,
        let originalRevision
      ) = model.submittedMutationSnapshot,
      submittedEntryID == entryID,
      submittedCommentID == comment.id,
      let originalContent,
      let originalRevision,
      revision(of: comment) == originalRevision
    else { return false }
    return DiaryReconciliationMatcher.commentMatches(
      serverContent: comment.content,
      expectedContent: originalContent
    )
  }

  private func revision(of entry: DiaryEntry) -> DiaryModel.MutationRevision {
    DiaryModel.MutationRevision(createdAt: entry.createdAt, updatedAt: entry.updatedAt)
  }

  private func revision(of comment: DiaryComment) -> DiaryModel.MutationRevision {
    DiaryModel.MutationRevision(createdAt: comment.createdAt, updatedAt: comment.updatedAt)
  }

  private func reloadDetailPreservingEditor() {
    if hasUnknownOutcomeForEntry {
      model.reconcileUnknownOutcome(entryID: entryID)
    } else {
      model.loadDetail(entryID: entryID, preservingVisibleContent: true)
    }
  }

  private func resolveUnknownEntryEditAsSaved() {
    guard entryEditReconciliation?.allowsResolveAsSaved == true,
      model.resolveUnknownOutcomeAsCommitted(context: .updateEntry(entryID: entryID))
    else {
      return
    }
    entryEditMediaModel.consumeReadyUploads()
    isEditingEntry = false
    resetEntryEditDraft(clearMedia: false)
  }

  private func allowUnknownEntryEditRetry() {
    guard entryEditReconciliation?.allowsManualRetry == true,
      model.confirmManualRetryAfterUnknownOutcome(context: .updateEntry(entryID: entryID))
    else { return }
    entryEditMediaModel.releaseSubmittedUploadOwnership()
  }

  private func abandonUnknownEntryEdit() {
    guard entryEditReconciliation?.allowsResolveAsSaved == false,
      entryEditReconciliation?.allowsManualRetry == false,
      model.abandonInconclusiveUnknownOutcome(context: .updateEntry(entryID: entryID))
    else { return }
    // The unknown request may have attached these uploads before another write won. Do not
    // issue a destructive discard for media whose attachment outcome cannot be proven.
    entryEditMediaModel.consumeReadyUploads()
    model.updateLocalDraftProtection(
      context: .updateEntry(entryID: entryID),
      isProtected: false
    )
    isEditingEntry = false
    resetEntryEditDraft(clearMedia: false)
  }

  private func resolveUnknownCommentEditAsSaved() {
    guard let commentID = editingComment?.id,
      let currentComment = editingComment,
      commentReconciliation(for: currentComment)?.allowsResolveAsSaved == true,
      model.resolveUnknownOutcomeAsCommitted(
        context: .updateComment(entryID: entryID, commentID: commentID)
      )
    else { return }
    commentEditContent = ""
    editingComment = nil
  }

  private func allowUnknownCommentEditRetry() {
    guard let editingComment,
      commentReconciliation(for: editingComment)?.allowsManualRetry == true
    else { return }
    let commentID = editingComment.id
    _ = model.confirmManualRetryAfterUnknownOutcome(
      context: .updateComment(entryID: entryID, commentID: commentID)
    )
  }

  private func abandonUnknownCommentEdit() {
    guard let editingComment,
      let reconciliation = commentReconciliation(for: editingComment),
      !reconciliation.allowsResolveAsSaved,
      !reconciliation.allowsManualRetry,
      model.abandonInconclusiveUnknownOutcome(
        context: .updateComment(entryID: entryID, commentID: editingComment.id)
      )
    else { return }
    model.updateLocalDraftProtection(
      context: .updateComment(entryID: entryID, commentID: editingComment.id),
      isProtected: false
    )
    commentEditContent = ""
    self.editingComment = nil
  }

  private func resolveUnknownInlineMutationAsSaved() {
    guard let context = model.unknownMutationContext,
      isInlineUnknownContext(context),
      model.resolveUnknownOutcomeAsCommitted(context: context)
    else { return }
    switch context {
    case .createComment(let contextEntryID) where contextEntryID == entryID:
      model.discardCommentDraft(entryID: entryID)
    case .deleteEntry(let contextEntryID) where contextEntryID == entryID:
      model.reload()
      dismiss()
    case .deleteComment:
      break
    case .createEntry, .updateEntry, .deleteEntry, .createComment, .updateComment:
      break
    }
  }

  private func allowUnknownInlineMutationRetry() {
    guard let context = model.unknownMutationContext,
      isInlineUnknownContext(context)
    else { return }
    _ = model.confirmManualRetryAfterUnknownOutcome(context: context)
  }

  private func beginEditing(_ entry: DiaryEntry) {
    focusedField = nil
    if entryEditDraftEntryID != entry.id {
      resetEntryEditDraft(clearMedia: true)
      entryEditDraftEntryID = entry.id
      initialEntryContent = entry.content
      entryEditContent = entry.content
      initialEntryAttachmentIDs = entry.attachments.map(\.id)
      retainedEntryAttachments = entry.attachments
      entryEditMediaModel.setExistingKinds(
        entry.attachments.map { $0.kind == .image ? .image : .video }
      )
    }
    isEditingEntry = true
  }

  private func removeRetainedAttachment(_ attachmentID: UUID) {
    retainedEntryAttachments.removeAll { $0.id == attachmentID }
    entryEditMediaModel.setExistingKinds(
      retainedEntryAttachments.map { $0.kind == .image ? .image : .video }
    )
  }

  private func submitEntryEdit() {
    let uploadIDs = entryEditMediaModel.readyUploadIDs
    let accepted = model.updateEntry(
      entryID: entryID,
      content: entryEditContent,
      attachments: entryAttachmentUpdate(newUploadIDs: uploadIDs)
    )
    if accepted {
      entryEditMediaModel.markReadyUploadsSubmitted()
    }
  }

  private func discardEntryEditDraft() {
    let context = DiaryModel.UnknownMutationContext.updateEntry(entryID: entryID)
    model.updateLocalDraftProtection(context: context, isProtected: false)
    model.releaseManualRetryDraftProtection(context: context)
    if model.rejectedMediaMutation == .updateEntry(entryID: entryID) {
      entryEditMediaModel.releaseSubmittedUploadOwnership()
    }
    resetEntryEditDraft(clearMedia: true)
    isEditingEntry = false
  }

  private func resetEntryEditDraft(clearMedia: Bool) {
    if clearMedia {
      entryEditMediaModel.clear()
    }
    entryEditMediaModel.setExistingKinds([])
    entryEditDraftEntryID = nil
    entryEditContent = ""
    initialEntryContent = ""
    retainedEntryAttachments = []
    initialEntryAttachmentIDs = []
  }

  private func entryAttachmentUpdate(newUploadIDs: [UUID]) -> DiaryAttachmentUpdate {
    let retainedIDs = retainedEntryAttachments.map(\.id)
    if retainedIDs == initialEntryAttachmentIDs, newUploadIDs.isEmpty {
      return .preserve
    }
    return .replace(retainedIDs + newUploadIDs)
  }

  private func detailStateShell<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      ScrollView {
        VStack(spacing: WoorisaiSpacing.regular) {
          DiaryHero(
            eyebrow: "DIARY TALK",
            title: "이 이야기에 대한 대화",
            message: "함께 남긴 순간에 천천히 답장을 건네 보세요.",
            symbol: "bubble.left.and.text.bubble.right.fill"
          )
          content()
        }
        .frame(maxWidth: 680)
        .padding(WoorisaiSpacing.screenGutter)
        .frame(maxWidth: .infinity)
      }
    }
    .accessibilityIdentifier(identifier)
  }

  private func detailError(_ message: String, _ identifier: String) -> some View {
    detailStateShell(identifier: identifier) {
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
            model.loadDetail(entryID: entryID)
          }
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          .buttonStyle(.borderedProminent)
          .tint(WoorisaiPalette.primaryButtonStart)
          .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
          .accessibilityIdentifier("diary.detail.retry")
        }
      }
    }
  }

  private var detailNotFound: some View {
    detailStateShell(identifier: "diary.detail.notFound") {
      BrandedStateCard {
        VStack(spacing: WoorisaiSpacing.medium) {
          Image(systemName: "book.closed.fill")
            .font(.system(size: 32, weight: .semibold))
            .foregroundStyle(WoorisaiPalette.coral)
            .accessibilityHidden(true)
          Text("이 일기는 더 이상 없어요")
            .font(.title3.bold())
            .foregroundStyle(WoorisaiPalette.ink)
          Text("상대가 삭제했거나 목록이 바뀌었을 수 있어요.")
            .font(.callout)
            .foregroundStyle(WoorisaiPalette.muted)
            .multilineTextAlignment(.center)
          Button("최신 목록으로 돌아가기") {
            model.reload()
            dismiss()
          }
          .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
          .buttonStyle(.borderedProminent)
          .tint(WoorisaiPalette.primaryButtonStart)
          .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
          .accessibilityIdentifier("diary.detail.backToList")
        }
      }
    }
  }

  private var entryEditorDetents: Set<PresentationDetent> {
    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
  }

  private var commentEditorDetents: Set<PresentationDetent> {
    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
  }
}

private struct DiaryCommentBubble: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let comment: DiaryComment
  let isMutationBlocked: Bool
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack(alignment: .bottom, spacing: WoorisaiSpacing.small) {
      if comment.isMine && !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 44)
      } else if !comment.isMine && !dynamicTypeSize.isAccessibilitySize {
        ParticipantAvatar(name: comment.author.displayName, size: 30)
      }

      commentBody

      if comment.isMine && !dynamicTypeSize.isAccessibilitySize {
        ParticipantAvatar(name: comment.author.displayName, size: 30)
      } else if !comment.isMine && !dynamicTypeSize.isAccessibilitySize {
        Spacer(minLength: 44)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }

  private var commentBody: some View {
    VStack(alignment: comment.isMine ? .trailing : .leading, spacing: WoorisaiSpacing.xSmall) {
      commentMetadata

      Text(comment.content)
        .font(.body)
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.leading)
        .lineSpacing(3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WoorisaiSpacing.regular)
        .padding(.vertical, WoorisaiSpacing.medium)
        .background(comment.isMine ? WoorisaiPalette.coralSoft : WoorisaiPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
            .stroke(
              comment.isMine ? WoorisaiPalette.coral.opacity(0.2) : WoorisaiPalette.line,
              lineWidth: 1
            )
        }
    }
    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 520)
    .overlay(alignment: .topTrailing) {
      commentManagementMenu
    }
  }

  @ViewBuilder
  private var commentMetadata: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: comment.isMine ? .trailing : .leading, spacing: WoorisaiSpacing.xSmall) {
        commentAuthor
        commentTimestamp
      }
      .padding(.trailing, comment.isMine ? WoorisaiControlMetric.minimumTapTarget : 0)
    } else {
      HStack(spacing: WoorisaiSpacing.small) {
        commentAuthor
        commentTimestamp
      }
      .padding(.trailing, comment.isMine ? WoorisaiControlMetric.minimumTapTarget : 0)
    }
  }

  private var commentAuthor: some View {
    Text(comment.isMine ? "나" : comment.author.displayName)
      .font(.caption.weight(.bold))
      .foregroundStyle(WoorisaiPalette.ink)
      .fixedSize(horizontal: false, vertical: true)
  }

  private var commentTimestamp: some View {
    Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
      .font(.caption2)
      .foregroundStyle(WoorisaiPalette.muted)
      .fixedSize(horizontal: true, vertical: true)
  }

  @ViewBuilder
  private var commentManagementMenu: some View {
    if comment.isMine {
      Menu {
        Button("수정", systemImage: "pencil", action: onEdit)
        Button("삭제", systemImage: "trash", role: .destructive, action: onDelete)
      } label: {
        Image(systemName: "ellipsis")
          .font(.caption.weight(.bold))
          .foregroundStyle(WoorisaiPalette.coralDark)
          .frame(
            width: WoorisaiControlMetric.minimumTapTarget,
            height: WoorisaiControlMetric.minimumTapTarget
          )
          .contentShape(Rectangle())
      }
      .disabled(isMutationBlocked)
      .accessibilityLabel("내 댓글 관리")
      .accessibilityIdentifier("diary.comment.\(comment.id).menu")
    }
  }
}
