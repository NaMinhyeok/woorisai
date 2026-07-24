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

  private struct ScoreSubmissionSnapshot: Equatable, Sendable {
    let originalScore: Int
    let originalUpdatedAt: Date
    let originalChangeIDs: Set<Int64>
    let targetScore: Int
    let reason: String?
    let attachmentIDs: [UUID]
    let currentParticipantSlot: ParticipantSlot
  }

  private struct CommentSubmissionSnapshot: Equatable, Sendable {
    let scoreChangeID: Int64
    let originalCommentIDs: Set<Int64>?
    let content: String?
    let attachmentIDs: [UUID]
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

  enum PagingState: Equatable, Sendable {
    case idle
    case loading
    case failed
  }

  enum OutcomeInspectionState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed
  }

  enum OutcomeInspectionResult: Equatable, Sendable {
    case inconclusive
    case committed
    case notCommitted
  }

  enum ManualRetryDraftContext: Equatable, Sendable {
    case scoreChange
    case comment(scoreChangeID: Int64)
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
  private(set) var pagingState: PagingState = .idle
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
  private(set) var archiveNotice: String?
  private(set) var lastSuccessfulScoreChangeID: Int64?
  private(set) var lastSuccessfulCommentScoreChangeID: Int64?
  private(set) var commentSubmissionScoreChangeID: Int64?
  private(set) var commentNoticeScoreChangeID: Int64?
  private(set) var commentNoticeMessage: String?
  private(set) var scoreOutcomeRequiresConfirmation = false
  private(set) var scoreOutcomeInspectionState: OutcomeInspectionState = .idle
  private(set) var scoreOutcomeInspectionResult: OutcomeInspectionResult = .inconclusive
  private(set) var unknownOutcomeTargetScore: Int?
  private(set) var commentOutcomeRequiresConfirmation = false
  private(set) var commentOutcomeInspectionState: OutcomeInspectionState = .idle
  private(set) var commentOutcomeInspectionResult: OutcomeInspectionResult = .inconclusive
  private(set) var commentOutcomeScoreChangeID: Int64?
  private(set) var manualRetryDraftContext: ManualRetryDraftContext?
  private(set) var localCommentDraftScoreChangeID: Int64?
  private(set) var localScoreDraftProtected = false

  var hasProtectedManualRetryDraft: Bool {
    manualRetryDraftContext != nil
  }

  var hasProtectedLocalCommentDraft: Bool {
    localCommentDraftScoreChangeID != nil
  }

  var hasProtectedLocalScoreDraft: Bool {
    localScoreDraftProtected
  }

  var canResolveUnknownScoreOutcomeAsCommitted: Bool {
    scoreOutcomeRequiresConfirmation
      && scoreOutcomeInspectionState == .loaded
      && scoreOutcomeInspectionResult == .committed
  }

  var canRetryUnknownScoreOutcome: Bool {
    scoreOutcomeRequiresConfirmation
      && scoreOutcomeInspectionState == .loaded
      && scoreOutcomeInspectionResult == .notCommitted
  }

  func commentOutcomeRequiresConfirmation(for scoreChangeID: Int64) -> Bool {
    commentOutcomeRequiresConfirmation && commentOutcomeScoreChangeID == scoreChangeID
  }

  func canResolveUnknownCommentOutcomeAsCommitted(for scoreChangeID: Int64) -> Bool {
    commentOutcomeRequiresConfirmation(for: scoreChangeID)
      && commentOutcomeInspectionState == .loaded
      && commentOutcomeInspectionResult == .committed
  }

  func canRetryUnknownCommentOutcome(for scoreChangeID: Int64) -> Bool {
    commentOutcomeRequiresConfirmation(for: scoreChangeID)
      && commentOutcomeInspectionState == .loaded
      && commentOutcomeInspectionResult == .notCommitted
  }

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

  @ObservationIgnored
  private var scoreSubmissionSnapshot: ScoreSubmissionSnapshot?

  @ObservationIgnored
  private var commentSubmissionSnapshot: CommentSubmissionSnapshot?

  init(service: any RelationshipServing) {
    self.service = service
  }

  func loadIfNeeded() {
    guard loadState == .idle else { return }
    reload()
  }

  func reload(
    preservingVisibleContent: Bool = false,
    updatesScoreOutcomeInspection: Bool = false
  ) {
    if !updatesScoreOutcomeInspection,
      scoreOutcomeRequiresConfirmation,
      scoreOutcomeInspectionState == .loading
    {
      scoreOutcomeInspectionState = .failed
      scoreOutcomeInspectionResult = .inconclusive
    }
    dataGeneration &+= 1
    let generation = dataGeneration
    let service = service
    loadTask?.cancel()
    pageTask?.cancel()
    pageTask = nil
    pagingState = .idle
    archiveNotice = nil
    let keepsVisibleContent = preservingVisibleContent && loadState == .loaded
    if !keepsVisibleContent {
      loadState = .loading
      notice = nil
    }

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
        if updatesScoreOutcomeInspection {
          self.scoreOutcomeInspectionResult = Self.inspectScoreOutcome(
            scores: scores,
            changes: firstPage.changes,
            snapshot: self.scoreSubmissionSnapshot
          )
          self.scoreOutcomeInspectionState = .loaded
        }
        self.loadTask = nil
      } catch is CancellationError {
        guard let self, self.dataGeneration == generation else { return }
        self.loadTask = nil
        if updatesScoreOutcomeInspection {
          self.scoreOutcomeInspectionState = .failed
          self.scoreOutcomeInspectionResult = .inconclusive
        }
        if keepsVisibleContent {
          self.loadState = .loaded
          self.notice = "최신 마음 기록 확인이 중단됐어요. 현재 화면은 그대로 두었어요."
        } else {
          self.loadState = .failed
        }
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.loadTask = nil
        if self.handleAuthenticationFailure(error) { return }
        if updatesScoreOutcomeInspection {
          self.scoreOutcomeInspectionState = .failed
          self.scoreOutcomeInspectionResult = .inconclusive
        }
        if keepsVisibleContent {
          self.loadState = .loaded
          self.notice = "최신 마음 기록을 불러오지 못했어요. 현재 화면은 그대로 두었어요."
          return
        }
        if error as? WoorisaiAPIError == .serviceUnavailable {
          self.loadState = .unavailable
        } else {
          self.loadState = .failed
        }
      }
    }
  }

  func refresh() async {
    notice = nil
    archiveNotice = nil
    reload(preservingVisibleContent: true)
    let task = loadTask
    await task?.value
    archiveNotice = notice
  }

  func loadNextPage() {
    guard loadState == .loaded, hasNextPage, pageTask == nil else { return }
    let expectedPage = currentPage + 1
    let generation = dataGeneration
    let service = service
    pagingState = .loading
    archiveNotice = nil

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
        self.pagingState = .idle
        self.archiveNotice = nil
      } catch is CancellationError {
        guard let self, self.dataGeneration == generation else { return }
        self.pageTask = nil
        self.pagingState = .idle
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.pageTask = nil
        self.pagingState = .failed
        if self.handleAuthenticationFailure(error) { return }
        self.archiveNotice = "다음 기록을 불러오지 못했어요. 다시 시도해 주세요."
      }
    }
  }

  func canCreateScoreChange(targetScore: Int) -> Bool {
    guard loadState == .loaded,
      scoreSubmissionState != .submitting,
      !scoreOutcomeRequiresConfirmation,
      manualRetryDraftContext == nil || manualRetryDraftContext == .scoreChange,
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

    guard let scores else { return false }
    let submissionSnapshot = ScoreSubmissionSnapshot(
      originalScore: scores.outgoingScore,
      originalUpdatedAt: scores.outgoingUpdatedAt,
      originalChangeIDs: Set(changes.map(\.id)),
      targetScore: targetScore,
      reason: draft.reason,
      attachmentIDs: draft.mediaUploadIDs,
      currentParticipantSlot: scores.currentParticipant.slot
    )

    let generation = dataGeneration
    let service = service
    scoreSubmissionState = .submitting
    localScoreDraftProtected = false
    rejectedMediaMutation = nil
    lastSuccessfulScoreChangeID = nil
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = submissionSnapshot
    if manualRetryDraftContext == .scoreChange {
      manualRetryDraftContext = nil
    }
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
        self.scoreOutcomeRequiresConfirmation = false
        self.scoreOutcomeInspectionState = .idle
        self.scoreOutcomeInspectionResult = .inconclusive
        self.unknownOutcomeTargetScore = nil
        self.scoreSubmissionSnapshot = nil
        self.manualRetryDraftContext = nil
        self.localScoreDraftProtected = false
        self.notice = "새 점수 기록을 남겼어요."
      } catch is CancellationError {
        guard let self, self.dataGeneration == generation else { return }
        self.scoreTask = nil
        self.scoreSubmissionState = .failed
        self.localScoreDraftProtected = true
        self.scoreOutcomeRequiresConfirmation = true
        self.scoreOutcomeInspectionState = .idle
        self.scoreOutcomeInspectionResult = .inconclusive
        self.unknownOutcomeTargetScore = targetScore
        self.notice = "저장 결과를 확인할 수 없어 재전송을 잠갔어요."
      } catch {
        guard let self, self.dataGeneration == generation else { return }
        self.scoreTask = nil
        let isDefinitiveNonCommit = Self.isDefinitiveNonCommit(error)
        if isDefinitiveNonCommit {
          self.rejectedMediaMutation = .scoreChange
        }
        if self.handleAuthenticationFailure(error) { return }
        if error as? WoorisaiAPIError == .conflict {
          self.scoreSubmissionState = .idle
          self.scoreOutcomeRequiresConfirmation = false
          self.scoreOutcomeInspectionResult = .inconclusive
          self.scoreSubmissionSnapshot = nil
          self.manualRetryDraftContext = nil
          self.localScoreDraftProtected = true
          self.conflict = .scoreChange
        } else if isDefinitiveNonCommit {
          self.scoreSubmissionState = .failed
          self.scoreOutcomeRequiresConfirmation = false
          self.scoreOutcomeInspectionResult = .inconclusive
          self.scoreSubmissionSnapshot = nil
          self.manualRetryDraftContext = nil
          self.localScoreDraftProtected = true
          self.notice = "점수 기록을 저장하지 못했어요. 내용을 확인하고 다시 시도해 주세요."
        } else {
          self.scoreSubmissionState = .failed
          self.localScoreDraftProtected = true
          self.scoreOutcomeRequiresConfirmation = true
          self.scoreOutcomeInspectionState = .idle
          self.scoreOutcomeInspectionResult = .inconclusive
          self.unknownOutcomeTargetScore = targetScore
          self.notice = "저장 결과를 확인할 수 없어 재전송을 잠갔어요."
        }
      }
    }
    return true
  }

  func loadThread(
    scoreChangeID: Int64,
    preservingVisibleContent: Bool = false,
    updatesCommentOutcomeInspection: Bool = false
  ) {
    if !updatesCommentOutcomeInspection,
      commentOutcomeRequiresConfirmation,
      commentOutcomeInspectionState == .loading
    {
      commentOutcomeInspectionState = .failed
      commentOutcomeInspectionResult = .inconclusive
    }
    threadGeneration &+= 1
    let generation = threadGeneration
    threadReadGeneration &+= 1
    let readGeneration = threadReadGeneration
    let service = service
    threadTask?.cancel()
    let keepsVisibleContent =
      preservingVisibleContent
      && threadState == .loaded
      && selectedThreadScoreChangeID == scoreChangeID
      && selectedThread != nil
    selectedThreadScoreChangeID = scoreChangeID
    if !keepsVisibleContent {
      selectedThread = nil
      threadState = .loading
    }

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
        if updatesCommentOutcomeInspection {
          self.commentOutcomeInspectionResult = Self.inspectCommentOutcome(
            thread: thread,
            snapshot: self.commentSubmissionSnapshot
          )
          self.commentOutcomeInspectionState = .loaded
        }
        self.threadTask = nil
      } catch is CancellationError {
        guard let self,
          self.threadGeneration == generation,
          self.threadReadGeneration == readGeneration
        else { return }
        self.threadTask = nil
        if updatesCommentOutcomeInspection {
          self.commentOutcomeInspectionState = .failed
          self.commentOutcomeInspectionResult = .inconclusive
        }
        if keepsVisibleContent {
          self.threadState = .loaded
          self.commentNoticeScoreChangeID = scoreChangeID
          self.commentNoticeMessage = "최신 대화 확인이 중단됐어요. 현재 대화와 초안은 그대로 두었어요."
        } else {
          self.threadState = .failed
        }
      } catch {
        guard let self,
          self.threadGeneration == generation,
          self.threadReadGeneration == readGeneration
        else { return }
        self.threadTask = nil
        if self.handleAuthenticationFailure(error) { return }
        if updatesCommentOutcomeInspection {
          self.commentOutcomeInspectionState = .failed
          self.commentOutcomeInspectionResult = .inconclusive
        }
        if keepsVisibleContent {
          self.threadState = .loaded
          self.commentNoticeScoreChangeID = scoreChangeID
          self.commentNoticeMessage = "최신 대화를 불러오지 못했어요. 현재 대화와 초안은 그대로 두었어요."
          return
        }
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
    guard commentSubmissionState != .submitting,
      !commentOutcomeRequiresConfirmation,
      manualRetryDraftContext == nil
        || manualRetryDraftContext == .comment(scoreChangeID: scoreChangeID)
    else { return false }
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

    let originalCommentIDs: Set<Int64>?
    if selectedThreadScoreChangeID == scoreChangeID, let selectedThread {
      originalCommentIDs = Set(selectedThread.comments.map(\.id))
    } else {
      originalCommentIDs = nil
    }
    let submissionSnapshot = CommentSubmissionSnapshot(
      scoreChangeID: scoreChangeID,
      originalCommentIDs: originalCommentIDs,
      content: draft.content,
      attachmentIDs: draft.mediaUploadIDs
    )

    commentWriteGeneration &+= 1
    let writeGeneration = commentWriteGeneration
    let successMinimumCommentCount = knownCommentCount(for: scoreChangeID) + 1
    let service = service
    commentSubmissionScoreChangeID = scoreChangeID
    commentSubmissionState = .submitting
    if localCommentDraftScoreChangeID == scoreChangeID {
      localCommentDraftScoreChangeID = nil
    }
    rejectedMediaMutation = nil
    lastSuccessfulCommentScoreChangeID = nil
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = submissionSnapshot
    if manualRetryDraftContext == .comment(scoreChangeID: scoreChangeID) {
      manualRetryDraftContext = nil
    }
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
        self.localCommentDraftScoreChangeID = nil
        self.clearUnknownCommentOutcome()
        self.commentSubmissionSnapshot = nil
        self.manualRetryDraftContext = nil
        self.commentNoticeScoreChangeID = scoreChangeID
        self.commentNoticeMessage = "댓글을 남겼어요."
      } catch is CancellationError {
        guard let self, self.commentWriteGeneration == writeGeneration else { return }
        self.commentTask = nil
        self.commentSubmissionState = .failed
        self.localCommentDraftScoreChangeID = scoreChangeID
        self.commentOutcomeRequiresConfirmation = true
        self.commentOutcomeInspectionState = .idle
        self.commentOutcomeInspectionResult = .inconclusive
        self.commentOutcomeScoreChangeID = scoreChangeID
        self.commentNoticeScoreChangeID = scoreChangeID
        self.commentNoticeMessage = "댓글 저장 결과를 확인할 수 없어 재전송을 잠갔어요."
      } catch {
        guard let self, self.commentWriteGeneration == writeGeneration else { return }
        self.commentTask = nil
        let isDefinitiveNonCommit = Self.isDefinitiveNonCommit(error)
        if isDefinitiveNonCommit {
          self.rejectedMediaMutation = .comment(scoreChangeID: scoreChangeID)
        }
        if self.handleAuthenticationFailure(error) { return }
        if error as? WoorisaiAPIError == .conflict {
          self.commentSubmissionState = .idle
          self.localCommentDraftScoreChangeID = scoreChangeID
          self.clearUnknownCommentOutcome()
          self.commentSubmissionSnapshot = nil
          self.manualRetryDraftContext = nil
          self.conflict = .comment(scoreChangeID: scoreChangeID)
        } else if isDefinitiveNonCommit {
          self.commentSubmissionState = .failed
          self.localCommentDraftScoreChangeID = scoreChangeID
          self.clearUnknownCommentOutcome()
          self.commentSubmissionSnapshot = nil
          self.manualRetryDraftContext = nil
          self.commentNoticeScoreChangeID = scoreChangeID
          self.commentNoticeMessage = "댓글을 저장하지 못했어요. 내용을 확인하고 다시 시도해 주세요."
        } else {
          self.commentSubmissionState = .failed
          self.localCommentDraftScoreChangeID = scoreChangeID
          self.commentOutcomeRequiresConfirmation = true
          self.commentOutcomeInspectionState = .idle
          self.commentOutcomeInspectionResult = .inconclusive
          self.commentOutcomeScoreChangeID = scoreChangeID
          self.commentNoticeScoreChangeID = scoreChangeID
          self.commentNoticeMessage = "댓글 저장 결과를 확인할 수 없어 재전송을 잠갔어요."
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
      loadThread(scoreChangeID: scoreChangeID, preservingVisibleContent: true)
    }
  }

  func dismissConflict() {
    guard let conflict else { return }
    self.conflict = nil
    switch conflict {
    case .scoreChange:
      reload()
    case .comment(let scoreChangeID):
      loadThread(scoreChangeID: scoreChangeID, preservingVisibleContent: true)
    }
  }

  func dismissNotice() {
    notice = nil
  }

  func inspectUnknownScoreOutcome() {
    guard scoreOutcomeRequiresConfirmation else { return }
    scoreOutcomeInspectionState = .loading
    scoreOutcomeInspectionResult = .inconclusive
    reload(
      preservingVisibleContent: true,
      updatesScoreOutcomeInspection: true
    )
  }

  @discardableResult
  func resolveUnknownScoreOutcomeAsCommitted() -> Bool {
    guard canResolveUnknownScoreOutcomeAsCommitted else { return false }
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localScoreDraftProtected = false
    scoreSubmissionState = .idle
    notice = "이미 저장된 점수 기록을 확인하고 초안을 정리했어요."
    return true
  }

  @discardableResult
  func confirmUnknownScoreOutcomeForRetry() -> Bool {
    guard canRetryUnknownScoreOutcome else { return false }
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = nil
    manualRetryDraftContext = .scoreChange
    localScoreDraftProtected = true
    scoreSubmissionState = .idle
    notice = "저장되지 않은 것을 확인했어요. 다시 기록할 수 있어요."
    return true
  }

  func inspectUnknownCommentOutcome(scoreChangeID: Int64) {
    guard commentOutcomeRequiresConfirmation(for: scoreChangeID) else { return }
    commentOutcomeInspectionState = .loading
    commentOutcomeInspectionResult = .inconclusive
    loadThread(
      scoreChangeID: scoreChangeID,
      preservingVisibleContent: true,
      updatesCommentOutcomeInspection: true
    )
  }

  @discardableResult
  func resolveUnknownCommentOutcomeAsCommitted(scoreChangeID: Int64) -> Bool {
    guard canResolveUnknownCommentOutcomeAsCommitted(for: scoreChangeID) else { return false }
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localCommentDraftScoreChangeID = nil
    commentSubmissionState = .idle
    commentNoticeScoreChangeID = scoreChangeID
    commentNoticeMessage = "이미 저장된 댓글을 확인하고 초안을 정리했어요."
    return true
  }

  @discardableResult
  func confirmUnknownCommentOutcomeForRetry(scoreChangeID: Int64) -> Bool {
    guard canRetryUnknownCommentOutcome(for: scoreChangeID) else { return false }
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = nil
    manualRetryDraftContext = .comment(scoreChangeID: scoreChangeID)
    localCommentDraftScoreChangeID = scoreChangeID
    commentSubmissionState = .idle
    commentNoticeScoreChangeID = scoreChangeID
    commentNoticeMessage = "저장되지 않은 것을 확인했어요. 다시 댓글을 남길 수 있어요."
    return true
  }

  @discardableResult
  func abandonInconclusiveUnknownScoreOutcome() -> Bool {
    // Abandon never resends, so it must stay available even when the inspection could not run
    // (offline). Requiring a successful inspection here would trap the user: the unknown outcome
    // usually WAS a connectivity failure, so the inspection fails too and every recovery action
    // stays disabled while the sheet blocks dismissal.
    guard scoreOutcomeRequiresConfirmation else { return false }
    let verifiedInconclusive =
      scoreOutcomeInspectionState == .loaded && scoreOutcomeInspectionResult == .inconclusive
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localScoreDraftProtected = false
    scoreSubmissionState = .idle
    notice =
      verifiedInconclusive
      ? "중복을 피하기 위해 재전송하지 않고 초안을 정리했어요."
      : "저장 여부를 확인하지 못한 채 재전송 없이 초안을 정리했어요. 나중에 기록에서 저장 여부를 확인해 주세요."
    return true
  }

  @discardableResult
  func abandonInconclusiveUnknownCommentOutcome(scoreChangeID: Int64) -> Bool {
    // Same escape guarantee as the score variant: abandon must not require a successful
    // inspection, or an offline unknown outcome leaves no enabled recovery action.
    guard commentOutcomeRequiresConfirmation(for: scoreChangeID) else { return false }
    let verifiedInconclusive =
      commentOutcomeInspectionState == .loaded && commentOutcomeInspectionResult == .inconclusive
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localCommentDraftScoreChangeID = nil
    commentSubmissionState = .idle
    commentNoticeScoreChangeID = scoreChangeID
    commentNoticeMessage =
      verifiedInconclusive
      ? "중복을 피하기 위해 재전송하지 않고 초안을 정리했어요."
      : "저장 여부를 확인하지 못한 채 재전송 없이 초안을 정리했어요. 나중에 대화에서 저장 여부를 확인해 주세요."
    return true
  }

  func releaseManualRetryDraftProtection(_ context: ManualRetryDraftContext) {
    guard manualRetryDraftContext == context else { return }
    manualRetryDraftContext = nil
  }

  func updateLocalCommentDraftProtection(scoreChangeID: Int64, isProtected: Bool) {
    if isProtected {
      localCommentDraftScoreChangeID = scoreChangeID
    } else if localCommentDraftScoreChangeID == scoreChangeID {
      localCommentDraftScoreChangeID = nil
    }
  }

  func updateLocalScoreDraftProtection(isProtected: Bool) {
    localScoreDraftProtected = isProtected
    if !isProtected, manualRetryDraftContext == .scoreChange {
      manualRetryDraftContext = nil
    }
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
    pagingState = .idle
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
    archiveNotice = nil
    lastSuccessfulScoreChangeID = nil
    lastSuccessfulCommentScoreChangeID = nil
    commentSubmissionScoreChangeID = nil
    commentNoticeScoreChangeID = nil
    commentNoticeMessage = nil
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = nil
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localCommentDraftScoreChangeID = nil
    localScoreDraftProtected = false
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
    pagingState = .idle
    threadState = .idle
    scoreSubmissionState = .idle
    commentSubmissionState = .idle
    lastSuccessfulCommentScoreChangeID = nil
    commentSubmissionScoreChangeID = nil
    commentNoticeScoreChangeID = nil
    commentNoticeMessage = nil
    archiveNotice = nil
    scoreOutcomeRequiresConfirmation = false
    scoreOutcomeInspectionState = .idle
    scoreOutcomeInspectionResult = .inconclusive
    unknownOutcomeTargetScore = nil
    scoreSubmissionSnapshot = nil
    clearUnknownCommentOutcome()
    commentSubmissionSnapshot = nil
    manualRetryDraftContext = nil
    localCommentDraftScoreChangeID = nil
    localScoreDraftProtected = false
    committedCommentOverlays.removeAll()
    authenticationRequired = true
    return true
  }

  private func clearUnknownCommentOutcome() {
    commentOutcomeRequiresConfirmation = false
    commentOutcomeInspectionState = .idle
    commentOutcomeInspectionResult = .inconclusive
    commentOutcomeScoreChangeID = nil
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

  private static func inspectScoreOutcome(
    scores: RelationshipScores,
    changes: [RelationshipScoreChange],
    snapshot: ScoreSubmissionSnapshot?
  ) -> OutcomeInspectionResult {
    guard let snapshot else { return .inconclusive }

    let matchingSubmittedChange = changes.contains { change in
      !snapshot.originalChangeIDs.contains(change.id)
        && change.sourceParticipant.slot == snapshot.currentParticipantSlot
        && change.changedBy.slot == snapshot.currentParticipantSlot
        && change.resultingScore == snapshot.targetScore
        && change.reason == snapshot.reason
        && change.attachments.map(\.id) == snapshot.attachmentIDs
        && change.createdAt >= snapshot.originalUpdatedAt
    }
    if matchingSubmittedChange { return .committed }

    if scores.outgoingScore == snapshot.originalScore,
      scores.outgoingUpdatedAt == snapshot.originalUpdatedAt
    {
      return .notCommitted
    }
    return .inconclusive
  }

  private static func inspectCommentOutcome(
    thread: RelationshipScoreThread,
    snapshot: CommentSubmissionSnapshot?
  ) -> OutcomeInspectionResult {
    guard let snapshot,
      snapshot.scoreChangeID == thread.change.id,
      let originalCommentIDs = snapshot.originalCommentIDs
    else {
      return .inconclusive
    }

    let matchingSubmittedComment = thread.comments.contains { comment in
      !originalCommentIDs.contains(comment.id)
        && comment.author.isCurrentParticipant
        && comment.content == snapshot.content
        && comment.attachments.map(\.id) == snapshot.attachmentIDs
    }
    if matchingSubmittedComment { return .committed }

    let latestCommentIDs = Set(thread.comments.map(\.id))
    return originalCommentIDs.isSubset(of: latestCommentIDs) ? .notCommitted : .inconclusive
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
