import SwiftUI
import WoorisaiAPI

enum DiaryEditorDismissalPolicy {
  static func cancellationIsDisabled(
    isSubmitting: Bool,
    requiresRetryConfirmation: Bool,
    canKeepDraft: Bool
  ) -> Bool {
    isSubmitting || (requiresRetryConfirmation && !canKeepDraft)
  }

  static func allowsDiscard(requiresRetryConfirmation: Bool) -> Bool {
    !requiresRetryConfirmation
  }
}

enum DiaryReconciliationMatcher {
  static func entryMatches(
    serverContent: String,
    serverAttachmentIDs: some Sequence<UUID>,
    expectedContent: String,
    expectedAttachmentIDs: some Sequence<UUID>
  ) -> Bool {
    serverContent == expectedContent
      && Array(serverAttachmentIDs) == Array(expectedAttachmentIDs)
  }

  static func commentMatches(serverContent: String, expectedContent: String) -> Bool {
    serverContent == expectedContent
  }
}

struct DiaryReconciliationPresentation: Equatable {
  let title: String
  let latestServerContent: String?
  let latestServerAttachments: [DiaryAttachment]?
  let state: DiaryModel.ReconciliationState
  let allowsResolveAsSaved: Bool
  let allowsManualRetry: Bool

  var blocksSubmission: Bool {
    state != .loaded || latestServerContent == nil
  }
}

struct DiaryCommentEditor: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let comment: DiaryComment
  @Binding var content: String
  let isSubmitting: Bool
  let requiresRetryConfirmation: Bool
  let reconciliation: DiaryReconciliationPresentation?
  let inspectionState: DiaryModel.ReconciliationState
  let allowsManualRetry: Bool
  let mutationMessage: String?
  let onCancel: () -> Void
  let onDismissMessage: () -> Void
  let onReloadLatest: () -> Void
  let onResolveAsSaved: () -> Void
  let onConfirmManualRetry: () -> Void
  let onAbandonInconclusive: () -> Void
  let onSubmit: () -> Void
  @FocusState private var isFocused: Bool
  @State private var confirmsDiscard = false

  var body: some View {
    NavigationStack {
      WarmBackground {
        ScrollView {
          VStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
            DiaryHero(
              eyebrow: "EDIT REPLY",
              title: "댓글 다듬기",
              message: "마음을 다시 읽어 보고 천천히 고쳐 보세요.",
              symbol: "bubble.left.and.text.bubble.right.fill"
            )

            if let mutationMessage {
              DiaryMutationStatusCard(
                message: mutationMessage,
                onDismiss: onDismissMessage
              )
            }

            if let reconciliation {
              DiaryReconciliationCard(presentation: reconciliation)
            }

            WarmSurface(cornerRadius: WoorisaiRadius.large) {
              VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
                editorHeading
                TextEditor(text: $content)
                  .frame(minHeight: 160)
                  .focused($isFocused)
                  .scrollContentBackground(.hidden)
                  .foregroundStyle(WoorisaiPalette.ink)
                  .tint(WoorisaiPalette.coralDark)
                  .padding(WoorisaiSpacing.small)
                  .background(WoorisaiPalette.field)
                  .clipShape(
                    RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
                  )
                  .overlay {
                    RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
                      .stroke(WoorisaiPalette.line, lineWidth: 1)
                  }
                  .accessibilityLabel("댓글 내용")
                  .accessibilityIdentifier("diary.comment.edit.input")
                  .disabled(isDraftEditingLocked)
              }
              .padding(WoorisaiSpacing.regular)
            }
          }
          .frame(maxWidth: 680)
          .padding(WoorisaiSpacing.screenGutter)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .keyboardDoneToolbar()
      .safeAreaInset(edge: .bottom, spacing: 0) {
        stickySubmitBar
      }
      .navigationTitle("댓글 수정")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소", action: requestCancel)
            .disabled(
              DiaryEditorDismissalPolicy.cancellationIsDisabled(
                isSubmitting: isSubmitting,
                requiresRetryConfirmation: requiresRetryConfirmation,
                canKeepDraft: false
              )
            )
        }
      }
      .confirmationDialog(
        "수정 중인 내용을 버릴까요?",
        isPresented: $confirmsDiscard,
        titleVisibility: .visible
      ) {
        Button("수정 내용 버리기", role: .destructive) {
          isFocused = false
          content = comment.content
          onCancel()
        }
        Button("계속 수정하기", role: .cancel) {}
      }
      .onAppear {
        isFocused = true
      }
      .onDisappear {
        isFocused = false
      }
    }
  }

  private var editorHeading: some View {
    editorTitleAndCount
  }

  private var editorTitleAndCount: some View {
    HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
      Text("댓글")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
      Spacer(minLength: WoorisaiSpacing.small)
      Text("\(codePointCount)/\(DiaryCommentDraft.maximumContentCharacterCount)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(
          codePointCount > DiaryCommentDraft.maximumContentCharacterCount
            ? WoorisaiPalette.error : WoorisaiPalette.muted
        )
    }
  }

  private var stickySubmitBar: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      if requiresRetryConfirmation {
        retryConfirmation
      }
      PrimaryHeartButton(
        "댓글 수정하기",
        isEnabled: canSubmit,
        isLoading: isSubmitting
      ) {
        isFocused = false
        onSubmit()
      }
      .accessibilityIdentifier("diary.comment.edit.submit")
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.small)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider().overlay(WoorisaiPalette.line)
    }
  }

  private var canSubmit: Bool {
    content != comment.content
      && !WoorisaiTextInput.normalized(content).isEmpty
      && codePointCount <= DiaryCommentDraft.maximumContentCharacterCount
      && !isSubmitting
      && !requiresRetryConfirmation
      && reconciliation?.blocksSubmission != true
  }

  private var isDraftEditingLocked: Bool {
    SubmittedDraftEditingPolicy.isLocked(
      isSubmitting: isSubmitting,
      requiresOutcomeConfirmation: requiresRetryConfirmation
    )
  }

  private var codePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(content)
  }

  private func requestCancel() {
    isFocused = false
    if content == comment.content {
      onCancel()
    } else {
      confirmsDiscard = true
    }
  }

  private var retryConfirmation: some View {
    DiaryUnknownOutcomeRecovery(
      inspectionState: inspectionState,
      allowsResolveAsSaved: reconciliation?.allowsResolveAsSaved ?? true,
      allowsManualRetry: allowsManualRetry,
      onReloadLatest: onReloadLatest,
      onResolveAsSaved: onResolveAsSaved,
      onConfirmManualRetry: onConfirmManualRetry,
      onAbandonInconclusive: onAbandonInconclusive
    )
  }
}

struct DiaryEntryComposer: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: LocalizedStringKey
  @Binding var content: String
  @State private var mediaModel: MediaAttachmentComposerModel
  @FocusState private var isContentFocused: Bool
  @State private var confirmsDraftExit = false
  let retainedAttachments: [DiaryAttachment]
  let mediaService: any MediaServing
  let isSubmitting: Bool
  let hasDraftChanges: Bool
  let canKeepDraft: Bool
  let requiresRetryConfirmation: Bool
  let reconciliation: DiaryReconciliationPresentation?
  let inspectionState: DiaryModel.ReconciliationState
  let allowsManualRetry: Bool
  let mutationMessage: String?
  let submitTitle: LocalizedStringKey
  let onRemoveRetainedAttachment: (UUID) -> Void
  let onAuthenticationRequired: @MainActor () -> Void
  let onKeepDraft: () -> Void
  let onDismissMessage: () -> Void
  let onReloadLatest: () -> Void
  let onResolveAsSaved: () -> Void
  let onConfirmManualRetry: () -> Void
  let onAbandonInconclusive: () -> Void
  let onDiscard: () -> Void
  let onSubmit: () -> Void

  @MainActor
  init(
    title: LocalizedStringKey,
    content: Binding<String>,
    mediaModel: MediaAttachmentComposerModel,
    retainedAttachments: [DiaryAttachment],
    mediaService: any MediaServing,
    isSubmitting: Bool,
    hasDraftChanges: Bool,
    canKeepDraft: Bool,
    requiresRetryConfirmation: Bool,
    reconciliation: DiaryReconciliationPresentation?,
    inspectionState: DiaryModel.ReconciliationState,
    allowsManualRetry: Bool,
    mutationMessage: String?,
    submitTitle: LocalizedStringKey,
    onRemoveRetainedAttachment: @escaping (UUID) -> Void,
    onAuthenticationRequired: @escaping @MainActor () -> Void,
    onKeepDraft: @escaping () -> Void,
    onDismissMessage: @escaping () -> Void,
    onReloadLatest: @escaping () -> Void,
    onResolveAsSaved: @escaping () -> Void,
    onConfirmManualRetry: @escaping () -> Void,
    onAbandonInconclusive: @escaping () -> Void,
    onDiscard: @escaping () -> Void,
    onSubmit: @escaping () -> Void
  ) {
    self.title = title
    _content = content
    _mediaModel = State(initialValue: mediaModel)
    self.retainedAttachments = retainedAttachments
    self.mediaService = mediaService
    self.isSubmitting = isSubmitting
    self.hasDraftChanges = hasDraftChanges
    self.canKeepDraft = canKeepDraft
    self.requiresRetryConfirmation = requiresRetryConfirmation
    self.reconciliation = reconciliation
    self.inspectionState = inspectionState
    self.allowsManualRetry = allowsManualRetry
    self.mutationMessage = mutationMessage
    self.submitTitle = submitTitle
    self.onRemoveRetainedAttachment = onRemoveRetainedAttachment
    self.onAuthenticationRequired = onAuthenticationRequired
    self.onKeepDraft = onKeepDraft
    self.onDismissMessage = onDismissMessage
    self.onReloadLatest = onReloadLatest
    self.onResolveAsSaved = onResolveAsSaved
    self.onConfirmManualRetry = onConfirmManualRetry
    self.onAbandonInconclusive = onAbandonInconclusive
    self.onDiscard = onDiscard
    self.onSubmit = onSubmit
  }

  var body: some View {
    NavigationStack {
      WarmBackground {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: WoorisaiSpacing.regular) {
            DiaryHero(
              eyebrow: "SHARE A STORY",
              title: title,
              message: "지금 나누고 싶은 순간이나 마음을 천천히 적어 주세요.",
              symbol: "square.and.pencil"
            )

            if let mutationMessage {
              DiaryMutationStatusCard(
                message: mutationMessage,
                onDismiss: onDismissMessage
              )
            }

            if let reconciliation {
              DiaryReconciliationCard(presentation: reconciliation)
              if let latestServerAttachments = reconciliation.latestServerAttachments,
                reconciliation.state == .loaded
              {
                latestServerAttachmentsCard(latestServerAttachments, presentation: reconciliation)
              }
            }

            contentCard

            if !retainedAttachments.isEmpty {
              retainedMediaCard
            }

            newMediaCard
          }
          .disabled(isDraftEditingLocked)
          .frame(maxWidth: 680)
          .padding(.horizontal, WoorisaiSpacing.screenGutter)
          .padding(.top, WoorisaiSpacing.medium)
          .padding(.bottom, WoorisaiSpacing.xLarge)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .keyboardDoneToolbar()
      .safeAreaInset(edge: .bottom, spacing: 0) {
        stickyActionBar
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소", action: requestCancel)
            .disabled(
              DiaryEditorDismissalPolicy.cancellationIsDisabled(
                isSubmitting: isSubmitting,
                requiresRetryConfirmation: requiresRetryConfirmation,
                canKeepDraft: canKeepDraft
              )
            )
            .tint(WoorisaiPalette.coralDark)
        }
      }
      .confirmationDialog(
        "작성 중인 내용을 어떻게 할까요?",
        isPresented: $confirmsDraftExit,
        titleVisibility: .visible
      ) {
        if canKeepDraft {
          Button("초안으로 두고 닫기") {
            isContentFocused = false
            onKeepDraft()
          }
        }
        if DiaryEditorDismissalPolicy.allowsDiscard(
          requiresRetryConfirmation: requiresRetryConfirmation
        ) {
          Button("내용 버리기", role: .destructive) {
            isContentFocused = false
            onDiscard()
          }
        }
        Button("계속 작성하기", role: .cancel) {}
      }
      .onChange(of: mediaModel.hasAuthenticationFailure) { _, required in
        if required {
          onAuthenticationRequired()
        }
      }
      .onDisappear {
        isContentFocused = false
      }
    }
  }

  private var contentCard: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        contentHeading

        TextEditor(text: $content)
          .frame(minHeight: 190)
          .focused($isContentFocused)
          .scrollContentBackground(.hidden)
          .foregroundStyle(WoorisaiPalette.ink)
          .tint(WoorisaiPalette.coralDark)
          .padding(WoorisaiSpacing.small)
          .background(WoorisaiPalette.field)
          .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: WoorisaiRadius.small, style: .continuous)
              .stroke(WoorisaiPalette.line, lineWidth: 1)
          }
          .accessibilityLabel("일기 내용")
          .accessibilityIdentifier("diary.entry.content")

        Label("이 글은 우리 둘에게만 보여요.", systemImage: "lock.fill")
          .font(.footnote)
          .foregroundStyle(WoorisaiPalette.muted)
      }
      .padding(WoorisaiSpacing.regular)
    }
  }

  // Keyboard dismissal lives in the shared keyboard toolbar (`keyboardDoneToolbar`), not in an
  // inline chip: the chip reflowed this heading on every focus change and sat at the top of the
  // card, far from the keyboard.
  private var contentHeading: some View {
    contentTitleAndCount
  }

  private var contentTitleAndCount: some View {
    HStack(alignment: .firstTextBaseline, spacing: WoorisaiSpacing.small) {
      Text("우리에게 남길 이야기")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
      Spacer(minLength: WoorisaiSpacing.small)
      Text("\(contentCodePointCount)/\(DiaryEntryCreateDraft.maximumContentCharacterCount)")
        .font(.caption.monospacedDigit())
        .foregroundStyle(
          contentCodePointCount > DiaryEntryCreateDraft.maximumContentCharacterCount
            ? WoorisaiPalette.error : WoorisaiPalette.muted
        )
    }
  }

  private var retainedMediaCard: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
        WoorisaiSectionHeading(
          "현재 첨부",
          detail: "\(retainedAttachments.count)개",
          symbol: "photo.on.rectangle"
        )

        MediaAttachmentGallery(
          items: retainedAttachments,
          kind: { $0.contentType.lowercased().hasPrefix("image/") ? .image : .video }
        ) { attachment, format in
          MediaAttachmentPreview(
            attachmentID: attachment.id,
            fileName: attachment.fileName,
            contentType: attachment.contentType,
            byteSize: attachment.byteSize,
            tileFormat: format,
            onAuthenticationRequired: onAuthenticationRequired
          )
          .overlay(alignment: .topTrailing) {
            Button(role: .destructive) {
              onRemoveRetainedAttachment(attachment.id)
            } label: {
              Image(systemName: "trash.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(
                  width: WoorisaiControlMetric.minimumTapTarget,
                  height: WoorisaiControlMetric.minimumTapTarget
                )
                .background(.black.opacity(0.58), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(WoorisaiSpacing.xSmall)
            .accessibilityLabel("\(attachment.fileName) 첨부에서 제거")
          }
        }
      }
      .padding(WoorisaiSpacing.regular)
    }
  }

  private func latestServerAttachmentsCard(
    _ attachments: [DiaryAttachment],
    presentation: DiaryReconciliationPresentation
  ) -> some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
        WoorisaiSectionHeading(
          "서버에서 다시 읽은 첨부",
          detail: "\(attachments.count)개",
          symbol: "arrow.triangle.2.circlepath"
        )

        if attachments.isEmpty {
          Label("서버의 최신 일기에는 첨부가 없어요.", systemImage: "photo.badge.minus")
            .font(.callout)
            .foregroundStyle(WoorisaiPalette.muted)
        } else {
          DiaryAttachmentGallery(
            attachments: attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        Label(
          reconciliationComparisonMessage(presentation),
          systemImage: reconciliationComparisonSymbol(presentation)
        )
        .font(.caption)
        .foregroundStyle(
          presentation.allowsResolveAsSaved || presentation.allowsManualRetry
            ? WoorisaiPalette.muted : WoorisaiPalette.error
        )
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityIdentifier("diary.reconciliation.attachments")
  }

  private func reconciliationComparisonMessage(
    _ presentation: DiaryReconciliationPresentation
  ) -> String {
    if presentation.allowsResolveAsSaved {
      return "서버의 최신 내용과 첨부가 이번 수정과 일치해요."
    }
    if presentation.allowsManualRetry {
      return "서버의 최신 내용과 첨부가 수정 전 상태와 일치해요."
    }
    return "서버 상태가 이번 수정이나 수정 전 상태와 다릅니다. 초안을 유지한 채 다시 확인해 주세요."
  }

  private func reconciliationComparisonSymbol(
    _ presentation: DiaryReconciliationPresentation
  ) -> String {
    presentation.allowsResolveAsSaved || presentation.allowsManualRetry
      ? "checkmark.shield.fill" : "exclamationmark.triangle.fill"
  }

  private var newMediaCard: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.large) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.medium) {
        WoorisaiSectionHeading("사진·영상 추가", detail: "선택", symbol: "paperclip")
        MediaAttachmentComposer(model: mediaModel)
        Text("사진은 최대 4장, 영상은 1개까지 첨부할 수 있어요.")
          .font(.footnote)
          .foregroundStyle(WoorisaiPalette.muted)
      }
      .padding(WoorisaiSpacing.regular)
    }
  }

  private var stickyActionBar: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      if requiresRetryConfirmation {
        DiaryUnknownOutcomeRecovery(
          inspectionState: inspectionState,
          allowsResolveAsSaved: reconciliation?.allowsResolveAsSaved ?? true,
          allowsManualRetry: allowsManualRetry,
          onReloadLatest: onReloadLatest,
          onResolveAsSaved: onResolveAsSaved,
          onConfirmManualRetry: onConfirmManualRetry,
          onAbandonInconclusive: onAbandonInconclusive
        )
      }
      if hasDraftChanges {
        Label(
          canKeepDraft ? "이 기기에서 로그인한 동안 초안을 기억해요." : "닫기 전에 수정 내용을 저장하거나 버려 주세요.",
          systemImage: "pencil.line"
        )
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
      }
      PrimaryHeartButton(
        submitTitle,
        isEnabled: canSubmit,
        isLoading: isSubmitting,
        action: submit
      )
      .accessibilityIdentifier("diary.entry.submit")
    }
    .padding(.horizontal, WoorisaiSpacing.screenGutter)
    .padding(.vertical, WoorisaiSpacing.small)
    .background(.regularMaterial)
    .overlay(alignment: .top) {
      Divider().overlay(WoorisaiPalette.line)
    }
  }

  private var canSubmit: Bool {
    hasDraftChanges
      && !WoorisaiTextInput.normalized(content).isEmpty
      && contentCodePointCount <= DiaryEntryCreateDraft.maximumContentCharacterCount
      && !isSubmitting
      && mediaModel.isReadyForSubmission
      && !requiresRetryConfirmation
      && reconciliation?.blocksSubmission != true
  }

  private var isDraftEditingLocked: Bool {
    SubmittedDraftEditingPolicy.isLocked(
      isSubmitting: isSubmitting,
      requiresOutcomeConfirmation: requiresRetryConfirmation
    )
  }

  private var contentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(content)
  }

  private func requestCancel() {
    isContentFocused = false
    if hasDraftChanges {
      confirmsDraftExit = true
    } else {
      onKeepDraft()
    }
  }

  private func submit() {
    isContentFocused = false
    onSubmit()
  }
}

struct DiaryUnknownOutcomeRecovery: View {
  let inspectionState: DiaryModel.ReconciliationState
  let allowsResolveAsSaved: Bool
  let allowsManualRetry: Bool
  let onReloadLatest: () -> Void
  let onResolveAsSaved: () -> Void
  let onConfirmManualRetry: () -> Void
  let onAbandonInconclusive: () -> Void
  @State private var showsRecoveryActions = false
  @State private var confirmsAbandon = false

  var body: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text(recoveryMessage)
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.error)
      Button {
        showsRecoveryActions.toggle()
      } label: {
        Label(
          recoveryButtonTitle,
          systemImage: showsRecoveryActions
            ? "chevron.up.circle.fill" : "arrow.triangle.2.circlepath"
        )
        .frame(maxWidth: .infinity, minHeight: WoorisaiControlMetric.minimumTapTarget)
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiPalette.coralDark)
      .disabled(inspectionState == .loading)
      .accessibilityIdentifier("diary.mutation.openRecovery")

      if showsRecoveryActions {
        recoveryActions
      }
    }
    .onChange(of: inspectionState) { _, _ in
      showsRecoveryActions = false
    }
    .confirmationDialog(
      "저장 여부를 확정할 수 없는 초안을 정리할까요?",
      isPresented: $confirmsAbandon,
      titleVisibility: .visible
    ) {
      Button("재전송 없이 초안 정리", role: .destructive) {
        showsRecoveryActions = false
        onAbandonInconclusive()
      }
      Button("초안 계속 보관", role: .cancel) {}
    } message: {
      Text("서버에 다시 보내지 않습니다. 최신 서버 내용은 그대로 유지돼요.")
    }
  }

  private var recoveryButtonTitle: String {
    if inspectionState == .loading { return "저장 결과 확인 중" }
    return showsRecoveryActions ? "확인 선택 닫기" : "저장 결과 확인하기"
  }

  private var recoveryActions: some View {
    VStack(alignment: .leading, spacing: WoorisaiSpacing.xSmall) {
      Text("저장 결과를 어떻게 확인했나요?")
        .font(.caption.weight(.bold))
        .foregroundStyle(WoorisaiPalette.ink)

      Button("최신 내용 불러오기") {
        showsRecoveryActions = false
        onReloadLatest()
      }
      .buttonStyle(.bordered)
      .disabled(inspectionState == .loading)
      .accessibilityIdentifier("diary.mutation.reloadLatest")

      Button("이미 저장됨 · 초안 정리") {
        showsRecoveryActions = false
        onResolveAsSaved()
      }
      .buttonStyle(.bordered)
      .disabled(!canResolve || !allowsResolveAsSaved)
      .accessibilityIdentifier("diary.mutation.resolveSaved")

      Button("저장 안 됨 · 다시 시도 허용") {
        showsRecoveryActions = false
        onConfirmManualRetry()
      }
      .buttonStyle(.borderedProminent)
      .tint(WoorisaiPalette.coralDark)
      .disabled(!canResolve || !allowsManualRetry)
      .accessibilityIdentifier("diary.mutation.confirmRetry")

      if canAbandonInconclusive {
        Button("판단 불가 · 재전송 없이 초안 정리", role: .destructive) {
          confirmsAbandon = true
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("diary.mutation.abandonInconclusive")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var canResolve: Bool {
    inspectionState == .loaded
  }

  private var canAbandonInconclusive: Bool {
    // Abandon is the offline escape hatch: offer it whenever the inspection could not resolve the
    // outcome — including when the reload itself fails (offline). Hidden only while a resolved
    // inspection offers a definitive action instead.
    !canResolve || (!allowsResolveAsSaved && !allowsManualRetry)
  }

  private var recoveryMessage: String {
    switch inspectionState {
    case .idle:
      return "저장됐을 수도 있어요. 최신 내용을 먼저 불러와 중복 여부를 확인해 주세요."
    case .loading:
      return "최신 내용을 확인하고 있어요. 작성 중인 초안은 그대로 유지됩니다."
    case .loaded:
      if !allowsResolveAsSaved, !allowsManualRetry {
        return "최신 내용이 이번 수정이나 수정 전 상태와 달라요. 다시 확인하거나 재전송 없이 초안을 정리해 주세요."
      }
      return "최신 내용을 확인했어요. 일치하는 저장 결과를 선택해 주세요."
    case .failed:
      return "최신 내용을 불러오지 못했어요. 다시 시도하거나, 재전송 없이 초안을 정리하고 나갈 수 있어요."
    }
  }
}

struct DiaryMutationStatusCard: View {
  let message: String
  let onDismiss: () -> Void
  @AccessibilityFocusState private var isAccessibilityFocused: Bool

  var body: some View {
    HStack(alignment: .center, spacing: WoorisaiSpacing.small) {
      Label(message, systemImage: "heart.text.square.fill")
        .font(.callout.weight(.semibold))
        .foregroundStyle(WoorisaiPalette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.caption.weight(.bold))
          .frame(
            width: WoorisaiControlMetric.minimumTapTarget,
            height: WoorisaiControlMetric.minimumTapTarget
          )
      }
      .buttonStyle(.plain)
      .foregroundStyle(WoorisaiPalette.coralDark)
      .accessibilityLabel("알림 닫기")
    }
    .padding(.leading, WoorisaiSpacing.regular)
    .padding(.vertical, WoorisaiSpacing.xSmall)
    .padding(.trailing, WoorisaiSpacing.xSmall)
    .background(WoorisaiPalette.coralSoft.opacity(0.68))
    .clipShape(RoundedRectangle(cornerRadius: WoorisaiRadius.medium, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityFocused($isAccessibilityFocused)
    .task(id: message) {
      await Task.yield()
      isAccessibilityFocused = true
    }
  }
}

private struct DiaryReconciliationCard: View {
  let presentation: DiaryReconciliationPresentation

  var body: some View {
    WarmSurface(cornerRadius: WoorisaiRadius.medium) {
      VStack(alignment: .leading, spacing: WoorisaiSpacing.small) {
        Label(presentation.title, systemImage: "arrow.triangle.2.circlepath")
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.coralDark)
        if let latestServerContent = presentation.latestServerContent,
          presentation.state == .loaded
        {
          Text(latestServerContent)
            .font(.callout)
            .foregroundStyle(WoorisaiPalette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if presentation.state == .failed {
          Label(
            "최신 내용을 불러오지 못했어요. 다시 불러오기를 선택해 주세요.",
            systemImage: "exclamationmark.triangle.fill"
          )
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.error)
        } else if presentation.state == .loaded {
          Label(
            "서버에서 이 내용을 찾을 수 없어요. 초안을 복사해 둔 뒤 편집기를 닫아 주세요.",
            systemImage: "doc.on.clipboard"
          )
          .font(.callout)
          .foregroundStyle(WoorisaiPalette.error)
        } else {
          ProgressView("최신 내용을 불러오고 있어요.")
            .foregroundStyle(WoorisaiPalette.muted)
        }
        Text("아래 편집란에는 작성하던 초안이 그대로 남아 있어요.")
          .font(.caption)
          .foregroundStyle(WoorisaiPalette.muted)
      }
      .padding(WoorisaiSpacing.regular)
    }
    .accessibilityIdentifier("diary.reconciliation.latest")
  }
}
