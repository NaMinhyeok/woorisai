import SwiftUI
import WoorisaiAPI

struct ScoreChangeThreadView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: RelationshipModel
  @State private var commentMediaModel: MediaAttachmentComposerModel
  @State private var latestScrollRequest = 0
  @State private var confirmsDraftDiscard = false
  @FocusState private var isCommentFocused: Bool

  let scoreChangeID: Int64
  let onAuthenticationRequired: @MainActor () -> Void
  private let mediaService: any MediaServing
  private let mediaSessionCoordinator: TopLevelMediaSessionCoordinator
  private static let latestAnchor = "relationship.thread.latest"

  @MainActor
  init(
    model: RelationshipModel,
    scoreChangeID: Int64,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    mediaSessionCoordinator: TopLevelMediaSessionCoordinator,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    let commentMediaModel = MediaAttachmentComposerModel(
      purpose: .comment,
      service: mediaService,
      uploader: mediaUploader
    )
    _commentMediaModel = State(initialValue: commentMediaModel)
    self.scoreChangeID = scoreChangeID
    self.mediaService = mediaService
    self.mediaSessionCoordinator = mediaSessionCoordinator
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    Group {
      switch model.threadState {
      case .idle, .loading:
        threadStateCard(identifier: "relationship.thread.loading") {
          ProgressView()
            .controlSize(.large)
            .tint(WoorisaiColor.Fg.brandVivid)
            .accessibilityHidden(true)
          Text("대화를 불러오고 있어요.")
            .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        }
      case .loaded:
        threadList
      case .notFound:
        threadError("이 점수 기록을 찾을 수 없어요.", "relationship.thread.notFound")
      case .unavailable:
        threadError("대화를 잠시 사용할 수 없어요.", "relationship.thread.unavailable")
      case .failed:
        threadError("대화를 불러오지 못했어요.", "relationship.thread.failed")
      }
    }
    .navigationTitle("점수 대화")
    .navigationBarTitleDisplayMode(.inline)
    // Typed text no longer locks the exit: the draft lives in the model, so leaving and returning
    // restores it. Only a pending upload does, because leaving would strand media ownership.
    .navigationBarBackButtonHidden(
      currentCommentSubmissionState == .submitting || hasUnknownCommentOutcome
        || hasPendingCommentMedia
    )
    .toolbar {
      if hasPendingCommentMedia,
        currentCommentSubmissionState != .submitting,
        !hasUnknownCommentOutcome
      {
        ToolbarItem(placement: .navigationBarLeading) {
          Button {
            confirmsDraftDiscard = true
          } label: {
            Label("돌아가기", systemImage: "chevron.left")
          }
          .accessibilityIdentifier("relationship.thread.requestBack")
        }
      }
    }
    .confirmationDialog(
      "첨부한 사진·영상을 지우고 나갈까요?",
      isPresented: $confirmsDraftDiscard,
      titleVisibility: .visible
    ) {
      Button("첨부 지우고 나가기", role: .destructive, action: discardMediaAndDismiss)
      Button("계속 작성하기", role: .cancel) {}
    } message: {
      Text("아직 보내지 않은 사진·영상이 사라집니다. 입력한 글은 그대로 보관해요.")
    }
    .sensoryFeedback(trigger: model.lastSuccessfulCommentScoreChangeID) { _, successfulID in
      successfulID == scoreChangeID ? .success : nil
    }
    .task(id: scoreChangeID) {
      model.loadThread(scoreChangeID: scoreChangeID)
    }
    .onAppear {
      mediaSessionCoordinator.registerTransient(commentMediaModel)
    }
    .onDisappear {
      isCommentFocused = false
      model.cancelThreadReadForScreenExit(scoreChangeID: scoreChangeID)
      if currentCommentSubmissionState != .submitting && !hasUnknownCommentOutcome
        && !hasPendingCommentMedia
      {
        model.updateLocalCommentDraftProtection(
          scoreChangeID: scoreChangeID,
          isProtected: false
        )
        model.releaseManualRetryDraftProtection(.comment(scoreChangeID: scoreChangeID))
        if model.rejectedMediaMutation == .comment(scoreChangeID: scoreChangeID) {
          commentMediaModel.releaseSubmittedUploadOwnership()
        }
        commentMediaModel.clear()
        mediaSessionCoordinator.unregisterTransient(commentMediaModel)
      }
    }
    .onChange(of: commentMediaModel.hasAuthenticationFailure) { _, required in
      if required {
        commentMediaModel.releaseSubmittedUploadOwnership()
        commentMediaModel.clear()
        onAuthenticationRequired()
      }
    }
    .onChange(of: model.authenticationRequired) { _, required in
      if required {
        commentMediaModel.releaseSubmittedUploadOwnership()
        commentMediaModel.clear()
      }
    }
    .onChange(of: model.rejectedMediaMutation) { _, rejection in
      if rejection == .comment(scoreChangeID: scoreChangeID) {
        commentMediaModel.releaseSubmittedUploadOwnership()
      }
    }
    .onChange(of: model.lastSuccessfulCommentScoreChangeID) { _, successfulID in
      guard successfulID == scoreChangeID else { return }
      commentMediaModel.consumeReadyUploads()
      model.discardCommentDraft(scoreChangeID: scoreChangeID)
      // Keep the conversation flowing: restore focus after a successful send (the field drops it
      // while disabled during the submit) instead of forcing a re-tap for the next reply.
      isCommentFocused = true
      latestScrollRequest &+= 1
      syncCommentDraftProtection()
    }
    .onChange(of: commentContent, initial: true) { _, _ in
      syncCommentDraftProtection()
    }
    .onChange(of: commentMediaModel.uploads.map(\.id), initial: true) { _, _ in
      syncCommentDraftProtection()
    }
    .onChange(of: commentMediaModel.isImporting, initial: true) { _, _ in
      syncCommentDraftProtection()
    }
  }

  private var threadList: some View {
    WarmBackground {
      ScrollViewReader { proxy in
        ScrollView {
          if let thread = model.selectedThread {
            LazyVStack(alignment: .leading, spacing: WoorisaiSpacing.large) {
              VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
                Text("이 마음에 대한 대화")
                  .font(.system(.title2, design: .rounded, weight: .bold))
                  .foregroundStyle(WoorisaiColor.Fg.neutral)
                Text("오래된 이야기부터 차례로 읽고, 가장 아래에서 답장을 건네 보세요.")
                  .font(.subheadline)
                  .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
              }
              .accessibilityElement(children: .combine)
              .accessibilityAddTraits(.isHeader)
              .accessibilityIdentifier("relationship.thread.hero")

              ScoreChangeRow(
                change: thread.change,
                mediaService: mediaService,
                onAuthenticationRequired: onAuthenticationRequired,
                reasonDisplay: .threadDetail
              )

              commentConversation(thread)

              Color.clear
                .frame(height: 1)
                .id(Self.latestAnchor)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, WoorisaiSpacing.screenGutter)
            .padding(.top, WoorisaiSpacing.medium)
            .padding(.bottom, WoorisaiSpacing.regular)
            .frame(maxWidth: .infinity)
            .dismissesKeyboardOnBackgroundTap()
          }
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
          commentComposerBar
        }
        .task(id: model.selectedThread?.change.id) {
          await Task.yield()
          scrollToLatest(using: proxy, animated: false)
          // Second pass after layout settles: the first attempt can fire before the lazy
          // content has registered the bottom sentinel, leaving the thread opened at the top.
          try? await Task.sleep(for: .milliseconds(120))
          scrollToLatest(using: proxy, animated: false)
        }
        .onChange(of: latestScrollRequest) { _, _ in
          scrollToLatest(using: proxy, animated: true)
        }
      }
    }
    // No toast host here: RelationshipView owns one host for the whole navigation stack, so
    // a toast raised in this thread cannot replay on the dashboard after popping.
    .accessibilityIdentifier("relationship.thread.loaded")
  }

  private func commentConversation(_ thread: RelationshipScoreThread) -> some View {
    WarmSurface {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
        WoorisaiSectionHeading(
          "둘만의 대화",
          detail: "댓글 \(thread.comments.count)",
          symbol: "bubble.left.and.bubble.right.fill"
        )
        .accessibilityIdentifier("relationship.thread.comments")

        Divider().overlay(WoorisaiColor.Stroke.neutralWeak)

        if thread.comments.isEmpty {
          VStack(spacing: WoorisaiSpacing.small) {
            Image(systemName: "bubble.left")
              .font(.title2)
              .foregroundStyle(WoorisaiColor.Fg.brandVivid)
              .accessibilityHidden(true)
            Text("아직 댓글이 없어요.")
              .font(.headline)
              .foregroundStyle(WoorisaiColor.Fg.neutral)
            Text("아래 입력창에서 먼저 다정한 이야기를 건네 보세요.")
              .font(.subheadline)
              .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, WoorisaiSpacing.large)
        } else {
          LazyVStack(spacing: WoorisaiSpacing.medium) {
            ForEach(thread.comments) { scoreComment in
              ScoreCommentBubble(
                comment: scoreComment,
                mediaService: mediaService,
                onAuthenticationRequired: onAuthenticationRequired
              )
            }
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
  }

  private var commentComposerBar: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
      if hasUnknownCommentOutcome {
        RelationshipCommentUnknownOutcomeRecovery(
          inspectionState: model.commentOutcomeInspectionState,
          inspectionResult: model.commentOutcomeInspectionResult,
          allowsResolveAsSaved: model.canResolveUnknownCommentOutcomeAsCommitted(
            for: scoreChangeID
          ),
          allowsManualRetry: model.canRetryUnknownCommentOutcome(for: scoreChangeID),
          onReloadLatest: inspectUnknownCommentOutcome,
          onResolveAsSaved: resolveUnknownCommentOutcomeAsSaved,
          onConfirmManualRetry: allowUnknownCommentOutcomeRetry,
          onAbandonInconclusive: abandonInconclusiveUnknownCommentOutcome
        )
      } else {
        if let notice = model.commentNotice(for: scoreChangeID) {
          Label(notice, systemImage: "bubble.left.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(WoorisaiColor.Fg.neutral)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.updatesFrequently)
            .accessibilityIdentifier("relationship.thread.notice")
        }

        MediaAttachmentStrip(model: commentMediaModel)
          .disabled(isDraftEditingLocked)

        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
            commentTextField
            HStack(spacing: WoorisaiSpacing.small) {
              attachmentSourceButton
              commentCountLabel
              Spacer(minLength: WoorisaiSpacing.small)
              commentSubmitButton
            }
          }
        } else {
          HStack(alignment: .bottom, spacing: WoorisaiSpacing.small) {
            attachmentSourceButton
            commentTextField
            commentCountLabel
            commentSubmitButton
          }
        }
      }
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.small)
    .woorisaiKeyboardActionBarSurface()
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.thread.composer")
  }

  private var commentTextField: some View {
    TextField(
      "답장을 쓰거나 사진·영상을 남겨 보세요.",
      text: commentContentBinding,
      axis: .vertical
    )
      .lineLimit(1...4)
      .focused($isCommentFocused)
      .foregroundStyle(WoorisaiColor.Fg.neutral)
      .tint(WoorisaiColor.Fg.brand)
      .padding(.horizontal, WoorisaiSpacing.medium)
      .padding(.vertical, WoorisaiSpacing.small)
      .frame(minHeight: WoorisaiControlMetric.minimumTapTarget)
      .background(
        WoorisaiColor.Bg.layerFill,
        in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
          .stroke(commentIsWithinLimit ? WoorisaiColor.Stroke.neutralWeak : WoorisaiColor.Stroke.critical, lineWidth: 1)
      }
      .accessibilityIdentifier("relationship.thread.commentInput")
      // The counter only appears near the limit, so VoiceOver hears the remaining budget here — a
      // hint rather than a value, because the value has to stay the typed text.
      .accessibilityHint(commentBudget.accessibilityDescription)
      .disabled(isDraftEditingLocked)
  }

  /// The attach affordance opens the source menu directly instead of toggling a tray.
  ///
  /// Before, this paperclip opened a tray and a second paperclip inside the tray picked the source —
  /// two steps to the same place. Worse, the tray held a `ScrollView` capped at 240pt, and a
  /// `ScrollView` fills the space it is offered rather than shrinking to its content, so an empty
  /// tray spent all 240pt to show one row. Selected attachments now cost only what
  /// `MediaAttachmentStrip` needs, and nothing at all while there are none.
  private var attachmentSourceButton: some View {
    MediaAttachmentSourceMenu(model: commentMediaModel)
      .labelStyle(.iconOnly)
      .font(.title2)
      .foregroundStyle(WoorisaiColor.Fg.brand)
      .frame(
        width: WoorisaiControlMetric.minimumTapTarget,
        height: WoorisaiControlMetric.minimumTapTarget
      )
      .accessibilityIdentifier("relationship.thread.media.attach")
      .disabled(isDraftEditingLocked)
  }

  private var commentSubmitButton: some View {
    Button(action: submitComment) {
      Group {
        if currentCommentSubmissionState == .submitting {
          ProgressView()
            .tint(WoorisaiColor.Fg.staticWhite)
        } else {
          Image(systemName: "arrow.up")
            .font(.headline.weight(.bold))
        }
      }
      .foregroundStyle(WoorisaiColor.Fg.staticWhite)
      .frame(
        width: WoorisaiControlMetric.minimumTapTarget,
        height: WoorisaiControlMetric.minimumTapTarget
      )
      .background(
        canSubmitComment
          ? WoorisaiColor.Bg.brandSolid : WoorisaiColor.Bg.disabled,
        in: Circle()
      )
    }
    .buttonStyle(.plain)
    .disabled(!canSubmitComment || currentCommentSubmissionState == .submitting)
    .accessibilityLabel(Text(commentSubmissionAccessibility.label))
    .accessibilityValue(Text(commentSubmissionAccessibility.value))
    .accessibilityIdentifier("relationship.thread.createComment")
  }

  private var commentCountLabel: some View {
    WoorisaiCharacterCountLabel(commentBudget, name: "댓글")
  }

  private var commentBudget: CharacterBudget {
    CharacterBudget(
      used: commentCodePointCount,
      limit: RelationshipScoreCommentDraft.maximumContentCharacterCount
    )
  }

  private var commentContent: String {
    model.commentDraft(scoreChangeID: scoreChangeID)
  }

  private var commentContentBinding: Binding<String> {
    Binding(
      get: { model.commentDraft(scoreChangeID: scoreChangeID) },
      set: { model.updateCommentDraft(scoreChangeID: scoreChangeID, content: $0) }
    )
  }

  private var trimmedComment: String {
    WoorisaiTextInput.normalized(commentContent)
  }

  private var commentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(commentContent)
  }

  private var hasPendingCommentMedia: Bool {
    !commentMediaModel.uploads.isEmpty || commentMediaModel.isImporting
  }

  private var commentIsWithinLimit: Bool {
    !commentBudget.isExceeded
  }

  private var commentSubmissionAccessibility: RelationshipSubmissionAccessibility {
    .comment(
      state: currentCommentSubmissionState,
      hasContent: !trimmedComment.isEmpty || !commentMediaModel.readyUploadIDs.isEmpty,
      isBlockedByAnotherSubmission: isBlockedByAnotherCommentSubmission,
      isContentWithinLimit: commentIsWithinLimit
    )
  }

  private var currentCommentSubmissionState: RelationshipModel.SubmissionState {
    model.commentSubmissionState(for: scoreChangeID)
  }

  private var hasUnknownCommentOutcome: Bool {
    model.commentOutcomeRequiresConfirmation(for: scoreChangeID)
  }

  /// Drives push-driven navigation deferral (not the exit lock): a half-written reply should not be
  /// yanked away by an arriving notification either.
  private var isCommentDraftDirty: Bool {
    !trimmedComment.isEmpty || hasPendingCommentMedia
  }

  private var isDraftEditingLocked: Bool {
    SubmittedDraftEditingPolicy.isLocked(
      isSubmitting: currentCommentSubmissionState == .submitting,
      requiresOutcomeConfirmation: hasUnknownCommentOutcome
    )
  }

  private var isBlockedByAnotherCommentSubmission: Bool {
    model.commentSubmissionState == .submitting
      && model.commentSubmissionScoreChangeID != scoreChangeID
  }

  private var canSubmitComment: Bool {
    (!trimmedComment.isEmpty || !commentMediaModel.readyUploadIDs.isEmpty)
      && commentIsWithinLimit
      && commentMediaModel.isReadyForSubmission
      && model.commentSubmissionState != .submitting
      && !model.commentOutcomeRequiresConfirmation
  }

  private func submitComment() {
    let uploadIDs = commentMediaModel.readyUploadIDs
    let accepted = model.createComment(
      scoreChangeID: scoreChangeID,
      content: commentContent,
      mediaUploadIDs: uploadIDs
    )
    if accepted {
      commentMediaModel.markReadyUploadsSubmitted()
    }
  }

  private func inspectUnknownCommentOutcome() {
    isCommentFocused = false
    model.inspectUnknownCommentOutcome(scoreChangeID: scoreChangeID)
  }

  private func resolveUnknownCommentOutcomeAsSaved() {
    guard model.resolveUnknownCommentOutcomeAsCommitted(scoreChangeID: scoreChangeID) else {
      return
    }
    commentMediaModel.consumeReadyUploads()
    model.discardCommentDraft(scoreChangeID: scoreChangeID)
    isCommentFocused = false
    syncCommentDraftProtection()
  }

  private func allowUnknownCommentOutcomeRetry() {
    guard model.confirmUnknownCommentOutcomeForRetry(scoreChangeID: scoreChangeID) else { return }
    commentMediaModel.releaseSubmittedUploadOwnership()
    syncCommentDraftProtection()
  }

  private func abandonInconclusiveUnknownCommentOutcome() {
    guard model.abandonInconclusiveUnknownCommentOutcome(scoreChangeID: scoreChangeID) else {
      return
    }
    commentMediaModel.consumeReadyUploads()
    model.discardCommentDraft(scoreChangeID: scoreChangeID)
    isCommentFocused = false
    syncCommentDraftProtection()
  }

  /// Discards only the pending media and leaves, keeping the typed text — that is what the dialog
  /// promises, and the text is safe to keep because the model owns it across navigation.
  private func discardMediaAndDismiss() {
    isCommentFocused = false
    model.updateLocalCommentDraftProtection(scoreChangeID: scoreChangeID, isProtected: false)
    model.releaseManualRetryDraftProtection(.comment(scoreChangeID: scoreChangeID))
    if model.rejectedMediaMutation == .comment(scoreChangeID: scoreChangeID) {
      commentMediaModel.releaseSubmittedUploadOwnership()
    }
    commentMediaModel.clear()
    mediaSessionCoordinator.unregisterTransient(commentMediaModel)
    dismiss()
  }

  private func syncCommentDraftProtection() {
    model.updateLocalCommentDraftProtection(
      scoreChangeID: scoreChangeID,
      isProtected: isCommentDraftDirty
    )
    if !isCommentDraftDirty {
      model.releaseManualRetryDraftProtection(.comment(scoreChangeID: scoreChangeID))
    }
  }

  private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
    guard model.selectedThread != nil else { return }
    if animated, !reduceMotion {
      withAnimation(.easeOut(duration: 0.24)) {
        proxy.scrollTo(Self.latestAnchor, anchor: .bottom)
      }
    } else {
      proxy.scrollTo(Self.latestAnchor, anchor: .bottom)
    }
  }

  private func threadStateCard<Content: View>(
    identifier: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      BrandedStateCard {
        VStack(spacing: WoorisaiSpacing.regular) {
          content()
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(identifier)
  }

  private func threadError(_ message: String, _ identifier: String) -> some View {
    threadStateCard(identifier: identifier) {
      Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
        .font(.system(size: 34))
        .foregroundStyle(WoorisaiColor.Fg.brandVivid)
        .accessibilityHidden(true)
      Text("대화를 열 수 없어요")
        .font(.title3.weight(.bold))
        .foregroundStyle(WoorisaiColor.Fg.neutral)
      Text(message)
        .font(.subheadline)
        .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
        .multilineTextAlignment(.center)
      Button("다시 시도") {
        model.loadThread(scoreChangeID: scoreChangeID)
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiColor.Bg.brandSolid)
      .foregroundStyle(WoorisaiColor.Fg.brandContrast)
      .accessibilityIdentifier("relationship.thread.retry")
    }
  }
}

private struct RelationshipCommentUnknownOutcomeRecovery: View {
  let inspectionState: RelationshipModel.OutcomeInspectionState
  let inspectionResult: RelationshipModel.OutcomeInspectionResult
  let allowsResolveAsSaved: Bool
  let allowsManualRetry: Bool
  let onReloadLatest: () -> Void
  let onResolveAsSaved: () -> Void
  let onConfirmManualRetry: () -> Void
  let onAbandonInconclusive: () -> Void
  @State private var showsRecoveryActions = false

  var body: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text(message)
        .font(.caption)
        .foregroundStyle(WoorisaiColor.Fg.critical)

      Button {
        showsRecoveryActions = true
      } label: {
        Label(
          inspectionState == .loading ? "댓글 저장 결과 확인 중" : "댓글 저장 결과 확인하기",
          systemImage: "arrow.triangle.2.circlepath"
        )
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiColor.Bg.brandSolid)
      .disabled(inspectionState == .loading)
      .accessibilityIdentifier("relationship.commentMutation.openRecovery")
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.commentMutation.recovery")
    .confirmationDialog(
      "댓글의 저장 결과를 어떻게 확인했나요?",
      isPresented: $showsRecoveryActions,
      titleVisibility: .visible
    ) {
      Button("최신 대화 다시 불러오기", action: onReloadLatest)
        .disabled(inspectionState == .loading)
        .accessibilityIdentifier("relationship.commentMutation.reloadLatest")
      Button("이미 저장됨 · 초안 정리", action: onResolveAsSaved)
        .disabled(!allowsResolveAsSaved)
        .accessibilityIdentifier("relationship.commentMutation.resolveSaved")
      Button("저장 안 됨 · 다시 시도 허용", action: onConfirmManualRetry)
        .disabled(!allowsManualRetry)
        .accessibilityIdentifier("relationship.commentMutation.confirmRetry")
      // Always enabled: abandon is the offline escape hatch — see the score composer's dialog.
      Button("판단 보류 · 재전송 없이 초안 정리", role: .destructive) {
        onAbandonInconclusive()
      }
      .accessibilityIdentifier("relationship.commentMutation.abandonInconclusive")
      Button("취소", role: .cancel) {}
    } message: {
      Text(message)
    }
  }

  private var message: String {
    switch inspectionState {
    case .idle:
      return "저장됐을 수도 있어요. 최신 대화를 먼저 확인해 주세요. 초안은 그대로 유지됩니다."
    case .loading:
      return "최신 대화를 확인하고 있어요. 초안은 그대로 유지됩니다."
    case .loaded:
      switch inspectionResult {
      case .committed:
        return "제출한 글·첨부와 같은 새 댓글을 확인했어요. 초안을 정리해 주세요."
      case .notCommitted:
        return "제출 전 댓글이 모두 그대로이고 같은 새 댓글은 없어요. 직접 다시 시도할 수 있어요."
      case .inconclusive:
        return "댓글 목록이 예상과 달라 자동 판단할 수 없어요. 재전송하지 않고 초안을 정리할 수 있어요."
      }
    case .failed:
      return "최신 대화를 불러오지 못했어요. 초안을 유지한 채 다시 시도해 주세요."
    }
  }
}

private struct ScoreCommentBubble: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  let comment: RelationshipScoreComment
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  private var isMine: Bool {
    comment.author.isCurrentParticipant
  }

  var body: some View {
    let metadataLayout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: WoorisaiSpacing.xSmall))
      : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small))

    return HStack(alignment: .top, spacing: 0) {
      BubbleOppositeGutter(isMine)

      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        metadataLayout {
          Text(isMine ? "나" : comment.author.displayName)
            .font(.caption.weight(.heavy))
            .foregroundStyle(WoorisaiColor.Fg.neutral)
          if !dynamicTypeSize.isAccessibilitySize {
            Spacer(minLength: WoorisaiSpacing.small)
          }
          Text(comment.createdAt.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(WoorisaiColor.Fg.neutralMuted)
            .fixedSize(horizontal: true, vertical: true)
        }

        if let content = comment.content {
          Text(content)
            .font(.body)
            .foregroundStyle(WoorisaiColor.Fg.neutral)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !comment.attachments.isEmpty {
          RelationshipMediaGallery(
            attachments: comment.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
      }
      .padding(WoorisaiSpacing.medium)
      .background(
        isMine ? WoorisaiColor.Bg.brandWeak : WoorisaiColor.Bg.layerFill,
        in: RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous)
          .stroke(
            WoorisaiColor.stroke(.init(isMine: isMine)),
            lineWidth: 1
          )
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      BubbleOppositeGutter(!isMine)
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("relationship.thread.comment.\(comment.id)")
  }
}

struct RelationshipMediaGallery: View {
  let attachments: [RelationshipMedia]
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    MediaAttachmentPreviewGallery(
      attachments: attachments.map(MediaAttachmentDescriptor.init),
      onAuthenticationRequired: onAuthenticationRequired
    )
    .accessibilityLabel("첨부 미디어 \(attachments.count)개")
    .accessibilityIdentifier("media.group")
  }
}

extension MediaAttachmentDescriptor {
  init(_ media: RelationshipMedia) {
    self.init(
      id: media.id,
      fileName: media.fileName,
      contentType: media.contentType,
      byteSize: media.byteSize
    )
  }
}
