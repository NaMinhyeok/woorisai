import SwiftUI
import WoorisaiAPI

enum DiaryConflictEditorDisposition: Equatable, Sendable {
  case none
  case closeEntryEditor
  case closeCommentEditor

  static func resolve(conflict: DiaryModel.Conflict?, visibleEntryID: Int64) -> Self {
    switch conflict {
    case .entry(let entryID) where entryID == visibleEntryID:
      return .closeEntryEditor
    case .comment(let entryID) where entryID == visibleEntryID:
      return .closeCommentEditor
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

  let participant: AuthenticatedParticipant
  let onSignOut: @MainActor () -> Void
  let onAuthenticationRequired: @MainActor () -> Void

  @MainActor
  init(
    model: DiaryModel,
    navigationPath: Binding<[Int64]>,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    newEntryMediaModel: MediaAttachmentComposerModel,
    participant: AuthenticatedParticipant,
    onSignOut: @escaping @MainActor () -> Void,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _newEntryMediaModel = State(initialValue: newEntryMediaModel)
    _navigationPath = navigationPath
    self.mediaService = mediaService
    self.mediaUploader = mediaUploader
    self.participant = participant
    self.onSignOut = onSignOut
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    NavigationStack(path: $navigationPath) {
      listContent
        .navigationTitle("우리 일기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
              isCreatingEntry = true
            } label: {
              Label("새 일기", systemImage: "square.and.pencil")
            }
            .disabled(model.mutationState == .submitting)
            .tint(WoorisaiPalette.coralDark)
            .accessibilityIdentifier("diary.createEntry.open")

            Button("나가기") {
              onSignOut()
            }
            .tint(WoorisaiPalette.coralDark)
            .accessibilityIdentifier("diary.signOut")
          }
        }
        .navigationDestination(for: Int64.self) { entryID in
          DiaryDetailView(
            model: model,
            entryID: entryID,
            mediaService: mediaService,
            mediaUploader: mediaUploader,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }
    }
    .accessibilityIdentifier("diary.screen")
    .task {
      model.loadIfNeeded()
    }
    .sheet(isPresented: $isCreatingEntry) {
      DiaryEntryComposer(
        title: "새 일기",
        content: $newEntryContent,
        mediaModel: newEntryMediaModel,
        retainedAttachments: [],
        mediaService: mediaService,
        isSubmitting: model.mutationState == .submitting,
        submitTitle: "기록하기",
        onRemoveRetainedAttachment: { _ in },
        onAuthenticationRequired: onAuthenticationRequired,
        onCancel: {
          newEntryMediaModel.clear()
          isCreatingEntry = false
        },
        onSubmit: {
          let uploadIDs = newEntryMediaModel.readyUploadIDs
          let accepted = model.createEntry(
            content: newEntryContent,
            mediaUploadIDs: uploadIDs
          )
          if accepted { newEntryMediaModel.markReadyUploadsSubmitted() }
        }
      )
      .presentationDetents(entryComposerDetents)
      .interactiveDismissDisabled(model.mutationState == .submitting)
    }
    .onChange(of: model.lastCreatedEntryID) { _, entryID in
      guard entryID != nil else { return }
      newEntryMediaModel.consumeReadyUploads()
      newEntryContent = ""
      isCreatingEntry = false
    }
    .onChange(of: isCreatingEntry) { oldValue, newValue in
      if oldValue, !newValue { newEntryMediaModel.clear() }
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
    .onDisappear {
      if model.mutationState != .submitting {
        if model.rejectedMediaMutation == .createEntry {
          newEntryMediaModel.releaseSubmittedUploadOwnership()
        }
        newEntryMediaModel.clear()
      }
    }
    .alert(
      "최신 일기가 필요해요",
      isPresented: Binding(
        get: { model.conflict != nil },
        set: { if !$0 { model.dismissConflict() } }
      )
    ) {
      Button("최신 내용 불러오기") {
        model.reloadAfterConflict()
      }
    } message: {
      Text("다른 변경과 겹쳐 저장하지 못했습니다. 자동으로 다시 쓰지 않고 최신 내용을 불러옵니다.")
    }
  }

  @ViewBuilder
  private var listContent: some View {
    switch model.listState {
    case .idle, .loading:
      diaryStateShell {
        BrandedStateCard {
          VStack(spacing: 14) {
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
        LazyVStack(alignment: .leading, spacing: 16) {
          DiaryHero(
            eyebrow: "OUR DIARY",
            title: "우리 일기",
            message: "점수로는 다 담지 못한 오늘의 이야기를 함께 남겨요.",
            symbol: "book.pages.fill"
          )

          createEntryPrompt

          if let notice = model.mutationNotice ?? model.listNotice {
            HStack(spacing: 10) {
              Image(systemName: "heart.text.square")
                .foregroundStyle(WoorisaiPalette.coralDark)
                .accessibilityHidden(true)
              Text(notice)
                .font(.callout)
                .foregroundStyle(WoorisaiPalette.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(15)
            .background(WoorisaiPalette.coralSoft.opacity(0.68))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityIdentifier("diary.notice")
          }

          DiarySectionHeading(
            eyebrow: "OUR STORIES",
            title: "차곡차곡 쌓인 이야기",
            detail: model.entries.isEmpty ? nil : "\(model.totalCount)개의 기록"
          )
          .padding(.top, 10)

          if model.entries.isEmpty {
            BrandedStateCard {
              VStack(spacing: 12) {
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
                .buttonStyle(.bordered)
                .tint(WoorisaiPalette.coralDark)
                .accessibilityIdentifier("diary.empty.create")
              }
              .accessibilityElement(children: .contain)
              .accessibilityIdentifier("diary.empty")
            }
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
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(WoorisaiPalette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay {
                  RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(WoorisaiPalette.line, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("diary.nextPage")
          }
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        model.reload()
      }
    }
    .accessibilityIdentifier("diary.loaded")
  }

  private var createEntryPrompt: some View {
    WarmSurface(cornerRadius: 24) {
      VStack(alignment: .leading, spacing: 16) {
        Group {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
              ParticipantAvatar(name: participant.displayName, size: 44)
              createEntryPromptCopy
            }
          } else {
            HStack(alignment: .top, spacing: 14) {
              ParticipantAvatar(name: participant.displayName, size: 44)
              createEntryPromptCopy
              Spacer(minLength: 0)
              Image(systemName: "square.and.pencil")
                .font(.title3.weight(.semibold))
                .foregroundStyle(WoorisaiPalette.coralDark)
                .padding(10)
                .background(WoorisaiPalette.coralSoft, in: RoundedRectangle(cornerRadius: 13))
                .accessibilityHidden(true)
            }
          }
        }

        PrimaryHeartButton(
          "이야기 남기기",
          isEnabled: model.mutationState != .submitting
        ) {
          isCreatingEntry = true
        }
        .accessibilityIdentifier("diary.createEntry.prompt")
      }
      .padding(18)
    }
  }

  private var createEntryPromptCopy: some View {
    VStack(alignment: .leading, spacing: 5) {
      Eyebrow("SHARE A STORY")
      Text("\(participant.displayName)님의 오늘은 어땠나요?")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
        .fixedSize(horizontal: false, vertical: true)
      Text("이 글은 우리 둘에게만 보여요.")
        .font(.footnote)
        .foregroundStyle(WoorisaiPalette.muted)
    }
  }

  private var entryComposerDetents: Set<PresentationDetent> {
    dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
  }

  private func diaryStateShell<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      ScrollView {
        VStack(spacing: 20) {
          DiaryHero(
            eyebrow: "OUR DIARY",
            title: "우리 일기",
            message: "점수로는 다 담지 못한 오늘의 이야기를 함께 남겨요.",
            symbol: "book.pages.fill"
          )
          content()
        }
        .frame(maxWidth: 680)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func listError(_ message: String, _ identifier: String) -> some View {
    diaryStateShell {
      BrandedStateCard {
        VStack(spacing: 14) {
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
          Button("다시 시도") { model.reload() }
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

private struct DiaryEntryCard: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let entry: DiaryEntry
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  var body: some View {
    WarmSurface(cornerRadius: 24) {
      VStack(alignment: .leading, spacing: 15) {
        NavigationLink(value: entry.id) {
          VStack(alignment: .leading, spacing: 15) {
            entryHeader

            Text(entry.content)
              .font(.body)
              .foregroundStyle(WoorisaiPalette.ink.opacity(0.88))
              .lineSpacing(5)
              .lineLimit(5)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("diary.entry.\(entry.id).open")

        if !entry.attachments.isEmpty {
          DiaryAttachmentGallery(
            attachments: entry.attachments,
            mediaService: mediaService,
            onAuthenticationRequired: onAuthenticationRequired
          )
        }

        Divider()
          .overlay(WoorisaiPalette.line)

        Group {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
              entryMetadata
              conversationLink
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          } else {
            HStack(spacing: 14) {
              entryMetadata
              Spacer(minLength: 0)
              conversationLink
            }
          }
        }
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
      }
      .padding(18)
    }
    .overlay {
      if entry.isMine {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
          .stroke(WoorisaiPalette.coral.opacity(0.24), lineWidth: 1)
      }
    }
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var entryHeader: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        ParticipantAvatar(name: entry.author.displayName, size: 42)
        authorIdentity
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        ParticipantAvatar(name: entry.author.displayName, size: 42)
        authorIdentity
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.caption.weight(.bold))
          .foregroundStyle(WoorisaiPalette.coralDark)
          .padding(.top, 8)
          .accessibilityHidden(true)
      }
    }
  }

  private var authorIdentity: some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 7) {
        Text(entry.author.displayName)
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if entry.isMine {
          Text("내 기록")
            .font(.caption2.weight(.bold))
            .foregroundStyle(WoorisaiPalette.coralDark)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(WoorisaiPalette.coralSoft, in: Capsule())
        }
      }
      Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
    }
  }

  @ViewBuilder
  private var entryMetadata: some View {
    HStack(spacing: 14) {
      if !entry.attachments.isEmpty {
        Label("첨부 \(entry.attachments.count)", systemImage: "paperclip")
      }
      Label("댓글 \(entry.commentCount)", systemImage: "bubble.left")
    }
  }

  private var conversationLink: some View {
    NavigationLink(value: entry.id) {
      Label("대화 보기", systemImage: "chevron.right")
        .fontWeight(.semibold)
        .foregroundStyle(WoorisaiPalette.coralDark)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("diary.entry.\(entry.id).conversation")
  }
}

private struct DiaryAttachmentGallery: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let attachments: [DiaryAttachment]
  let mediaService: any MediaServing
  let onAuthenticationRequired: @MainActor () -> Void

  private var columns: [GridItem] {
    let count = attachments.count > 1 && !dynamicTypeSize.isAccessibilitySize ? 2 : 1
    return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 10) {
      ForEach(attachments) { attachment in
        MediaAttachmentPreview(
          attachmentID: attachment.id,
          fileName: attachment.fileName,
          contentType: attachment.contentType,
          byteSize: attachment.byteSize,
          onAuthenticationRequired: onAuthenticationRequired
        )
      }
    }
  }
}

private struct DiaryHero: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let eyebrow: LocalizedStringKey
  let title: LocalizedStringKey
  let message: LocalizedStringKey
  let symbol: String

  var body: some View {
    VStack(spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 30, weight: .semibold))
        .foregroundStyle(WoorisaiPalette.coral)
        .frame(width: 58, height: 58)
        .background(WoorisaiPalette.coralSoft.opacity(0.82), in: Circle())
        .accessibilityHidden(true)
      Eyebrow(eyebrow)
      Text(title)
        .font(dynamicTypeSize.isAccessibilitySize ? .title.bold() : .largeTitle.bold())
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      Text(message)
        .font(.callout)
        .foregroundStyle(WoorisaiPalette.muted)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

private struct DiarySectionHeading: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let eyebrow: LocalizedStringKey
  let title: LocalizedStringKey
  let detail: String?

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 8) {
          heading
          detailLabel
        }
      } else {
        HStack(alignment: .bottom, spacing: 12) {
          heading
          Spacer(minLength: 0)
          detailLabel
        }
      }
    }
  }

  private var heading: some View {
    VStack(alignment: .leading, spacing: 4) {
      Eyebrow(eyebrow)
      Text(title)
        .font(.title3.bold())
        .foregroundStyle(WoorisaiPalette.ink)
        .accessibilityAddTraits(.isHeader)
    }
  }

  @ViewBuilder
  private var detailLabel: some View {
    if let detail {
      Text(detail)
        .font(.caption)
        .foregroundStyle(WoorisaiPalette.muted)
    }
  }
}

private struct DiaryDetailView: View {
  private enum FocusedField: Hashable {
    case comment
    case commentEditor
  }

  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var model: DiaryModel
  @State private var entryEditMediaModel: MediaAttachmentComposerModel
  @State private var commentContent = ""
  @State private var isEditingEntry = false
  @State private var entryEditContent = ""
  @State private var editingComment: DiaryComment?
  @State private var commentEditContent = ""
  @State private var confirmsEntryDeletion = false
  @State private var initialEntryAttachmentIDs: [UUID] = []
  @State private var retainedEntryAttachments: [DiaryAttachment] = []
  @FocusState private var focusedField: FocusedField?

  let entryID: Int64
  let onAuthenticationRequired: @MainActor () -> Void
  private let mediaService: any MediaServing

  @MainActor
  init(
    model: DiaryModel,
    entryID: Int64,
    mediaService: any MediaServing,
    mediaUploader: any PresignedMediaUploading,
    onAuthenticationRequired: @escaping @MainActor () -> Void
  ) {
    _model = State(initialValue: model)
    _entryEditMediaModel = State(
      initialValue: MediaAttachmentComposerModel(
        purpose: .diaryEntry,
        service: mediaService,
        uploader: mediaUploader
      )
    )
    self.entryID = entryID
    self.mediaService = mediaService
    self.onAuthenticationRequired = onAuthenticationRequired
  }

  var body: some View {
    Group {
      switch model.detailState {
      case .idle, .loading:
        detailStateShell {
          BrandedStateCard {
            VStack(spacing: 14) {
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
        detailError("이 일기는 더 이상 존재하지 않아요.")
      case .unavailable:
        detailError("일기를 잠시 사용할 수 없어요.")
      case .failed:
        detailError("일기를 불러오지 못했어요.")
      }
    }
    .navigationTitle("일기 대화")
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(model.mutationState == .submitting)
    .toolbar {
      KeyboardDismissToolbar {
        focusedField = nil
      }
    }
    .task(id: entryID) {
      model.loadDetail(entryID: entryID)
    }
    .onDisappear {
      focusedField = nil
      model.cancelDetailReadForScreenExit(entryID: entryID)
      if model.mutationState != .submitting {
        if model.rejectedMediaMutation == .updateEntry(entryID: entryID) {
          entryEditMediaModel.releaseSubmittedUploadOwnership()
        }
        entryEditMediaModel.clear()
      }
    }
    .onChange(of: model.selectedEntryID) { oldValue, newValue in
      if oldValue == entryID, newValue == nil, model.mutationNotice == "일기를 삭제했어요." {
        dismiss()
      }
    }
    .sheet(isPresented: $isEditingEntry) {
      DiaryEntryComposer(
        title: "일기 수정",
        content: $entryEditContent,
        mediaModel: entryEditMediaModel,
        retainedAttachments: retainedEntryAttachments,
        mediaService: mediaService,
        isSubmitting: model.mutationState == .submitting,
        submitTitle: "수정하기",
        onRemoveRetainedAttachment: { attachmentID in
          retainedEntryAttachments.removeAll { $0.id == attachmentID }
          entryEditMediaModel.setExistingKinds(
            retainedEntryAttachments.map { attachment in
              attachment.kind == .image ? .image : .video
            }
          )
        },
        onAuthenticationRequired: onAuthenticationRequired,
        onCancel: {
          entryEditMediaModel.clear()
          isEditingEntry = false
        },
        onSubmit: {
          let uploadIDs = entryEditMediaModel.readyUploadIDs
          let accepted = model.updateEntry(
            entryID: entryID,
            content: entryEditContent,
            attachments: entryAttachmentUpdate(newUploadIDs: uploadIDs)
          )
          if accepted { entryEditMediaModel.markReadyUploadsSubmitted() }
        }
      )
      .presentationDetents(entryEditorDetents)
      .interactiveDismissDisabled(model.mutationState == .submitting)
    }
    .sheet(
      item: $editingComment,
      onDismiss: { focusedField = nil }
    ) { comment in
      NavigationStack {
        WarmBackground {
          ScrollView {
            VStack(alignment: .leading, spacing: 18) {
              DiaryHero(
                eyebrow: "EDIT REPLY",
                title: "댓글 다듬기",
                message: "마음을 다시 읽어 보고 천천히 고쳐 보세요.",
                symbol: "bubble.left.and.text.bubble.right.fill"
              )

              WarmSurface {
                VStack(alignment: .leading, spacing: 10) {
                  HStack {
                    Text("댓글")
                      .font(.headline)
                      .foregroundStyle(WoorisaiPalette.ink)
                    Spacer()
                    Text(
                      "\(commentEditCodePointCount)/\(DiaryCommentDraft.maximumContentCharacterCount)"
                    )
                      .font(.caption.monospacedDigit())
                      .foregroundStyle(
                        commentEditCodePointCount > DiaryCommentDraft.maximumContentCharacterCount
                          ? WoorisaiPalette.error : WoorisaiPalette.muted
                      )
                  }
                  TextEditor(text: $commentEditContent)
                    .frame(minHeight: 150)
                    .focused($focusedField, equals: .commentEditor)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(WoorisaiPalette.ink)
                    .tint(WoorisaiPalette.coralDark)
                    .padding(10)
                    .background(WoorisaiPalette.field)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                      RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WoorisaiPalette.line, lineWidth: 1)
                    }
                }
                .padding(18)
              }
            }
            .frame(maxWidth: 680)
            .padding(20)
            .frame(maxWidth: .infinity)
          }
          .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("댓글 수정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button("취소") {
              focusedField = nil
              editingComment = nil
            }
            .disabled(model.mutationState == .submitting)
          }
          ToolbarItem(placement: .confirmationAction) {
            Button("수정") {
              focusedField = nil
              model.updateComment(
                entryID: entryID,
                commentID: comment.id,
                content: commentEditContent
              )
            }
            .disabled(
              WoorisaiTextInput.normalized(commentEditContent).isEmpty
                || commentEditCodePointCount > DiaryCommentDraft.maximumContentCharacterCount
                || model.mutationState == .submitting
            )
          }
          KeyboardDismissToolbar {
            focusedField = nil
          }
        }
        .onAppear {
          focusedField = .commentEditor
        }
      }
      .presentationDetents(commentEditorDetents)
      .interactiveDismissDisabled(model.mutationState == .submitting)
    }
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
    .onChange(of: model.lastUpdatedEntryID) { _, updatedID in
      guard updatedID == entryID else { return }
      entryEditMediaModel.consumeReadyUploads()
      isEditingEntry = false
    }
    .onChange(of: isEditingEntry) { oldValue, newValue in
      if oldValue, !newValue { entryEditMediaModel.clear() }
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
      case .closeEntryEditor:
        entryEditMediaModel.releaseSubmittedUploadOwnership()
        entryEditMediaModel.clear()
        entryEditContent = ""
        retainedEntryAttachments = []
        initialEntryAttachmentIDs = []
        isEditingEntry = false
      case .closeCommentEditor:
        commentEditContent = ""
        editingComment = nil
      case .none:
        break
      }
    }
  }

  private var detailList: some View {
    WarmBackground {
      ScrollView {
        if let detail = model.selectedDetail {
          LazyVStack(alignment: .leading, spacing: 18) {
            DiaryHero(
              eyebrow: "DIARY TALK",
              title: "이 이야기에 대한 대화",
              message: "함께 남긴 순간에 천천히 답장을 건네 보세요.",
              symbol: "bubble.left.and.text.bubble.right.fill"
            )

            diaryOriginCard(detail.entry)

            if let notice = model.mutationNotice {
              HStack(spacing: 10) {
                Image(systemName: "heart.circle.fill")
                  .foregroundStyle(WoorisaiPalette.coralDark)
                  .accessibilityHidden(true)
                Text(notice)
                  .font(.callout)
                  .foregroundStyle(WoorisaiPalette.ink)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(15)
              .background(WoorisaiPalette.coralSoft.opacity(0.68))
              .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            DiarySectionHeading(
              eyebrow: "COMMENTS",
              title: "둘만의 대화",
              detail: "댓글 \(detail.comments.count)"
            )
            .padding(.top, 8)

            WarmSurface(cornerRadius: 24) {
              VStack(spacing: 16) {
                if detail.comments.isEmpty {
                  VStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                      .font(.title2)
                      .foregroundStyle(WoorisaiPalette.sage)
                      .accessibilityHidden(true)
                    Text("아직 댓글이 없어요.")
                      .font(.headline)
                      .foregroundStyle(WoorisaiPalette.ink)
                    Text("먼저 다정한 이야기를 건네 보세요.")
                      .font(.callout)
                      .foregroundStyle(WoorisaiPalette.muted)
                  }
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 22)
                } else {
                  ForEach(detail.comments) { comment in
                    DiaryCommentBubble(
                      comment: comment,
                      isSubmitting: model.mutationState == .submitting,
                      onEdit: {
                        focusedField = nil
                        commentEditContent = comment.content
                        editingComment = comment
                      },
                      onDelete: {
                        model.deleteComment(entryID: entryID, commentID: comment.id)
                      }
                    )
                    .accessibilityIdentifier("diary.comment.\(comment.id)")
                  }
                }

                Divider()
                  .overlay(WoorisaiPalette.line)

                commentComposer
              }
              .padding(18)
            }
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 40)
          .frame(maxWidth: .infinity)
        }
      }
      .scrollDismissesKeyboard(.interactively)
      .refreshable {
        model.loadDetail(entryID: entryID)
      }
    }
    .onChange(of: model.mutationNotice) { _, notice in
      if notice == "댓글을 남겼어요." {
        commentContent = ""
        focusedField = nil
      }
      if notice == "일기를 수정했어요." { isEditingEntry = false }
      if notice == "댓글을 수정했어요." {
        focusedField = nil
        editingComment = nil
      }
    }
    .accessibilityIdentifier("diary.detail.loaded")
  }

  private func diaryOriginCard(_ entry: DiaryEntry) -> some View {
    WarmSurface(cornerRadius: 24) {
      VStack(alignment: .leading, spacing: 16) {
        diaryOriginHeader(entry)

        Text(entry.content)
          .font(.body)
          .foregroundStyle(WoorisaiPalette.ink)
          .lineSpacing(6)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)

        if !entry.attachments.isEmpty {
          VStack(alignment: .leading, spacing: 10) {
            Divider()
              .overlay(WoorisaiPalette.line)
            Text("첨부")
              .font(.caption.bold())
              .foregroundStyle(WoorisaiPalette.muted)
            DiaryAttachmentGallery(
              attachments: entry.attachments,
              mediaService: mediaService,
              onAuthenticationRequired: onAuthenticationRequired
            )
          }
        }

        if entry.isMine {
          Divider()
            .overlay(WoorisaiPalette.line)
          Group {
            if dynamicTypeSize.isAccessibilitySize {
              VStack(spacing: 10) { diaryActionButtons(entry) }
            } else {
              HStack(spacing: 12) { diaryActionButtons(entry) }
            }
          }
          .disabled(model.mutationState == .submitting)
        }
      }
      .padding(18)
    }
    .overlay {
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(WoorisaiPalette.coral.opacity(0.24), lineWidth: 1)
    }
  }

  @ViewBuilder
  private func diaryOriginHeader(_ entry: DiaryEntry) -> some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: .leading, spacing: 10) {
        ParticipantAvatar(name: entry.author.displayName, size: 44)
        diaryOriginIdentity(entry)
        if entry.updatedAt != nil {
          Text("수정됨")
            .font(.caption2)
            .foregroundStyle(WoorisaiPalette.muted)
        }
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        ParticipantAvatar(name: entry.author.displayName, size: 44)
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
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 7) {
        Text(entry.author.displayName)
          .font(.headline)
          .foregroundStyle(WoorisaiPalette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if entry.isMine {
          Text("내 기록")
            .font(.caption2.bold())
            .foregroundStyle(WoorisaiPalette.coralDark)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
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
        .frame(maxWidth: .infinity, minHeight: 42)
    }
    .buttonStyle(.bordered)
    .tint(WoorisaiPalette.coralDark)

    Button(role: .destructive) {
      confirmsEntryDeletion = true
    } label: {
      Label("일기 삭제", systemImage: "trash")
        .frame(maxWidth: .infinity, minHeight: 42)
    }
    .buttonStyle(.bordered)
  }

  private var commentComposer: some View {
    VStack(alignment: .leading, spacing: 12) {
      Group {
        if dynamicTypeSize.isAccessibilitySize {
          VStack(alignment: .leading, spacing: 6) { commentComposerHeading }
        } else {
          HStack { commentComposerHeading }
        }
      }

      TextField("이 일기에 답장을 남겨 보세요", text: $commentContent, axis: .vertical)
        .lineLimit(3...6)
        .focused($focusedField, equals: .comment)
        .foregroundStyle(WoorisaiPalette.ink)
        .tint(WoorisaiPalette.coralDark)
        .padding(12)
        .background(WoorisaiPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(WoorisaiPalette.line, lineWidth: 1)
        }
        .accessibilityIdentifier("diary.comment.input")

      PrimaryHeartButton(
        "댓글 남기기",
        isEnabled: !WoorisaiTextInput.normalized(commentContent).isEmpty
          && commentCodePointCount <= DiaryCommentDraft.maximumContentCharacterCount,
        isLoading: model.mutationState == .submitting
      ) {
        focusedField = nil
        model.createComment(entryID: entryID, content: commentContent)
      }
      .accessibilityIdentifier("diary.comment.create")
    }
  }

  @ViewBuilder
  private var commentComposerHeading: some View {
    VStack(alignment: .leading, spacing: 3) {
      Eyebrow("LEAVE A REPLY")
      Text("댓글 달기")
        .font(.headline)
        .foregroundStyle(WoorisaiPalette.ink)
    }
    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
    Text(
      "\(commentCodePointCount)/\(DiaryCommentDraft.maximumContentCharacterCount)"
    )
      .font(.caption.monospacedDigit())
      .foregroundStyle(
        commentCodePointCount > DiaryCommentDraft.maximumContentCharacterCount
          ? WoorisaiPalette.error : WoorisaiPalette.muted
      )
  }

  private func beginEditing(_ entry: DiaryEntry) {
    focusedField = nil
    entryEditContent = entry.content
    initialEntryAttachmentIDs = entry.attachments.map(\.id)
    retainedEntryAttachments = entry.attachments
    entryEditMediaModel.clear()
    entryEditMediaModel.setExistingKinds(
      entry.attachments.map { attachment in
        attachment.kind == .image ? .image : .video
      }
    )
    isEditingEntry = true
  }

  private var commentEditCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(commentEditContent)
  }

  private var commentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(commentContent)
  }

  private func detailStateShell<Content: View>(
    @ViewBuilder content: () -> Content
  ) -> some View {
    WarmBackground {
      ScrollView {
        VStack(spacing: 20) {
          DiaryHero(
            eyebrow: "DIARY TALK",
            title: "이 이야기에 대한 대화",
            message: "함께 남긴 순간에 천천히 답장을 건네 보세요.",
            symbol: "bubble.left.and.text.bubble.right.fill"
          )
          content()
        }
        .frame(maxWidth: 680)
        .padding(20)
        .frame(maxWidth: .infinity)
      }
    }
  }

  private func detailError(_ message: String) -> some View {
    detailStateShell {
      BrandedStateCard {
        VStack(spacing: 14) {
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
          Button("다시 시도") { model.loadDetail(entryID: entryID) }
            .buttonStyle(.borderedProminent)
            .tint(WoorisaiPalette.primaryButtonStart)
            .foregroundStyle(WoorisaiPalette.primaryButtonLabel)
        }
      }
    }
  }

  private func entryAttachmentUpdate(newUploadIDs: [UUID]) -> DiaryAttachmentUpdate {
    let retainedIDs = retainedEntryAttachments.map(\.id)
    if retainedIDs == initialEntryAttachmentIDs, newUploadIDs.isEmpty {
      return .preserve
    }
    return .replace(retainedIDs + newUploadIDs)
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
  let isSubmitting: Bool
  let onEdit: () -> Void
  let onDelete: () -> Void

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        commentBody
          .frame(maxWidth: .infinity, alignment: comment.isMine ? .trailing : .leading)
      } else {
        HStack(alignment: .bottom, spacing: 8) {
          if comment.isMine {
            Spacer(minLength: 42)
          } else {
            ParticipantAvatar(name: comment.author.displayName, size: 30)
          }

          commentBody

          if comment.isMine {
            ParticipantAvatar(name: comment.author.displayName, size: 30)
          } else {
            Spacer(minLength: 42)
          }
        }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .contain)
  }

  private var commentBody: some View {
    VStack(alignment: comment.isMine ? .trailing : .leading, spacing: 5) {
      commentMetadata

      Text(comment.content)
        .font(.body)
        .foregroundStyle(WoorisaiPalette.ink)
        .multilineTextAlignment(.leading)
        .lineSpacing(3)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(comment.isMine ? WoorisaiPalette.coralSoft : WoorisaiPalette.field)
        .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 17, style: .continuous)
            .stroke(
              comment.isMine
                ? WoorisaiPalette.coral.opacity(0.2) : WoorisaiPalette.line,
              lineWidth: 1
            )
        }
    }
  }

  @ViewBuilder
  private var commentMetadata: some View {
    if dynamicTypeSize.isAccessibilitySize {
      VStack(alignment: comment.isMine ? .trailing : .leading, spacing: 3) {
        commentAuthor
        commentTimestamp
        commentManagementMenu
      }
    } else {
      HStack(spacing: 7) {
        commentAuthor
        commentTimestamp
        commentManagementMenu
      }
    }
  }

  private var commentAuthor: some View {
    Text(comment.author.displayName)
      .font(.caption.bold())
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
          .frame(width: 44, height: 44)
      }
      .disabled(isSubmitting)
      .accessibilityLabel("내 댓글 관리")
    }
  }
}

private struct DiaryEntryComposer: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let title: LocalizedStringKey
  @Binding var content: String
  @State private var mediaModel: MediaAttachmentComposerModel
  @FocusState private var isContentFocused: Bool
  let retainedAttachments: [DiaryAttachment]
  let mediaService: any MediaServing
  let isSubmitting: Bool
  let submitTitle: LocalizedStringKey
  let onRemoveRetainedAttachment: (UUID) -> Void
  let onAuthenticationRequired: @MainActor () -> Void
  let onCancel: () -> Void
  let onSubmit: () -> Void

  @MainActor
  init(
    title: LocalizedStringKey,
    content: Binding<String>,
    mediaModel: MediaAttachmentComposerModel,
    retainedAttachments: [DiaryAttachment],
    mediaService: any MediaServing,
    isSubmitting: Bool,
    submitTitle: LocalizedStringKey,
    onRemoveRetainedAttachment: @escaping (UUID) -> Void,
    onAuthenticationRequired: @escaping @MainActor () -> Void,
    onCancel: @escaping () -> Void,
    onSubmit: @escaping () -> Void
  ) {
    self.title = title
    _content = content
    _mediaModel = State(initialValue: mediaModel)
    self.retainedAttachments = retainedAttachments
    self.mediaService = mediaService
    self.isSubmitting = isSubmitting
    self.submitTitle = submitTitle
    self.onRemoveRetainedAttachment = onRemoveRetainedAttachment
    self.onAuthenticationRequired = onAuthenticationRequired
    self.onCancel = onCancel
    self.onSubmit = onSubmit
  }

  var body: some View {
    NavigationStack {
      WarmBackground {
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            DiaryHero(
              eyebrow: "SHARE A STORY",
              title: title,
              message: "지금 나누고 싶은 순간이나 마음을 천천히 적어 주세요.",
              symbol: "square.and.pencil"
            )

            WarmSurface(cornerRadius: 24) {
              VStack(alignment: .leading, spacing: 11) {
                Group {
                  if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 6) { contentHeading }
                  } else {
                    HStack(alignment: .firstTextBaseline) { contentHeading }
                  }
                }

                TextEditor(text: $content)
                  .frame(minHeight: 210)
                  .focused($isContentFocused)
                  .scrollContentBackground(.hidden)
                  .foregroundStyle(WoorisaiPalette.ink)
                  .tint(WoorisaiPalette.coralDark)
                  .padding(10)
                  .background(WoorisaiPalette.field)
                  .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                  .overlay {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                      .stroke(WoorisaiPalette.line, lineWidth: 1)
                  }
                  .accessibilityLabel("일기 내용")
                  .accessibilityIdentifier("diary.entry.content")

                Label("이 글은 우리 둘에게만 보여요.", systemImage: "lock.fill")
                  .font(.footnote)
                  .foregroundStyle(WoorisaiPalette.muted)
              }
              .padding(18)
            }

            if !retainedAttachments.isEmpty {
              WarmSurface(cornerRadius: 24) {
                VStack(alignment: .leading, spacing: 12) {
                  DiarySectionHeading(
                    eyebrow: "CURRENT MEDIA",
                    title: "현재 첨부",
                    detail: "\(retainedAttachments.count)개"
                  )

                  LazyVGrid(columns: retainedColumns, spacing: 12) {
                    ForEach(retainedAttachments) { attachment in
                      VStack(spacing: 8) {
                        MediaAttachmentPreview(
                          attachmentID: attachment.id,
                          fileName: attachment.fileName,
                          contentType: attachment.contentType,
                          byteSize: attachment.byteSize,
                          onAuthenticationRequired: onAuthenticationRequired
                        )
                        Button(role: .destructive) {
                          onRemoveRetainedAttachment(attachment.id)
                        } label: {
                          Label("첨부에서 제거", systemImage: "trash")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .buttonStyle(.bordered)
                      }
                    }
                  }
                }
                .padding(18)
              }
            }

            WarmSurface(cornerRadius: 24) {
              VStack(alignment: .leading, spacing: 12) {
                DiarySectionHeading(
                  eyebrow: "ADD A MEMORY",
                  title: "사진·영상 추가",
                  detail: "선택"
                )
                MediaAttachmentComposer(model: mediaModel)
                Text("사진은 최대 4장, 영상은 1개까지 첨부할 수 있어요.")
                  .font(.footnote)
                  .foregroundStyle(WoorisaiPalette.muted)
              }
              .padding(18)
            }

            PrimaryHeartButton(
              submitTitle,
              isEnabled: canSubmit,
              isLoading: isSubmitting,
              action: submit
            )
            .accessibilityIdentifier("diary.entry.submit")
          }
          .frame(maxWidth: 680)
          .padding(.horizontal, 20)
          .padding(.top, 18)
          .padding(.bottom, 40)
          .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("취소", action: cancel)
            .disabled(isSubmitting)
            .tint(WoorisaiPalette.coralDark)
        }
        KeyboardDismissToolbar {
          isContentFocused = false
        }
      }
      .onChange(of: mediaModel.hasAuthenticationFailure) { _, required in
        if required { onAuthenticationRequired() }
      }
      .onDisappear {
        isContentFocused = false
      }
    }
  }

  private var canSubmit: Bool {
    !WoorisaiTextInput.normalized(content).isEmpty
      && contentCodePointCount <= DiaryEntryCreateDraft.maximumContentCharacterCount
      && !isSubmitting
      && mediaModel.isReadyForSubmission
  }

  private var contentCodePointCount: Int {
    WoorisaiTextInput.normalizedCodePointCount(content)
  }

  private func cancel() {
    isContentFocused = false
    onCancel()
  }

  private func submit() {
    isContentFocused = false
    onSubmit()
  }

  private var retainedColumns: [GridItem] {
    let count = retainedAttachments.count > 1 && !dynamicTypeSize.isAccessibilitySize ? 2 : 1
    return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
  }

  @ViewBuilder
  private var contentHeading: some View {
    Text("우리에게 남길 이야기")
      .font(.headline)
      .foregroundStyle(WoorisaiPalette.ink)
    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
    Text(
      "\(contentCodePointCount)/\(DiaryEntryCreateDraft.maximumContentCharacterCount)"
    )
      .font(.caption.monospacedDigit())
      .foregroundStyle(
        contentCodePointCount > DiaryEntryCreateDraft.maximumContentCharacterCount
          ? WoorisaiPalette.error : WoorisaiPalette.muted
      )
  }
}
