import Foundation
import Observation
import WoorisaiAPI

@MainActor
@Observable
final class DiaryModel {
  enum ListState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable
    case failed
  }

  enum DetailState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case notFound
    case unavailable
    case failed
  }

  enum MutationState: Equatable, Sendable {
    case idle
    case submitting
    case failed
  }

  enum ReconciliationState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
  }

  enum Conflict: Equatable, Sendable {
    case entry(entryID: Int64)
    case comment(entryID: Int64)
  }

  enum RejectedMediaMutation: Equatable, Sendable {
    case createEntry
    case updateEntry(entryID: Int64)
  }

  enum UnknownMutationContext: Hashable, Sendable {
    case createEntry
    case updateEntry(entryID: Int64)
    case deleteEntry(entryID: Int64)
    case createComment(entryID: Int64)
    case updateComment(entryID: Int64, commentID: Int64)
    case deleteComment(entryID: Int64, commentID: Int64)
  }

  struct MutationRevision: Equatable, Sendable {
    let createdAt: Date
    let updatedAt: Date?
  }

  enum SubmittedMutationSnapshot: Equatable, Sendable {
    case updateEntry(
      entryID: Int64,
      content: String?,
      attachmentIDs: [UUID]?,
      originalContent: String?,
      originalAttachmentIDs: [UUID]?,
      originalRevision: MutationRevision?
    )
    case updateComment(
      entryID: Int64,
      commentID: Int64,
      content: String,
      originalContent: String?,
      originalRevision: MutationRevision?
    )

    var context: UnknownMutationContext {
      switch self {
      case .updateEntry(let entryID, _, _, _, _, _):
        return .updateEntry(entryID: entryID)
      case .updateComment(let entryID, let commentID, _, _, _):
        return .updateComment(entryID: entryID, commentID: commentID)
      }
    }
  }

  private(set) var listState: ListState = .idle
  private(set) var detailState: DetailState = .idle
  private(set) var mutationState: MutationState = .idle
  private(set) var entries: [DiaryEntry] = []
  private(set) var currentPage = 0
  private(set) var hasNextPage = false
  private(set) var totalCount: Int64 = 0
  private(set) var selectedEntryID: Int64?
  private(set) var selectedDetail: DiaryEntryDetail?
  private(set) var conflict: Conflict?
  private(set) var rejectedMediaMutation: RejectedMediaMutation?
  private(set) var lastConflictEditorInvalidation: Conflict?
  private(set) var authenticationRequired = false
  private(set) var listNotice: String?
  private(set) var mutationNotice: String?
  private(set) var lastCreatedEntryID: Int64?
  private(set) var lastUpdatedEntryID: Int64?
  private(set) var commentDrafts: [Int64: String] = [:]
  private(set) var mutationOutcomeRequiresConfirmation = false
  private(set) var editorReconciliationState: ReconciliationState = .idle
  private(set) var reconciliationContentUnavailable = false
  private(set) var unknownMutationContext: UnknownMutationContext?
  private(set) var inspectedUnknownMutationContext: UnknownMutationContext?
  private(set) var submittedMutationSnapshot: SubmittedMutationSnapshot?
  private(set) var manualRetryDraftContext: UnknownMutationContext?
  private(set) var protectedLocalDraftContexts: Set<UnknownMutationContext> = []

  var hasProtectedManualRetryDraft: Bool {
    manualRetryDraftContext != nil
  }

  var hasProtectedLocalDraft: Bool {
    !protectedLocalDraftContexts.isEmpty
  }

  @ObservationIgnored
  private let service: any DiaryServing

  @ObservationIgnored
  private var listTask: Task<Void, Never>?

  @ObservationIgnored
  private var pageTask: Task<Void, Never>?

  @ObservationIgnored
  private var detailTask: Task<Void, Never>?

  @ObservationIgnored
  private var mutationTask: Task<Void, Never>?

  @ObservationIgnored
  private var listGeneration: UInt = 0

  @ObservationIgnored
  private var detailReadGeneration: UInt = 0

  @ObservationIgnored
  private var selectionGeneration: UInt = 0

  @ObservationIgnored
  private var mutationGeneration: UInt = 0

  init(service: any DiaryServing) {
    self.service = service
  }

  func loadIfNeeded() {
    guard listState == .idle else { return }
    reload()
  }

  func reload(
    preservingVisibleContent: Bool = false,
    updatesEditorReconciliation: Bool = false
  ) {
    if !updatesEditorReconciliation,
      editorReconciliationState == .loading,
      inspectedUnknownMutationContext == unknownMutationContext,
      inspectedUnknownMutationContext == .createEntry
    {
      editorReconciliationState = .failed
    }
    listGeneration &+= 1
    let generation = listGeneration
    let service = service
    listTask?.cancel()
    pageTask?.cancel()
    pageTask = nil
    let keepsVisibleContent = preservingVisibleContent && listState == .loaded
    if !keepsVisibleContent {
      listState = .loading
      listNotice = nil
    }

    listTask = Task { @MainActor [weak self] in
      do {
        let page = try await service.loadDiaryEntries(pageNumber: 1)
        try Task.checkCancellation()
        guard let self, self.listGeneration == generation else { return }
        self.entries = page.entries
        self.currentPage = page.pageNumber
        self.hasNextPage = page.hasNext
        self.totalCount = page.totalCount
        self.listState = .loaded
        if updatesEditorReconciliation {
          self.editorReconciliationState = .loaded
        }
        self.listTask = nil
      } catch is CancellationError {
        guard let self, self.listGeneration == generation else { return }
        self.listTask = nil
        if updatesEditorReconciliation {
          self.editorReconciliationState = .failed
        }
        if keepsVisibleContent {
          self.listState = .loaded
          self.listNotice = "최신 일기 확인이 중단됐어요. 현재 목록은 그대로 두었어요."
        } else {
          self.listState = .failed
        }
      } catch {
        guard let self, self.listGeneration == generation else { return }
        self.listTask = nil
        if self.handleAuthenticationFailure(error) { return }
        if updatesEditorReconciliation {
          self.editorReconciliationState = .failed
        }
        if keepsVisibleContent {
          self.listState = .loaded
          self.listNotice = "최신 일기를 불러오지 못했어요. 현재 목록은 그대로 두었어요."
          return
        }
        self.listState =
          error as? WoorisaiAPIError == .serviceUnavailable
          ? .unavailable : .failed
      }
    }
  }

  func refresh() async {
    reload(preservingVisibleContent: true)
    let task = listTask
    await task?.value
  }

  func loadNextPage() {
    guard listState == .loaded, hasNextPage, pageTask == nil else { return }
    let expectedPage = currentPage + 1
    let generation = listGeneration
    let service = service

    pageTask = Task { @MainActor [weak self] in
      do {
        let page = try await service.loadDiaryEntries(pageNumber: expectedPage)
        try Task.checkCancellation()
        guard let self, self.listGeneration == generation else { return }
        let knownIDs = Set(self.entries.map(\.id))
        guard page.entries.allSatisfy({ !knownIDs.contains($0.id) }) else {
          throw WoorisaiAPIError.schemaDrift
        }
        self.entries.append(contentsOf: page.entries)
        self.currentPage = page.pageNumber
        self.hasNextPage = page.hasNext
        self.totalCount = page.totalCount
        self.pageTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.listGeneration == generation else { return }
        self.pageTask = nil
        if self.handleAuthenticationFailure(error) { return }
        self.listNotice = "다음 일기를 불러오지 못했어요. 다시 시도해 주세요."
      }
    }
  }

  func loadDetail(
    entryID: Int64,
    preservingVisibleContent: Bool = false,
    reconciliationConflict: Conflict? = nil,
    updatesEditorReconciliation: Bool = false
  ) {
    if !updatesEditorReconciliation,
      editorReconciliationState == .loading,
      inspectedUnknownMutationContext == unknownMutationContext,
      Self.entryID(for: inspectedUnknownMutationContext) != nil
    {
      editorReconciliationState = .failed
    }
    selectionGeneration &+= 1
    let selection = selectionGeneration
    detailReadGeneration &+= 1
    let read = detailReadGeneration
    let service = service
    detailTask?.cancel()
    let keepsVisibleContent =
      preservingVisibleContent
      && selectedEntryID == entryID
      && selectedDetail?.entry.id == entryID
    if updatesEditorReconciliation {
      reconciliationContentUnavailable = false
    }
    selectedEntryID = entryID
    if !keepsVisibleContent {
      selectedDetail = nil
      detailState = .loading
    }

    detailTask = Task { @MainActor [weak self] in
      do {
        let detail = try await service.loadDiaryEntry(id: entryID)
        try Task.checkCancellation()
        guard let self,
          self.selectionGeneration == selection,
          self.detailReadGeneration == read,
          self.selectedEntryID == entryID
        else { return }
        self.selectedDetail = detail
        self.detailState = .loaded
        if updatesEditorReconciliation {
          self.editorReconciliationState = .loaded
          self.reconciliationContentUnavailable = false
        }
        self.detailTask = nil
      } catch is CancellationError {
        guard let self,
          self.selectionGeneration == selection,
          self.detailReadGeneration == read
        else { return }
        self.detailTask = nil
        if updatesEditorReconciliation {
          self.editorReconciliationState = .failed
        }
        if keepsVisibleContent {
          self.detailState = .loaded
          self.mutationNotice = "최신 내용 확인이 중단됐어요. 작성 중인 내용은 그대로 두었어요."
        } else {
          self.detailState = .failed
        }
      } catch {
        guard let self,
          self.selectionGeneration == selection,
          self.detailReadGeneration == read
        else { return }
        self.detailTask = nil
        if self.handleAuthenticationFailure(error) { return }
        if updatesEditorReconciliation,
          error as? WoorisaiAPIError == .notFound
        {
          self.editorReconciliationState = .loaded
          self.reconciliationContentUnavailable = true
          self.conflict = nil
          self.mutationNotice = "서버에서 이 내용을 찾을 수 없어요. 작성 중인 초안은 그대로 두었어요."
          if keepsVisibleContent {
            self.detailState = .loaded
          } else {
            self.selectedDetail = nil
            self.detailState = .notFound
          }
          return
        }
        if updatesEditorReconciliation {
          self.editorReconciliationState = .failed
        }
        if let reconciliationConflict,
          reconciliationConflict == self.lastConflictEditorInvalidation
        {
          self.conflict = reconciliationConflict
          self.mutationNotice = "최신 내용을 불러오지 못했어요. 초안은 그대로 두고 다시 시도해 주세요."
          if keepsVisibleContent {
            self.detailState = .loaded
            return
          }
        }
        if keepsVisibleContent {
          self.detailState = .loaded
          self.mutationNotice = "최신 내용을 불러오지 못했어요. 작성 중인 내용은 그대로 두었어요."
          return
        }
        switch error as? WoorisaiAPIError {
        case .notFound: self.detailState = .notFound
        case .serviceUnavailable: self.detailState = .unavailable
        default: self.detailState = .failed
        }
      }
    }
  }

  func cancelDetailReadForScreenExit(entryID: Int64) {
    guard selectedEntryID == entryID else { return }
    guard !mutationOutcomeRequiresConfirmation else { return }
    selectionGeneration &+= 1
    detailReadGeneration &+= 1
    detailTask?.cancel()
    detailTask = nil
    selectedEntryID = nil
    selectedDetail = nil
    detailState = .idle
    editorReconciliationState = .idle
    lastConflictEditorInvalidation = nil
  }

  func refreshDetail(entryID: Int64) async {
    loadDetail(entryID: entryID, preservingVisibleContent: true)
    let task = detailTask
    await task?.value
  }

  @discardableResult
  func createEntry(content: String, mediaUploadIDs: [UUID] = []) -> Bool {
    guard canBeginMutation else { return false }
    let draft: DiaryEntryCreateDraft
    do {
      draft = try DiaryEntryCreateDraft(content: content, mediaUploadIDs: mediaUploadIDs)
    } catch {
      mutationState = .failed
      mutationNotice = "일기 내용을 확인해 주세요."
      return false
    }

    beginMutation()
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        // Diary create has no idempotency key. It is deliberately issued exactly once.
        let entry = try await service.createDiaryEntry(draft)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateListReads()
        let wasKnown = self.entries.contains(where: { $0.id == entry.id })
        self.entries.removeAll { $0.id == entry.id }
        self.entries.insert(entry, at: 0)
        if !wasKnown { self.totalCount += 1 }
        self.currentPage = max(self.currentPage, 1)
        self.listState = .loaded
        self.lastCreatedEntryID = entry.id
        self.finishMutation(message: "새 일기를 남겼어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: nil,
          mediaMutation: .createEntry,
          unknownContext: .createEntry
        )
      }
    }
    return true
  }

  @discardableResult
  func updateEntry(
    entryID: Int64,
    content: String? = nil,
    attachments: DiaryAttachmentUpdate = .preserve
  ) -> Bool {
    guard canBeginMutation else { return false }
    let draft: DiaryEntryUpdateDraft
    do {
      draft = try DiaryEntryUpdateDraft(content: content, attachments: attachments)
    } catch {
      mutationState = .failed
      mutationNotice = "수정할 일기 내용을 확인해 주세요."
      return false
    }

    let originalEntry = selectedDetail?.entry.id == entryID ? selectedDetail?.entry : nil
    beginMutation(
      submittedSnapshot: .updateEntry(
        entryID: entryID,
        content: draft.content,
        attachmentIDs: Self.replacedAttachmentIDs(in: draft.attachments),
        originalContent: originalEntry?.content,
        originalAttachmentIDs: originalEntry?.attachments.map(\.id),
        originalRevision: Self.revision(of: originalEntry)
      )
    )
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        let entry = try await service.updateDiaryEntry(id: entryID, draft: draft)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateReads(afterMutationFor: entryID)
        self.replaceEntry(entry)
        self.lastUpdatedEntryID = entry.id
        self.finishMutation(message: "일기를 수정했어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .entry(entryID: entryID),
          mediaMutation: .updateEntry(entryID: entryID),
          unknownContext: .updateEntry(entryID: entryID)
        )
      }
    }
    return true
  }

  func deleteEntry(entryID: Int64) {
    guard canBeginMutation else { return }
    beginMutation()
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        try await service.deleteDiaryEntry(id: entryID)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateReads(afterMutationFor: entryID)
        let wasKnown = self.entries.contains(where: { $0.id == entryID })
        self.entries.removeAll { $0.id == entryID }
        if wasKnown { self.totalCount = max(0, self.totalCount - 1) }
        if self.selectedEntryID == entryID {
          self.selectedEntryID = nil
          self.selectedDetail = nil
          self.detailState = .idle
        }
        self.commentDrafts.removeValue(forKey: entryID)
        self.finishMutation(message: "일기를 삭제했어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .entry(entryID: entryID),
          unknownContext: .deleteEntry(entryID: entryID)
        )
      }
    }
  }

  func createComment(entryID: Int64, content: String) {
    guard canBeginMutation else { return }
    let draft: DiaryCommentDraft
    do {
      draft = try DiaryCommentDraft(content: content)
    } catch {
      mutationState = .failed
      mutationNotice = "댓글 내용을 입력해 주세요."
      return
    }

    beginMutation()
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        // Comment create is also non-idempotent and is never automatically retried.
        let comment = try await service.createDiaryComment(entryID: entryID, draft: draft)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateReads(afterMutationFor: entryID)
        self.applyCreatedComment(comment, entryID: entryID)
        self.finishMutation(message: "댓글을 남겼어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .comment(entryID: entryID),
          unknownContext: .createComment(entryID: entryID)
        )
      }
    }
  }

  func updateComment(entryID: Int64, commentID: Int64, content: String) {
    guard canBeginMutation else { return }
    let draft: DiaryCommentDraft
    do {
      draft = try DiaryCommentDraft(content: content)
    } catch {
      mutationState = .failed
      mutationNotice = "댓글 내용을 확인해 주세요."
      return
    }

    let originalComment = selectedDetail?.comments.first { $0.id == commentID }
    beginMutation(
      submittedSnapshot: .updateComment(
        entryID: entryID,
        commentID: commentID,
        content: draft.content,
        originalContent: originalComment?.content,
        originalRevision: Self.revision(of: originalComment)
      )
    )
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        let comment = try await service.updateDiaryComment(id: commentID, draft: draft)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateDetailRead(ifSelected: entryID)
        if let detail = self.selectedDetail, detail.entry.id == entryID {
          let comments = detail.comments.map { $0.id == commentID ? comment : $0 }
          self.selectedDetail = DiaryEntryDetail(entry: detail.entry, comments: comments)
        }
        self.finishMutation(message: "댓글을 수정했어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .comment(entryID: entryID),
          unknownContext: .updateComment(entryID: entryID, commentID: commentID)
        )
      }
    }
  }

  func deleteComment(entryID: Int64, commentID: Int64) {
    guard canBeginMutation else { return }
    beginMutation()
    let generation = mutationGeneration
    let service = service
    mutationTask = Task { @MainActor [weak self] in
      do {
        try await service.deleteDiaryComment(id: commentID)
        try Task.checkCancellation()
        guard let self, self.mutationGeneration == generation else { return }
        self.invalidateReads(afterMutationFor: entryID)
        self.applyDeletedComment(commentID: commentID, entryID: entryID)
        self.finishMutation(message: "댓글을 삭제했어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .comment(entryID: entryID),
          unknownContext: .deleteComment(entryID: entryID, commentID: commentID)
        )
      }
    }
  }

  func reloadAfterConflict(preservingVisibleContent: Bool = true) {
    guard let conflict else { return }
    self.conflict = nil
    lastConflictEditorInvalidation = conflict
    editorReconciliationState = .loading
    switch conflict {
    case .entry(let entryID), .comment(let entryID):
      loadDetail(
        entryID: entryID,
        preservingVisibleContent: preservingVisibleContent,
        reconciliationConflict: conflict,
        updatesEditorReconciliation: true
      )
    }
  }

  func dismissConflict() {
    guard let conflict else { return }
    self.conflict = nil
    lastConflictEditorInvalidation = conflict
    editorReconciliationState = .loading
    switch conflict {
    case .entry(let entryID), .comment(let entryID):
      // Keep the editor and its local draft mounted while the latest server value is fetched.
      loadDetail(
        entryID: entryID,
        preservingVisibleContent: true,
        reconciliationConflict: conflict,
        updatesEditorReconciliation: true
      )
    }
  }

  func dismissNotices() {
    listNotice = nil
    mutationNotice = nil
  }

  func commentDraft(entryID: Int64) -> String {
    commentDrafts[entryID] ?? ""
  }

  func updateCommentDraft(entryID: Int64, content: String) {
    if content.isEmpty {
      commentDrafts.removeValue(forKey: entryID)
      releaseManualRetryDraftProtection(context: .createComment(entryID: entryID))
    } else {
      commentDrafts[entryID] = content
    }
  }

  func discardCommentDraft(entryID: Int64) {
    commentDrafts.removeValue(forKey: entryID)
    releaseManualRetryDraftProtection(context: .createComment(entryID: entryID))
  }

  func releaseManualRetryDraftProtection(context: UnknownMutationContext) {
    if manualRetryDraftContext == context {
      manualRetryDraftContext = nil
    }
    if submittedMutationSnapshot?.context == context {
      submittedMutationSnapshot = nil
    }
  }

  func updateLocalDraftProtection(
    context: UnknownMutationContext,
    isProtected: Bool
  ) {
    if isProtected {
      protectedLocalDraftContexts.insert(context)
    } else {
      protectedLocalDraftContexts.remove(context)
    }
  }

  @discardableResult
  func confirmManualRetryAfterUnknownOutcome(context: UnknownMutationContext) -> Bool {
    guard mutationOutcomeRequiresConfirmation,
      unknownMutationContext == context,
      inspectedUnknownMutationContext == context,
      editorReconciliationState == .loaded,
      !reconciliationContentUnavailable
    else {
      mutationNotice = "먼저 최신 내용을 불러와 저장 여부를 확인해 주세요."
      return false
    }
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    manualRetryDraftContext = Self.retainsDraft(for: context) ? context : nil
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
    mutationState = .idle
    mutationNotice = "중복 여부를 확인한 뒤 수동 재시도를 선택했어요."
    return true
  }

  @discardableResult
  func resolveUnknownOutcomeAsCommitted(context: UnknownMutationContext) -> Bool {
    guard mutationOutcomeRequiresConfirmation,
      unknownMutationContext == context,
      inspectedUnknownMutationContext == context,
      editorReconciliationState == .loaded
    else {
      mutationNotice = "먼저 최신 내용을 불러와 저장 여부를 확인해 주세요."
      return false
    }
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = nil
    manualRetryDraftContext = nil
    protectedLocalDraftContexts.remove(context)
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
    mutationState = .idle
    mutationNotice = "이미 저장된 내용을 확인하고 초안을 정리했어요."
    return true
  }

  @discardableResult
  func abandonInconclusiveUnknownOutcome(context: UnknownMutationContext) -> Bool {
    // Abandon never resends, so it must NOT require a successful reconciliation: the unknown
    // outcome is usually a connectivity failure, so the reload fails too — requiring `.loaded`
    // here left the editor sheets with every recovery action disabled and dismissal locked.
    guard mutationOutcomeRequiresConfirmation,
      unknownMutationContext == context
    else {
      mutationNotice = "먼저 최신 내용을 불러와 저장 여부를 확인해 주세요."
      return false
    }
    let verifiedByReconciliation =
      inspectedUnknownMutationContext == context && editorReconciliationState == .loaded
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = nil
    manualRetryDraftContext = nil
    protectedLocalDraftContexts.remove(context)
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
    mutationState = .idle
    mutationNotice =
      verifiedByReconciliation
      ? "중복을 피하기 위해 재전송하지 않고 초안을 정리했어요."
      : "저장 여부를 확인하지 못한 채 재전송 없이 초안을 정리했어요. 나중에 최신 내용에서 저장 여부를 확인해 주세요."
    return true
  }

  func reconcileUnknownOutcome(entryID: Int64) {
    guard mutationOutcomeRequiresConfirmation,
      let context = unknownMutationContext,
      Self.entryID(for: context) == entryID
    else {
      mutationNotice = "이 작업의 저장 결과는 해당 일기에서 확인해 주세요."
      return
    }
    inspectedUnknownMutationContext = context
    editorReconciliationState = .loading
    loadDetail(
      entryID: entryID,
      preservingVisibleContent: true,
      updatesEditorReconciliation: true
    )
  }

  func reconcileUnknownOutcomeList() {
    guard mutationOutcomeRequiresConfirmation,
      unknownMutationContext == .createEntry
    else {
      mutationNotice = "새 일기 저장 결과만 최신 목록에서 확인할 수 있어요."
      return
    }
    inspectedUnknownMutationContext = .createEntry
    editorReconciliationState = .loading
    reconciliationContentUnavailable = false
    reload(preservingVisibleContent: true, updatesEditorReconciliation: true)
  }

  func clear() {
    listGeneration &+= 1
    detailReadGeneration &+= 1
    selectionGeneration &+= 1
    mutationGeneration &+= 1
    listTask?.cancel()
    pageTask?.cancel()
    detailTask?.cancel()
    mutationTask?.cancel()
    listTask = nil
    pageTask = nil
    detailTask = nil
    mutationTask = nil
    listState = .idle
    detailState = .idle
    mutationState = .idle
    entries = []
    currentPage = 0
    hasNextPage = false
    totalCount = 0
    selectedEntryID = nil
    selectedDetail = nil
    conflict = nil
    rejectedMediaMutation = nil
    lastConflictEditorInvalidation = nil
    authenticationRequired = false
    listNotice = nil
    mutationNotice = nil
    lastCreatedEntryID = nil
    lastUpdatedEntryID = nil
    commentDrafts.removeAll()
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = nil
    manualRetryDraftContext = nil
    protectedLocalDraftContexts.removeAll()
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
  }

  private func beginMutation(
    submittedSnapshot: SubmittedMutationSnapshot? = nil
  ) {
    mutationGeneration &+= 1
    mutationState = .submitting
    mutationNotice = nil
    rejectedMediaMutation = nil
    lastConflictEditorInvalidation = nil
    lastCreatedEntryID = nil
    lastUpdatedEntryID = nil
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = submittedSnapshot
    manualRetryDraftContext = nil
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
  }

  private func finishMutation(message: String) {
    mutationTask = nil
    mutationState = .idle
    mutationNotice = message
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = nil
    manualRetryDraftContext = nil
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
  }

  private func finishMutationFailure(
    _ error: any Error,
    generation: UInt,
    conflict conflictValue: Conflict?,
    mediaMutation: RejectedMediaMutation? = nil,
    unknownContext: UnknownMutationContext
  ) {
    guard mutationGeneration == generation else { return }
    mutationTask = nil
    let isDefinitiveNonCommit = Self.isDefinitiveNonCommit(error)
    if isDefinitiveNonCommit {
      rejectedMediaMutation = mediaMutation
    }
    if handleAuthenticationFailure(error) { return }
    if error as? WoorisaiAPIError == .conflict, let conflictValue {
      mutationState = .idle
      conflict = conflictValue
      unknownMutationContext = nil
      inspectedUnknownMutationContext = nil
      manualRetryDraftContext = nil
      return
    }
    mutationState = .failed
    mutationOutcomeRequiresConfirmation = !isDefinitiveNonCommit
    unknownMutationContext = isDefinitiveNonCommit ? nil : unknownContext
    inspectedUnknownMutationContext = nil
    if isDefinitiveNonCommit {
      submittedMutationSnapshot = nil
    }
    manualRetryDraftContext = nil
    mutationNotice =
      isDefinitiveNonCommit
      ? "저장하지 못했어요. 내용을 확인하고 다시 시도해 주세요."
      : "저장 결과를 확인할 수 없어요. 중복 방지를 위해 재전송을 잠갔습니다."
  }

  private func invalidateListReads() {
    // A loaded list is reconciled locally by each successful mutation, so only cancel its stale
    // pagination. A detail mutation can also finish while a push-triggered reload is running; in
    // that case start a replacement read so cancellation can never strand the list in `.loading`.
    guard listState == .loaded else {
      reload()
      return
    }
    listGeneration &+= 1
    listTask?.cancel()
    pageTask?.cancel()
    listTask = nil
    pageTask = nil
  }

  private func invalidateDetailRead(ifSelected entryID: Int64) {
    guard selectedEntryID == entryID else { return }
    detailReadGeneration &+= 1
    detailTask?.cancel()
    detailTask = nil
  }

  private func invalidateReads(afterMutationFor entryID: Int64) {
    invalidateListReads()
    invalidateDetailRead(ifSelected: entryID)
  }

  private func replaceEntry(_ entry: DiaryEntry) {
    if let index = entries.firstIndex(where: { $0.id == entry.id }) {
      entries[index] = entry
    }
    if let detail = selectedDetail, detail.entry.id == entry.id {
      selectedDetail = DiaryEntryDetail(entry: entry, comments: detail.comments)
    }
  }

  private func applyCreatedComment(_ comment: DiaryComment, entryID: Int64) {
    commentDrafts.removeValue(forKey: entryID)
    if let index = entries.firstIndex(where: { $0.id == entryID }) {
      entries[index] = Self.withCommentCount(
        entries[index],
        entries[index].commentCount + 1
      )
    }
    guard let detail = selectedDetail, detail.entry.id == entryID else { return }
    var comments = detail.comments.filter { $0.id != comment.id }
    comments.append(comment)
    comments.sort {
      $0.createdAt < $1.createdAt || ($0.createdAt == $1.createdAt && $0.id < $1.id)
    }
    let entry = Self.withCommentCount(
      detail.entry,
      max(detail.entry.commentCount + 1, Int64(comments.count))
    )
    selectedDetail = DiaryEntryDetail(entry: entry, comments: comments)
  }

  private func applyDeletedComment(commentID: Int64, entryID: Int64) {
    if let index = entries.firstIndex(where: { $0.id == entryID }) {
      entries[index] = Self.withCommentCount(
        entries[index],
        max(0, entries[index].commentCount - 1)
      )
    }
    guard let detail = selectedDetail, detail.entry.id == entryID else { return }
    let comments = detail.comments.filter { $0.id != commentID }
    let entry = Self.withCommentCount(
      detail.entry,
      max(Int64(comments.count), detail.entry.commentCount - 1)
    )
    selectedDetail = DiaryEntryDetail(entry: entry, comments: comments)
  }

  private static func withCommentCount(_ entry: DiaryEntry, _ commentCount: Int64) -> DiaryEntry {
    DiaryEntry(
      id: entry.id,
      author: entry.author,
      content: entry.content,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
      isMine: entry.isMine,
      attachments: entry.attachments,
      commentCount: commentCount
    )
  }

  private func handleAuthenticationFailure(_ error: any Error) -> Bool {
    guard let apiError = error as? WoorisaiAPIError,
      apiError == .credentialRejected || apiError == .credentialMissing
    else {
      return false
    }
    listGeneration &+= 1
    detailReadGeneration &+= 1
    selectionGeneration &+= 1
    mutationGeneration &+= 1
    listTask?.cancel()
    pageTask?.cancel()
    detailTask?.cancel()
    mutationTask?.cancel()
    listTask = nil
    pageTask = nil
    detailTask = nil
    mutationTask = nil
    listState = .idle
    detailState = .idle
    mutationState = .idle
    entries = []
    currentPage = 0
    hasNextPage = false
    totalCount = 0
    selectedEntryID = nil
    selectedDetail = nil
    conflict = nil
    listNotice = nil
    mutationNotice = nil
    lastCreatedEntryID = nil
    lastUpdatedEntryID = nil
    commentDrafts.removeAll()
    mutationOutcomeRequiresConfirmation = false
    unknownMutationContext = nil
    inspectedUnknownMutationContext = nil
    submittedMutationSnapshot = nil
    manualRetryDraftContext = nil
    protectedLocalDraftContexts.removeAll()
    editorReconciliationState = .idle
    reconciliationContentUnavailable = false
    authenticationRequired = true
    return true
  }

  private static func isDefinitiveNonCommit(_ error: any Error) -> Bool {
    switch error as? WoorisaiAPIError {
    case .credentialMissing, .credentialRejected, .invalidRequest, .forbidden, .notFound,
      .conflict, .unsupportedMediaType:
      return true
    default:
      return false
    }
  }

  private static func entryID(for context: UnknownMutationContext?) -> Int64? {
    switch context {
    case .updateEntry(let entryID), .deleteEntry(let entryID), .createComment(let entryID),
      .updateComment(let entryID, _), .deleteComment(let entryID, _):
      return entryID
    case .createEntry, nil:
      return nil
    }
  }

  private static func replacedAttachmentIDs(
    in update: DiaryAttachmentUpdate
  ) -> [UUID]? {
    guard case .replace(let attachmentIDs) = update else { return nil }
    return attachmentIDs
  }

  private static func revision(of entry: DiaryEntry?) -> MutationRevision? {
    entry.map { MutationRevision(createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
  }

  private static func revision(of comment: DiaryComment?) -> MutationRevision? {
    comment.map { MutationRevision(createdAt: $0.createdAt, updatedAt: $0.updatedAt) }
  }

  private static func retainsDraft(for context: UnknownMutationContext) -> Bool {
    switch context {
    case .createEntry, .updateEntry, .createComment, .updateComment:
      return true
    case .deleteEntry, .deleteComment:
      return false
    }
  }

  private var canBeginMutation: Bool {
    mutationState != .submitting && !mutationOutcomeRequiresConfirmation
  }
}
