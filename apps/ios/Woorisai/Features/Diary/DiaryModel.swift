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

  enum Conflict: Equatable, Sendable {
    case entry(entryID: Int64)
    case comment(entryID: Int64)
  }

  enum RejectedMediaMutation: Equatable, Sendable {
    case createEntry
    case updateEntry(entryID: Int64)
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

  func reload() {
    listGeneration &+= 1
    let generation = listGeneration
    let service = service
    listTask?.cancel()
    pageTask?.cancel()
    pageTask = nil
    listState = .loading
    listNotice = nil

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
        self.listTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.listGeneration == generation else { return }
        self.listTask = nil
        if self.handleAuthenticationFailure(error) { return }
        self.listState =
          error as? WoorisaiAPIError == .serviceUnavailable
          ? .unavailable : .failed
      }
    }
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

  func loadDetail(entryID: Int64) {
    selectionGeneration &+= 1
    let selection = selectionGeneration
    detailReadGeneration &+= 1
    let read = detailReadGeneration
    let service = service
    detailTask?.cancel()
    selectedEntryID = entryID
    selectedDetail = nil
    detailState = .loading

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
        self.detailTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self,
          self.selectionGeneration == selection,
          self.detailReadGeneration == read
        else { return }
        self.detailTask = nil
        if self.handleAuthenticationFailure(error) { return }
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
    selectionGeneration &+= 1
    detailReadGeneration &+= 1
    detailTask?.cancel()
    detailTask = nil
    selectedEntryID = nil
    selectedDetail = nil
    detailState = .idle
  }

  @discardableResult
  func createEntry(content: String, mediaUploadIDs: [UUID] = []) -> Bool {
    guard mutationState != .submitting else { return false }
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
          mediaMutation: .createEntry
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
    guard mutationState != .submitting else { return false }
    let draft: DiaryEntryUpdateDraft
    do {
      draft = try DiaryEntryUpdateDraft(content: content, attachments: attachments)
    } catch {
      mutationState = .failed
      mutationNotice = "수정할 일기 내용을 확인해 주세요."
      return false
    }

    beginMutation()
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
          mediaMutation: .updateEntry(entryID: entryID)
        )
      }
    }
    return true
  }

  func deleteEntry(entryID: Int64) {
    guard mutationState != .submitting else { return }
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
        self.finishMutation(message: "일기를 삭제했어요.")
      } catch {
        self?.finishMutationFailure(
          error,
          generation: generation,
          conflict: .entry(entryID: entryID)
        )
      }
    }
  }

  func createComment(entryID: Int64, content: String) {
    guard mutationState != .submitting else { return }
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
          conflict: .comment(entryID: entryID)
        )
      }
    }
  }

  func updateComment(entryID: Int64, commentID: Int64, content: String) {
    guard mutationState != .submitting else { return }
    let draft: DiaryCommentDraft
    do {
      draft = try DiaryCommentDraft(content: content)
    } catch {
      mutationState = .failed
      mutationNotice = "댓글 내용을 확인해 주세요."
      return
    }

    beginMutation()
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
          conflict: .comment(entryID: entryID)
        )
      }
    }
  }

  func deleteComment(entryID: Int64, commentID: Int64) {
    guard mutationState != .submitting else { return }
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
          conflict: .comment(entryID: entryID)
        )
      }
    }
  }

  func reloadAfterConflict() {
    guard let conflict else { return }
    self.conflict = nil
    lastConflictEditorInvalidation = conflict
    switch conflict {
    case .entry(let entryID), .comment(let entryID):
      loadDetail(entryID: entryID)
    }
  }

  func dismissConflict() {
    guard let conflict else { return }
    self.conflict = nil
    lastConflictEditorInvalidation = conflict
    switch conflict {
    case .entry(let entryID), .comment(let entryID):
      // Closing the alert must not leave the known-stale detail actionable. Clear it
      // synchronously and reload before edit/delete controls can return.
      loadDetail(entryID: entryID)
    }
  }

  func dismissNotices() {
    listNotice = nil
    mutationNotice = nil
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
  }

  private func beginMutation() {
    mutationGeneration &+= 1
    mutationState = .submitting
    mutationNotice = nil
    rejectedMediaMutation = nil
    lastConflictEditorInvalidation = nil
    lastCreatedEntryID = nil
    lastUpdatedEntryID = nil
  }

  private func finishMutation(message: String) {
    mutationTask = nil
    mutationState = .idle
    mutationNotice = message
  }

  private func finishMutationFailure(
    _ error: any Error,
    generation: UInt,
    conflict conflictValue: Conflict?,
    mediaMutation: RejectedMediaMutation? = nil
  ) {
    guard mutationGeneration == generation else { return }
    mutationTask = nil
    if Self.isDefinitiveNonCommit(error) {
      rejectedMediaMutation = mediaMutation
    }
    if handleAuthenticationFailure(error) { return }
    if error as? WoorisaiAPIError == .conflict, let conflictValue {
      mutationState = .idle
      conflict = conflictValue
      return
    }
    mutationState = .failed
    mutationNotice = "저장 결과를 확인할 수 없어요. 자동으로 다시 보내지 않았습니다."
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
}
