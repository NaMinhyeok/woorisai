import Foundation
import Observation
import WoorisaiAPI

@MainActor
@Observable
final class RelationshipModel {
  private struct CommittedCommentOverlay {
    var comments: [RelationshipScoreComment] = []
    var minimumCommentCount: Int64 = 0
  }

  enum LoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case unavailable
    case failed
  }

  enum ThreadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case notFound
    case unavailable
    case failed
  }

  enum SubmissionState: Equatable, Sendable {
    case idle
    case submitting
    case failed
  }

  enum Conflict: Equatable, Sendable {
    case scoreChange
    case comment(scoreChangeID: Int64)
  }

  enum RejectedMediaMutation: Equatable, Sendable {
    case scoreChange
    case comment(scoreChangeID: Int64)
  }

  private(set) var loadState: LoadState = .idle
  private(set) var threadState: ThreadState = .idle
  private(set) var scoreSubmissionState: SubmissionState = .idle
  private(set) var commentSubmissionState: SubmissionState = .idle
  private(set) var scores: RelationshipScores?
  private(set) var changes: [RelationshipScoreChange] = []
  private(set) var currentPage = 0
  private(set) var hasNextPage = false
  private(set) var totalCount: Int64 = 0
  private(set) var selectedThread: RelationshipScoreThread?
  private(set) var selectedThreadScoreChangeID: Int64?
  private(set) var conflict: Conflict?
  private(set) var rejectedMediaMutation: RejectedMediaMutation?
  private(set) var authenticationRequired = false
  private(set) var notice: String?
  private(set) var lastSuccessfulScoreChangeID: Int64?
  private(set) var lastSuccessfulCommentScoreChangeID: Int64?
  private(set) var commentSubmissionScoreChangeID: Int64?
  private(set) var commentNoticeScoreChangeID: Int64?
  private(set) var commentNoticeMessage: String?

  @ObservationIgnored
  private let service: any RelationshipServing

  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  @ObservationIgnored
  private var pageTask: Task<Void, Never>?

  @ObservationIgnored
  private var scoreTask: Task<Void, Never>?

  @ObservationIgnored
  private var threadTask: Task<Void, Never>?

  @ObservationIgnored
  private var commentTask: Task<Void, Never>?

  @ObservationIgnored
  private var dataGeneration: UInt = 0

  @ObservationIgnored
  private var threadGeneration: UInt = 0

  @ObservationIgnored
  private var threadReadGeneration: UInt = 0

  @ObservationIgnored
  private var commentWriteGeneration: UInt = 0

  @ObservationIgnored
  private var committedCommentOverlays: [Int64: CommittedCommentOverlay] = [:]

  init(service: any RelationshipServing) {
    self.service = service
  }

  func loadIfNeeded() {
    guard loadState == .idle else { return }
    reload()
  }

  func reload() {
    dataGeneration &+= 1
    let generation = dataGeneration
    let service = service
    loadTask?.cancel()
    pageTask?.cancel()
    pageTask = nil
    loadState = .loading
    notice = nil

    loadTask = Task { @MainActor [weak self] in
      do {
        let scores = try await service.loadRelationshipScores()
        try Task.checkCancellation()
        let firstPage = try await service.loadScoreChanges(pageNumber: 1)
        try Task.checkCancellation()
        guard let self, self.dataGeneration == generation else { return }
        self.scores = scores
        self.changes = self.mergingCommittedCommentCounts(into: firstPage.changes)
        self.currentPage = firstPage.pageNumber
        self.hasNextPage = firstPage.hasNext
        self.totalCount = firstPage.totalCount
        self.loadState = .loaded
        self.loadTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.loadTask = nil
        if self.handleAuthenticationFailure(error) { return }
        if error as? WoorisaiAPIError == .serviceUnavailable {
          self.loadState = .unavailable
        } else {
          self.loadState = .failed
        }
      }
    }
  }

  func loadNextPage() {
    guard loadState == .loaded, hasNextPage, pageTask == nil else { return }
    let expectedPage = currentPage + 1
    let generation = dataGeneration
    let service = service

    pageTask = Task { @MainActor [weak self] in
      do {
        let page = try await service.loadScoreChanges(pageNumber: expectedPage)
        try Task.checkCancellation()
        guard let self, self.dataGeneration == generation else { return }
        let knownIDs = Set(self.changes.map(\.id))
        guard page.changes.allSatisfy({ !knownIDs.contains($0.id) }) else {
          throw WoorisaiAPIError.schemaDrift
        }
        self.changes.append(contentsOf: self.mergingCommittedCommentCounts(into: page.changes))
        self.currentPage = page.pageNumber
        self.hasNextPage = page.hasNext
        self.totalCount = page.totalCount
        self.pageTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.pageTask = nil
        if self.handleAuthenticationFailure(error) { return }
        self.notice = "다음 기록을 불러오지 못했어요. 다시 시도해 주세요."
      }
    }
  }

  func canCreateScoreChange(targetScore: Int) -> Bool {
    guard loadState == .loaded,
      scoreSubmissionState != .submitting,
      let outgoingScore = scores?.outgoingScore
    else {
      return false
    }
    return (0...100).contains(targetScore) && targetScore != outgoingScore
  }

  @discardableResult
  func createScoreChange(
    targetScore: Int,
    reason: String,
    mediaUploadIDs: [UUID] = []
  ) -> Bool {
    guard canCreateScoreChange(targetScore: targetScore) else {
      if scores?.outgoingScore == targetScore {
        scoreSubmissionState = .failed
        notice = "현재 점수와 다른 점수를 선택해 주세요."
      }
      return false
    }
    let draft: RelationshipScoreChangeDraft
    do {
      draft = try RelationshipScoreChangeDraft(
        mutation: .target(targetScore),
        reason: reason,
        mediaUploadIDs: mediaUploadIDs
      )
    } catch {
      scoreSubmissionState = .failed
      notice = "점수와 이유를 확인해 주세요."
      return false
    }

    let generation = dataGeneration
    let service = service
    scoreSubmissionState = .submitting
    rejectedMediaMutation = nil
    lastSuccessfulScoreChangeID = nil
    notice = nil
    scoreTask?.cancel()
    scoreTask = Task { @MainActor [weak self] in
      do {
        // Create operations have no idempotency key. This call is deliberately issued once and
        // is never automatically retried after a transport failure or conflict.
        let created = try await service.createScoreChange(draft)
        try Task.checkCancellation()
        guard let self, self.dataGeneration == generation else { return }
        if let scores = self.scores {
          self.scores = RelationshipScores(
            currentParticipant: scores.currentParticipant,
            partner: scores.partner,
            outgoingScore: created.outgoingScore,
            incomingScore: scores.incomingScore,
            outgoingUpdatedAt: created.outgoingUpdatedAt,
            incomingUpdatedAt: scores.incomingUpdatedAt
          )
        }
        self.changes.removeAll { $0.id == created.change.id }
        self.changes.insert(created.change, at: 0)
        self.totalCount += 1
        self.lastSuccessfulScoreChangeID = created.change.id
        self.scoreSubmissionState = .idle
        self.scoreTask = nil
        self.notice = "새 점수 기록을 남겼어요."
      } catch is CancellationError {
        return
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.scoreTask = nil
        if Self.isDefinitiveNonCommit(error) {
          self.rejectedMediaMutation = .scoreChange
        }
        if self.handleAuthenticationFailure(error) { return }
        if error as? WoorisaiAPIError == .conflict {
          self.scoreSubmissionState = .idle
          self.conflict = .scoreChange
        } else {
          self.scoreSubmissionState = .failed
          self.notice = "저장 결과를 확인할 수 없어요. 자동으로 다시 보내지 않았습니다."
        }
      }
    }
    return true
  }

  func loadThread(scoreChangeID: Int64) {
    threadGeneration &+= 1
    let generation = threadGeneration
    threadReadGeneration &+= 1
    let readGeneration = threadReadGeneration
    let service = service
    threadTask?.cancel()
    selectedThreadScoreChangeID = scoreChangeID
    selectedThread = nil
    threadState = .loading

    threadTask = Task { @MainActor [weak self] in
      do {
        let thread = try await service.loadScoreChange(id: scoreChangeID)
        try Task.checkCancellation()
        guard let self,
          self.threadGeneration == generation,
          self.threadReadGeneration == readGeneration
        else { return }
        self.selectedThread = self.mergingCommittedComments(into: thread)
        self.threadState = .loaded
        self.threadTask = nil
      } catch is CancellationError {
        return
      } catch {
        guard let self,
          self.threadGeneration == generation,
          self.threadReadGeneration == readGeneration
        else { return }
        self.threadTask = nil
        if self.handleAuthenticationFailure(error) { return }
        switch error as? WoorisaiAPIError {
        case .notFound: self.threadState = .notFound
        case .serviceUnavailable: self.threadState = .unavailable
        default: self.threadState = .failed
        }
      }
    }
  }

  func cancelThreadReadForScreenExit(scoreChangeID: Int64) {
    guard selectedThreadScoreChangeID == scoreChangeID else { return }
    threadReadGeneration &+= 1
    threadTask?.cancel()
    threadTask = nil
    selectedThreadScoreChangeID = nil
    selectedThread = nil
    threadState = .idle
  }

  func commentSubmissionState(for scoreChangeID: Int64) -> SubmissionState {
    commentSubmissionScoreChangeID == scoreChangeID ? commentSubmissionState : .idle
  }

  func commentNotice(for scoreChangeID: Int64) -> String? {
    guard commentNoticeScoreChangeID == scoreChangeID else { return nil }
    return commentNoticeMessage
  }

  @discardableResult
  func createComment(
    scoreChangeID: Int64,
    content: String,
    mediaUploadIDs: [UUID] = []
  ) -> Bool {
    guard commentSubmissionState != .submitting else { return false }
    let draft: RelationshipScoreCommentDraft
    do {
      draft = try RelationshipScoreCommentDraft(
        content: content,
        mediaUploadIDs: mediaUploadIDs
      )
    } catch {
      commentSubmissionScoreChangeID = scoreChangeID
      commentSubmissionState = .failed
      commentNoticeScoreChangeID = scoreChangeID
      commentNoticeMessage = "댓글 내용을 입력해 주세요."
      return false
    }

    commentWriteGeneration &+= 1
    let writeGeneration = commentWriteGeneration
    let successMinimumCommentCount = knownCommentCount(for: scoreChangeID) + 1
    let service = service
    commentSubmissionScoreChangeID = scoreChangeID
    commentSubmissionState = .submitting
    rejectedMediaMutation = nil
    lastSuccessfulCommentScoreChangeID = nil
    commentNoticeScoreChangeID = nil
    commentNoticeMessage = nil
    commentTask?.cancel()
    commentTask = Task { @MainActor [weak self] in
      do {
        // Like score writes, comment create is sent once; the UI never performs an automatic
        // duplicate retry when the response is lost.
        let comment = try await service.createScoreChangeComment(
          scoreChangeID: scoreChangeID,
          draft: draft
        )
        try Task.checkCancellation()
        guard let self, self.commentWriteGeneration == writeGeneration else { return }
        self.commentTask = nil

        var overlay = self.committedCommentOverlays[scoreChangeID, default: .init()]
        if !overlay.comments.contains(where: { $0.id == comment.id }) {
          overlay.comments.append(comment)
          overlay.minimumCommentCount = max(
            overlay.minimumCommentCount,
            successMinimumCommentCount
          )
          self.committedCommentOverlays[scoreChangeID] = overlay
        }
        self.changes = self.mergingCommittedCommentCounts(into: self.changes)
        if let thread = self.selectedThread, thread.change.id == scoreChangeID {
          self.selectedThread = self.mergingCommittedComments(into: thread)
        }
        self.lastSuccessfulCommentScoreChangeID = scoreChangeID
        self.commentSubmissionState = .idle
        self.commentNoticeScoreChangeID = scoreChangeID
        self.commentNoticeMessage = "댓글을 남겼어요."
      } catch is CancellationError {
        guard let self, self.commentWriteGeneration == writeGeneration else { return }
        self.commentTask = nil
        self.commentSubmissionState = .failed
        self.commentNoticeScoreChangeID = scoreChangeID
        self.commentNoticeMessage = "댓글 저장 결과를 확인할 수 없어 자동 재시도하지 않았습니다."
      } catch {
        guard let self, self.commentWriteGeneration == writeGeneration else { return }
        self.commentTask = nil
        if Self.isDefinitiveNonCommit(error) {
          self.rejectedMediaMutation = .comment(scoreChangeID: scoreChangeID)
        }
        if self.handleAuthenticationFailure(error) { return }
        if error as? WoorisaiAPIError == .conflict {
          self.commentSubmissionState = .idle
          self.conflict = .comment(scoreChangeID: scoreChangeID)
        } else {
          self.commentSubmissionState = .failed
          self.commentNoticeScoreChangeID = scoreChangeID
          self.commentNoticeMessage = "댓글 저장 결과를 확인할 수 없어 자동 재시도하지 않았습니다."
        }
      }
    }
    return true
  }

  func reloadAfterConflict() {
    guard let conflict else { return }
    self.conflict = nil
    switch conflict {
    case .scoreChange:
      reload()
    case .comment(let scoreChangeID):
      loadThread(scoreChangeID: scoreChangeID)
    }
  }

  func dismissConflict() {
    guard let conflict else { return }
    self.conflict = nil
    switch conflict {
    case .scoreChange:
      reload()
    case .comment(let scoreChangeID):
      loadThread(scoreChangeID: scoreChangeID)
    }
  }

  func dismissNotice() {
    notice = nil
  }

  func clear() {
    dataGeneration &+= 1
    threadGeneration &+= 1
    threadReadGeneration &+= 1
    commentWriteGeneration &+= 1
    loadTask?.cancel()
    pageTask?.cancel()
    scoreTask?.cancel()
    threadTask?.cancel()
    commentTask?.cancel()
    loadTask = nil
    pageTask = nil
    scoreTask = nil
    threadTask = nil
    commentTask = nil
    loadState = .idle
    threadState = .idle
    scoreSubmissionState = .idle
    commentSubmissionState = .idle
    scores = nil
    changes = []
    currentPage = 0
    hasNextPage = false
    totalCount = 0
    selectedThreadScoreChangeID = nil
    selectedThread = nil
    conflict = nil
    rejectedMediaMutation = nil
    authenticationRequired = false
    notice = nil
    lastSuccessfulScoreChangeID = nil
    lastSuccessfulCommentScoreChangeID = nil
    commentSubmissionScoreChangeID = nil
    commentNoticeScoreChangeID = nil
    commentNoticeMessage = nil
    committedCommentOverlays.removeAll()
  }

  private func handleAuthenticationFailure(_ error: any Error) -> Bool {
    guard let apiError = error as? WoorisaiAPIError,
      apiError == .credentialRejected || apiError == .credentialMissing
    else {
      return false
    }

    dataGeneration &+= 1
    threadGeneration &+= 1
    threadReadGeneration &+= 1
    commentWriteGeneration &+= 1
    loadTask?.cancel()
    pageTask?.cancel()
    scoreTask?.cancel()
    threadTask?.cancel()
    commentTask?.cancel()
    loadTask = nil
    pageTask = nil
    scoreTask = nil
    threadTask = nil
    commentTask = nil
    scores = nil
    changes = []
    selectedThreadScoreChangeID = nil
    selectedThread = nil
    loadState = .idle
    threadState = .idle
    scoreSubmissionState = .idle
    commentSubmissionState = .idle
    lastSuccessfulCommentScoreChangeID = nil
    commentSubmissionScoreChangeID = nil
    commentNoticeScoreChangeID = nil
    commentNoticeMessage = nil
    committedCommentOverlays.removeAll()
    authenticationRequired = true
    return true
  }

  private func mergingCommittedComments(
    into thread: RelationshipScoreThread
  ) -> RelationshipScoreThread {
    guard let overlay = committedCommentOverlays[thread.change.id],
      !overlay.comments.isEmpty
    else {
      return thread
    }

    let existingIDs = Set(thread.comments.map(\.id))
    let missingComments = overlay.comments.filter { !existingIDs.contains($0.id) }

    let comments = (thread.comments + missingComments).sorted {
      if $0.createdAt == $1.createdAt { return $0.id < $1.id }
      return $0.createdAt < $1.createdAt
    }
    let mergedCommentCount = max(
      thread.change.commentCount,
      max(overlay.minimumCommentCount, Int64(comments.count))
    )
    guard !missingComments.isEmpty || mergedCommentCount != thread.change.commentCount else {
      return thread
    }
    return RelationshipScoreThread(
      change: Self.withCommentCount(
        thread.change,
        mergedCommentCount
      ),
      comments: comments
    )
  }

  private func mergingCommittedCommentCounts(
    into changes: [RelationshipScoreChange]
  ) -> [RelationshipScoreChange] {
    changes.map { change in
      guard let minimumCount = committedCommentOverlays[change.id]?.minimumCommentCount,
        minimumCount > change.commentCount
      else {
        return change
      }
      return Self.withCommentCount(change, minimumCount)
    }
  }

  private func knownCommentCount(for scoreChangeID: Int64) -> Int64 {
    var knownCount = committedCommentOverlays[scoreChangeID]?.minimumCommentCount ?? 0
    if let change = changes.first(where: { $0.id == scoreChangeID }) {
      knownCount = max(knownCount, change.commentCount)
    }
    if let thread = selectedThread, thread.change.id == scoreChangeID {
      knownCount = max(
        knownCount,
        max(thread.change.commentCount, Int64(thread.comments.count))
      )
    }
    return knownCount
  }

  private static func withCommentCount(
    _ change: RelationshipScoreChange,
    _ commentCount: Int64
  ) -> RelationshipScoreChange {
    RelationshipScoreChange(
      id: change.id,
      sourceParticipant: change.sourceParticipant,
      targetParticipant: change.targetParticipant,
      changedBy: change.changedBy,
      delta: change.delta,
      resultingScore: change.resultingScore,
      reason: change.reason,
      createdAt: change.createdAt,
      commentCount: commentCount,
      attachments: change.attachments
    )
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
