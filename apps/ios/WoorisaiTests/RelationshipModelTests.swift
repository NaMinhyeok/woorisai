import Foundation
import Testing
import WoorisaiAPI

@testable import Woorisai

@MainActor
struct RelationshipModelTests {
  @Test
  func loadsScoresAndHistoryAndRejectsUnchangedTargetLocally() async {
    let service = RelationshipServiceFake()
    let model = RelationshipModel(service: service)

    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    #expect(model.scores == RelationshipFixtures.scores)
    #expect(model.changes == [RelationshipFixtures.change])
    #expect(!model.canCreateScoreChange(targetScore: 70))
    #expect(model.canCreateScoreChange(targetScore: 71))

    model.createScoreChange(targetScore: 70, reason: "같은 점수")

    #expect(model.scoreSubmissionState == .failed)
    #expect(model.notice == "현재 점수와 다른 점수를 선택해 주세요.")
    #expect(await service.scoreCreateCount == 0)
  }

  @Test
  func invalidMediaBearingDraftIsRejectedBeforeSubmissionOwnershipTransfers() async {
    let service = RelationshipServiceFake()
    let model = RelationshipModel(service: service)
    let uploadID = UUID(uuidString: "00000000-0000-0000-0000-000000000091")!
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    let scoreAccepted = model.createScoreChange(
      targetScore: 75,
      reason: String(repeating: "가", count: 201),
      mediaUploadIDs: [uploadID]
    )
    let commentAccepted = model.createComment(
      scoreChangeID: RelationshipFixtures.change.id,
      content: String(repeating: "나", count: 501),
      mediaUploadIDs: [uploadID]
    )

    #expect(!scoreAccepted)
    #expect(!commentAccepted)
    #expect(await service.scoreCreateCount == 0)
    #expect(await service.commentCreateCount == 0)
  }

  @Test
  func conflictDoesNotRetryCreateAndReloadsOnlyAfterExplicitAction() async {
    let service = RelationshipServiceFake(scoreWrite: .conflict)
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createScoreChange(targetScore: 75, reason: "새 점수")
    await relationshipExpectEventually { model.conflict == .scoreChange }

    #expect(model.rejectedMediaMutation == .scoreChange)
    #expect(await service.scoreCreateCount == 1)
    #expect(await service.scoreLoadCount == 1)
    #expect(await service.historyLoadCount == 1)

    model.reloadAfterConflict()
    await relationshipExpectEventually {
      let loadCount = await service.scoreLoadCount
      return model.loadState == .loaded && loadCount == 2
    }

    #expect(await service.scoreCreateCount == 1)
    #expect(await service.historyLoadCount == 2)
    #expect(model.conflict == nil)
  }

  @Test
  func ambiguousWriteFailureIsIssuedOnceWithoutAutomaticRetry() async {
    let service = RelationshipServiceFake(scoreWrite: .transport)
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createScoreChange(targetScore: 75, reason: "새 점수")
    await relationshipExpectEventually { model.scoreSubmissionState == .failed }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(await service.scoreCreateCount == 1)
    #expect(model.notice?.contains("자동으로 다시 보내지 않았습니다") == true)
  }

  @Test
  func commentConflictReloadsThreadOnlyAfterExplicitAction() async {
    let service = RelationshipServiceFake(commentWrite: .conflict)
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually {
      model.conflict == .comment(scoreChangeID: RelationshipFixtures.change.id)
    }

    #expect(
      model.rejectedMediaMutation
        == .comment(scoreChangeID: RelationshipFixtures.change.id)
    )
    #expect(await service.commentCreateCount == 1)
    #expect(await service.threadLoadCount == 1)

    model.reloadAfterConflict()
    await relationshipExpectEventually {
      let loadCount = await service.threadLoadCount
      return model.threadState == .loaded && loadCount == 2
    }
    #expect(await service.commentCreateCount == 1)
  }

  @Test
  func dismissingConflictReloadsKnownStaleScoreAndThreadSnapshots() async {
    let scoreService = RelationshipServiceFake(scoreWrite: .conflict)
    let scoreModel = RelationshipModel(service: scoreService)
    scoreModel.loadIfNeeded()
    await relationshipExpectEventually { scoreModel.loadState == .loaded }
    scoreModel.createScoreChange(targetScore: 75, reason: "경합한 점수")
    await relationshipExpectEventually { scoreModel.conflict == .scoreChange }

    scoreModel.dismissConflict()

    #expect(scoreModel.conflict == nil)
    #expect(scoreModel.loadState == .loading)
    await relationshipExpectEventually {
      await scoreService.scoreLoadCount == 2 && scoreModel.loadState == .loaded
    }

    let commentService = RelationshipServiceFake(commentWrite: .conflict)
    let commentModel = RelationshipModel(service: commentService)
    commentModel.loadIfNeeded()
    await relationshipExpectEventually { commentModel.loadState == .loaded }
    commentModel.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { commentModel.threadState == .loaded }
    commentModel.createComment(
      scoreChangeID: RelationshipFixtures.change.id,
      content: "경합한 댓글"
    )
    await relationshipExpectEventually {
      commentModel.conflict == .comment(scoreChangeID: RelationshipFixtures.change.id)
    }

    commentModel.dismissConflict()

    #expect(commentModel.conflict == nil)
    #expect(commentModel.selectedThread == nil)
    #expect(commentModel.threadState == .loading)
    await relationshipExpectEventually {
      await commentService.threadLoadCount == 2 && commentModel.threadState == .loaded
    }
  }

  @Test
  func commentTransportFailureIsVisibleAndNotAutomaticallyRetried() async {
    let service = RelationshipServiceFake(commentWrite: .transport)
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { model.commentSubmissionState == .failed }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(await service.commentCreateCount == 1)
    #expect(
      model.commentNotice(for: RelationshipFixtures.change.id)?
        .contains("자동 재시도하지 않았습니다") == true
    )
  }

  @Test
  func unauthorizedReadClearsFeatureCacheAndRequestsPIN() async {
    let service = RelationshipServiceFake(read: .credentialRejected)
    let model = RelationshipModel(service: service)

    model.loadIfNeeded()
    await relationshipExpectEventually { model.authenticationRequired }

    #expect(model.scores == nil)
    #expect(model.changes.isEmpty)
    #expect(model.selectedThread == nil)
    #expect(await service.historyLoadCount == 0)
  }

  @Test
  func clearDropsAllRelationshipCacheForLocalSignOut() async {
    let service = RelationshipServiceFake()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.clear()

    #expect(model.loadState == .idle)
    #expect(model.threadState == .idle)
    #expect(model.scores == nil)
    #expect(model.changes.isEmpty)
    #expect(model.selectedThread == nil)
  }

  @Test
  func reloadDuringPaginationDoesNotLeaveNextPagePermanentlyBlocked() async {
    let service = ControlledPaginationService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.loadNextPage()
    await relationshipExpectEventually { await service.pageTwoRequestCount == 1 }

    model.reload()
    await relationshipExpectEventually {
      let firstPageCount = await service.firstPageRequestCount
      return model.loadState == .loaded && firstPageCount == 2
    }

    model.loadNextPage()
    await relationshipExpectEventually { await service.pageTwoRequestCount == 2 }
    await service.succeedPageTwo(request: 1)
    await relationshipExpectEventually { model.currentPage == 2 }

    // Let the canceled, stale request finish last; its generation must not replace the new page.
    await service.succeedPageTwo(request: 0)
    await Task.yield()
    #expect(model.currentPage == 2)
    #expect(model.changes.map(\.id) == [101, 102])
  }

  @Test
  func screenExitInvalidatesThreadReadAndIgnoresItsLateCompletion() async {
    let service = ControlledThreadReadService()
    let model = RelationshipModel(service: service)

    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { await service.threadRequestCount == 1 }
    #expect(model.threadState == .loading)

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)

    #expect(model.threadState == .idle)
    #expect(model.selectedThread == nil)

    await service.succeedThreadRead()
    await relationshipExpectEventually { await service.threadReturnCount == 1 }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.threadState == .idle)
    #expect(model.selectedThread == nil)
  }

  @Test
  func exitingPreviousThreadDoesNotCancelReplacementRead() async {
    let service = ControlledThreadReadService()
    let model = RelationshipModel(service: service)

    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { await service.threadRequestCount == 1 }

    model.loadThread(scoreChangeID: RelationshipFixtures.createdChange.id)
    await relationshipExpectEventually { await service.threadRequestCount == 2 }

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    #expect(model.threadState == .loading)
    #expect(model.selectedThreadScoreChangeID == RelationshipFixtures.createdChange.id)

    await service.succeedThreadRead(
      scoreChangeID: RelationshipFixtures.createdChange.id,
      with: RelationshipFixtures.secondThread
    )
    await relationshipExpectEventually {
      model.threadState == .loaded
        && model.selectedThread?.change.id == RelationshipFixtures.createdChange.id
    }

    await service.succeedThreadRead(
      scoreChangeID: RelationshipFixtures.change.id,
      with: RelationshipFixtures.thread
    )
    await relationshipExpectEventually { await service.threadReturnCount == 2 }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.threadState == .loaded)
    #expect(model.selectedThread == RelationshipFixtures.secondThread)
  }

  @Test
  func navigatingToAnotherThreadSettlesIssuedCommentWriteWithoutMutatingSelection() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    #expect(model.commentSubmissionState == .submitting)

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    #expect(model.threadState == .idle)
    #expect(model.selectedThread == nil)
    model.loadThread(scoreChangeID: RelationshipFixtures.createdChange.id)
    await relationshipExpectEventually {
      model.selectedThread?.change.id == RelationshipFixtures.createdChange.id
    }
    #expect(model.commentSubmissionState == .submitting)
    #expect(
      model.commentSubmissionState(for: RelationshipFixtures.createdChange.id) == .idle
    )
    #expect(model.commentNotice(for: RelationshipFixtures.createdChange.id) == nil)

    await service.succeedCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .idle }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(await service.commentRequestCount == 1)
    #expect(model.selectedThread == RelationshipFixtures.secondThread)
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 2
    )
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.createdChange.id })?.commentCount
        == 0
    )
    #expect(model.lastSuccessfulCommentScoreChangeID == RelationshipFixtures.change.id)
    #expect(model.commentNotice(for: RelationshipFixtures.change.id) == "댓글을 남겼어요.")
    #expect(model.commentNotice(for: RelationshipFixtures.createdChange.id) == nil)
  }

  @Test
  func ambiguousCommentOutcomeAfterNavigationSettlesWithoutRetryOrNewThreadMutation() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    model.loadThread(scoreChangeID: RelationshipFixtures.createdChange.id)
    await relationshipExpectEventually {
      model.selectedThread?.change.id == RelationshipFixtures.createdChange.id
    }

    await service.failCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .failed }
    try? await Task.sleep(for: .milliseconds(30))

    #expect(await service.commentRequestCount == 1)
    #expect(model.selectedThread == RelationshipFixtures.secondThread)
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 1
    )
    #expect(model.lastSuccessfulCommentScoreChangeID == nil)
    #expect(
      model.commentNotice(for: RelationshipFixtures.change.id)?
        .contains("자동 재시도하지 않았습니다") == true
    )
    #expect(model.commentNotice(for: RelationshipFixtures.createdChange.id) == nil)
  }

  @Test
  func committedCommentIsMergedIntoLateStaleReadOfSameThread() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    await service.delayNextThreadRead(scoreChangeID: RelationshipFixtures.change.id)
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { await service.hasDelayedThreadRead }

    await service.succeedCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .idle }
    #expect(model.threadState == .loading)

    await service.succeedDelayedThreadRead(with: RelationshipFixtures.thread)
    await relationshipExpectEventually { model.threadState == .loaded }

    #expect(model.selectedThread?.change.commentCount == 2)
    #expect(model.selectedThread?.comments.map(\.id) == [301, 302])
    #expect(model.commentNotice(for: RelationshipFixtures.change.id) == "댓글을 남겼어요.")
    #expect(await service.commentRequestCount == 1)
  }

  @Test
  func mixedThreadSnapshotDoesNotDoubleCountAcknowledgedComment() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    await service.succeedCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .idle }

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    await service.delayNextThreadRead(scoreChangeID: RelationshipFixtures.change.id)
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { await service.hasDelayedThreadRead }
    await service.succeedDelayedThreadRead(with: RelationshipFixtures.mixedCaughtUpThread)
    await relationshipExpectEventually { model.threadState == .loaded }

    #expect(model.selectedThread?.change.commentCount == 2)
    #expect(model.selectedThread?.comments.map(\.id) == [301, 302])
    #expect(await service.commentRequestCount == 1)
  }

  @Test
  func reloadStartedBeforeCommentSuccessPreservesCountWhenStaleHistoryFinishesLast() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    await service.delayNextHistoryRead()
    model.reload()
    await relationshipExpectEventually { await service.hasDelayedHistoryRead }

    await service.succeedCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .idle }
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 2
    )

    await service.succeedDelayedHistoryRead(with: RelationshipFixtures.pageWithSecondChange)
    await relationshipExpectEventually { model.loadState == .loaded }

    #expect(await service.commentRequestCount == 1)
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 2
    )
    #expect(model.commentNotice(for: RelationshipFixtures.change.id) == "댓글을 남겼어요.")
  }

  @Test
  func reloadStartedAfterCommentSuccessPreservesStaleCountWithoutDuplicatingCaughtUpCount() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    await service.succeedCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .idle }

    await service.delayNextHistoryRead()
    model.reload()
    await relationshipExpectEventually { await service.hasDelayedHistoryRead }
    await service.succeedDelayedHistoryRead(with: RelationshipFixtures.pageWithSecondChange)
    await relationshipExpectEventually { model.loadState == .loaded }
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 2
    )

    await service.delayNextHistoryRead()
    model.reload()
    await relationshipExpectEventually { await service.hasDelayedHistoryRead }
    await service.succeedDelayedHistoryRead(with: RelationshipFixtures.caughtUpPage)
    await relationshipExpectEventually { model.loadState == .loaded }

    #expect(await service.commentRequestCount == 1)
    #expect(
      model.changes.first(where: { $0.id == RelationshipFixtures.change.id })?.commentCount == 2
    )
  }

  @Test
  func ambiguousCommentOutcomeRemainsVisibleWhenReloadChangesDataGeneration() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    await service.delayNextHistoryRead()
    model.reload()
    await relationshipExpectEventually { await service.hasDelayedHistoryRead }

    await service.failCommentWrite()
    await relationshipExpectEventually { model.commentSubmissionState == .failed }
    await service.succeedDelayedHistoryRead(with: RelationshipFixtures.pageWithSecondChange)
    await relationshipExpectEventually { model.loadState == .loaded }

    #expect(await service.commentRequestCount == 1)
    #expect(
      model.commentNotice(for: RelationshipFixtures.change.id)?
        .contains("자동 재시도하지 않았습니다") == true
    )
  }

  @Test
  func commentConflictRemainsActionableWhenReloadChangesDataGeneration() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }

    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }
    await service.delayNextHistoryRead()
    model.reload()
    await relationshipExpectEventually { await service.hasDelayedHistoryRead }

    await service.conflictCommentWrite()
    await relationshipExpectEventually {
      model.conflict == .comment(scoreChangeID: RelationshipFixtures.change.id)
    }
    await service.succeedDelayedHistoryRead(with: RelationshipFixtures.pageWithSecondChange)
    await relationshipExpectEventually { model.loadState == .loaded }

    #expect(await service.commentRequestCount == 1)
    #expect(model.commentSubmissionState == .idle)
    #expect(model.conflict == .comment(scoreChangeID: RelationshipFixtures.change.id))
  }

  @Test
  func cacheClearIgnoresLateCommentWriteCompletion() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }
    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }

    model.clear()
    await service.succeedCommentWrite()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.loadState == .idle)
    #expect(model.threadState == .idle)
    #expect(model.commentSubmissionState == .idle)
    #expect(model.commentSubmissionScoreChangeID == nil)
    #expect(model.scores == nil)
    #expect(model.changes.isEmpty)
    #expect(model.selectedThread == nil)
    #expect(model.commentNotice(for: RelationshipFixtures.change.id) == nil)
    #expect(await service.commentRequestCount == 1)
  }

  @Test
  func authenticationFailureIgnoresLateCommentWriteCompletion() async {
    let service = ControlledCommentWriteService()
    let model = RelationshipModel(service: service)
    model.loadIfNeeded()
    await relationshipExpectEventually { model.loadState == .loaded }
    model.loadThread(scoreChangeID: RelationshipFixtures.change.id)
    await relationshipExpectEventually { model.threadState == .loaded }
    model.createComment(scoreChangeID: RelationshipFixtures.change.id, content: "새 댓글")
    await relationshipExpectEventually { await service.commentRequestCount == 1 }

    model.cancelThreadReadForScreenExit(scoreChangeID: RelationshipFixtures.change.id)
    await service.rejectNextThreadRead(scoreChangeID: RelationshipFixtures.createdChange.id)
    model.loadThread(scoreChangeID: RelationshipFixtures.createdChange.id)
    await relationshipExpectEventually { model.authenticationRequired }
    await service.succeedCommentWrite()
    try? await Task.sleep(for: .milliseconds(30))

    #expect(model.loadState == .idle)
    #expect(model.threadState == .idle)
    #expect(model.commentSubmissionState == .idle)
    #expect(model.commentSubmissionScoreChangeID == nil)
    #expect(model.scores == nil)
    #expect(model.changes.isEmpty)
    #expect(model.selectedThread == nil)
    #expect(model.commentNotice(for: RelationshipFixtures.change.id) == nil)
    #expect(await service.commentRequestCount == 1)
  }

  @Test
  func submissionAccessibilityDescribesIdleFailureAndProgressStates() {
    #expect(
      RelationshipSubmissionAccessibility.score(
        state: .idle,
        targetScore: 75,
        canSubmit: true
      )
        == RelationshipSubmissionAccessibility(
          label: "점수 기록하기",
          value: "선택한 점수 75점"
        )
    )
    #expect(
      RelationshipSubmissionAccessibility.score(
        state: .submitting,
        targetScore: 75,
        canSubmit: false
      ) == RelationshipSubmissionAccessibility(label: "점수 저장 중", value: "진행 중")
    )
    #expect(
      RelationshipSubmissionAccessibility.comment(
        state: .failed,
        hasContent: true,
        isBlockedByAnotherSubmission: false
      )
        == RelationshipSubmissionAccessibility(
          label: "댓글 남기기",
          value: "이전 저장 실패, 입력한 댓글 저장 가능"
        )
    )
    #expect(
      RelationshipSubmissionAccessibility.comment(
        state: .idle,
        hasContent: true,
        isBlockedByAnotherSubmission: false
      )
        == RelationshipSubmissionAccessibility(
          label: "댓글 남기기",
          value: "입력한 댓글 저장 가능"
        )
    )
    #expect(
      RelationshipSubmissionAccessibility.comment(
        state: .submitting,
        hasContent: true
      ) == RelationshipSubmissionAccessibility(label: "댓글 저장 중", value: "진행 중")
    )
    #expect(
      RelationshipSubmissionAccessibility.comment(
        state: .idle,
        hasContent: true,
        isBlockedByAnotherSubmission: true
      )
        == RelationshipSubmissionAccessibility(
          label: "댓글 남기기",
          value: "다른 댓글 저장이 끝날 때까지 기다려 주세요"
        )
    )
  }
}

private actor RelationshipServiceFake: RelationshipServing {
  enum Read: Sendable { case credentialRejected, success }
  enum Write: Sendable { case conflict, success, transport }

  private let read: Read
  private let scoreWrite: Write
  private let commentWrite: Write
  private(set) var scoreLoadCount = 0
  private(set) var historyLoadCount = 0
  private(set) var scoreCreateCount = 0
  private(set) var threadLoadCount = 0
  private(set) var commentCreateCount = 0

  init(read: Read = .success, scoreWrite: Write = .success, commentWrite: Write = .success) {
    self.read = read
    self.scoreWrite = scoreWrite
    self.commentWrite = commentWrite
  }

  func loadRelationshipScores() async throws -> RelationshipScores {
    scoreLoadCount += 1
    if read == .credentialRejected { throw WoorisaiAPIError.credentialRejected }
    return RelationshipFixtures.scores
  }

  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    historyLoadCount += 1
    return RelationshipFixtures.page
  }

  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    scoreCreateCount += 1
    switch scoreWrite {
    case .conflict: throw WoorisaiAPIError.conflict
    case .transport: throw WoorisaiAPIError.transport
    case .success: return RelationshipFixtures.created
    }
  }

  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    threadLoadCount += 1
    return RelationshipFixtures.thread
  }

  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    commentCreateCount += 1
    switch commentWrite {
    case .conflict: throw WoorisaiAPIError.conflict
    case .transport: throw WoorisaiAPIError.transport
    case .success: return RelationshipFixtures.createdComment
    }
  }
}

private actor ControlledPaginationService: RelationshipServing {
  private var pageTwoContinuations:
    [Int: CheckedContinuation<RelationshipScoreChangePage, any Error>] = [:]
  private(set) var firstPageRequestCount = 0
  private(set) var pageTwoRequestCount = 0

  func loadRelationshipScores() async throws -> RelationshipScores {
    RelationshipFixtures.scores
  }

  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    if pageNumber == 1 {
      firstPageRequestCount += 1
      return RelationshipScoreChangePage(
        changes: [RelationshipFixtures.change],
        pageNumber: 1,
        hasNext: true,
        totalCount: 2
      )
    }

    let request = pageTwoRequestCount
    pageTwoRequestCount += 1
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        pageTwoContinuations[request] = continuation
      }
    } onCancel: {
      // Deliberately finish after reload to exercise stale page cleanup.
    }
  }

  func succeedPageTwo(request: Int) {
    pageTwoContinuations.removeValue(forKey: request)?.resume(
      returning: RelationshipScoreChangePage(
        changes: [RelationshipFixtures.createdChange],
        pageNumber: 2,
        hasNext: false,
        totalCount: 2
      )
    )
  }

  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    throw RelationshipModelTestFailure.unexpectedOperation
  }
}

private actor ControlledThreadReadService: RelationshipServing {
  private var continuations: [Int64: CheckedContinuation<RelationshipScoreThread, any Error>] = [:]
  private(set) var threadRequestCount = 0
  private(set) var threadReturnCount = 0

  func loadRelationshipScores() async throws -> RelationshipScores {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    threadRequestCount += 1
    let thread = try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        continuations[id] = continuation
      }
    } onCancel: {
      // Deliberately complete after cancellation to verify the model ignores stale data.
    }
    threadReturnCount += 1
    return thread
  }

  func succeedThreadRead(
    scoreChangeID: Int64 = RelationshipFixtures.change.id,
    with thread: RelationshipScoreThread = RelationshipFixtures.thread
  ) {
    continuations.removeValue(forKey: scoreChangeID)?.resume(returning: thread)
  }

  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    throw RelationshipModelTestFailure.unexpectedOperation
  }
}

private actor ControlledCommentWriteService: RelationshipServing {
  private var continuation: CheckedContinuation<RelationshipScoreComment, any Error>?
  private var delayNextHistoryRequest = false
  private var delayedHistoryContinuation:
    CheckedContinuation<RelationshipScoreChangePage, any Error>?
  private var delayedThreadContinuation: CheckedContinuation<RelationshipScoreThread, any Error>?
  private var delayedThreadScoreChangeID: Int64?
  private var rejectedThreadScoreChangeID: Int64?
  private(set) var commentRequestCount = 0
  private(set) var threadRequestCount = 0

  func loadRelationshipScores() async throws -> RelationshipScores {
    RelationshipFixtures.scores
  }

  func loadScoreChanges(pageNumber: Int) async throws -> RelationshipScoreChangePage {
    if delayNextHistoryRequest {
      delayNextHistoryRequest = false
      return try await withCheckedThrowingContinuation { continuation in
        delayedHistoryContinuation = continuation
      }
    }
    return RelationshipFixtures.pageWithSecondChange
  }

  func delayNextHistoryRead() {
    delayNextHistoryRequest = true
  }

  var hasDelayedHistoryRead: Bool {
    delayedHistoryContinuation != nil
  }

  func succeedDelayedHistoryRead(with page: RelationshipScoreChangePage) {
    delayedHistoryContinuation?.resume(returning: page)
    delayedHistoryContinuation = nil
  }

  func createScoreChange(
    _ draft: RelationshipScoreChangeDraft
  ) async throws -> RelationshipScoreChangeCreated {
    throw RelationshipModelTestFailure.unexpectedOperation
  }

  func loadScoreChange(id: Int64) async throws -> RelationshipScoreThread {
    threadRequestCount += 1
    if rejectedThreadScoreChangeID == id {
      rejectedThreadScoreChangeID = nil
      throw WoorisaiAPIError.credentialRejected
    }
    if delayedThreadScoreChangeID == id {
      delayedThreadScoreChangeID = nil
      return try await withCheckedThrowingContinuation { continuation in
        delayedThreadContinuation = continuation
      }
    }

    switch id {
    case RelationshipFixtures.change.id:
      return RelationshipFixtures.thread
    case RelationshipFixtures.createdChange.id:
      return RelationshipFixtures.secondThread
    default:
      throw WoorisaiAPIError.notFound
    }
  }

  func delayNextThreadRead(scoreChangeID: Int64) {
    delayedThreadScoreChangeID = scoreChangeID
  }

  func rejectNextThreadRead(scoreChangeID: Int64) {
    rejectedThreadScoreChangeID = scoreChangeID
  }

  var hasDelayedThreadRead: Bool {
    delayedThreadContinuation != nil
  }

  func succeedDelayedThreadRead(with thread: RelationshipScoreThread) {
    delayedThreadContinuation?.resume(returning: thread)
    delayedThreadContinuation = nil
  }

  func createScoreChangeComment(
    scoreChangeID: Int64,
    draft: RelationshipScoreCommentDraft
  ) async throws -> RelationshipScoreComment {
    commentRequestCount += 1
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
      }
    } onCancel: {
      // A screen exit must not cancel an already-issued non-idempotent write.
    }
  }

  func succeedCommentWrite() {
    continuation?.resume(returning: RelationshipFixtures.createdComment)
    continuation = nil
  }

  func failCommentWrite() {
    continuation?.resume(throwing: WoorisaiAPIError.transport)
    continuation = nil
  }

  func conflictCommentWrite() {
    continuation?.resume(throwing: WoorisaiAPIError.conflict)
    continuation = nil
  }
}

private enum RelationshipModelTestFailure: Error, Sendable {
  case unexpectedOperation
}

private enum RelationshipFixtures {
  static let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
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
  static let scores = RelationshipScores(
    currentParticipant: current,
    partner: partner,
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
  static let page = RelationshipScoreChangePage(
    changes: [change],
    pageNumber: 1,
    hasNext: false,
    totalCount: 1
  )
  static let thread = RelationshipScoreThread(change: change, comments: [comment])
  static let createdChange = RelationshipScoreChange(
    id: 102,
    sourceParticipant: current,
    targetParticipant: partner,
    changedBy: current,
    delta: 5,
    resultingScore: 75,
    reason: "새 점수",
    createdAt: timestamp.addingTimeInterval(2),
    commentCount: 0,
    attachments: []
  )
  static let pageWithSecondChange = RelationshipScoreChangePage(
    changes: [change, createdChange],
    pageNumber: 1,
    hasNext: false,
    totalCount: 2
  )
  static let changeWithAcknowledgedComment = RelationshipScoreChange(
    id: change.id,
    sourceParticipant: change.sourceParticipant,
    targetParticipant: change.targetParticipant,
    changedBy: change.changedBy,
    delta: change.delta,
    resultingScore: change.resultingScore,
    reason: change.reason,
    createdAt: change.createdAt,
    commentCount: 2,
    attachments: change.attachments
  )
  static let caughtUpPage = RelationshipScoreChangePage(
    changes: [changeWithAcknowledgedComment, createdChange],
    pageNumber: 1,
    hasNext: false,
    totalCount: 2
  )
  static let mixedCaughtUpThread = RelationshipScoreThread(
    change: changeWithAcknowledgedComment,
    comments: [comment]
  )
  static let secondThread = RelationshipScoreThread(change: createdChange, comments: [])
  static let created = RelationshipScoreChangeCreated(
    change: createdChange,
    outgoingScore: 75,
    outgoingUpdatedAt: createdChange.createdAt
  )
  static let createdComment = RelationshipScoreComment(
    id: 302,
    author: current,
    content: "새 댓글",
    createdAt: timestamp.addingTimeInterval(3),
    attachments: []
  )
}

@MainActor
private func relationshipExpectEventually(
  _ condition: @escaping @MainActor () async -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  for _ in 0..<200 {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("관계 상태가 제한 시간 안에 수렴하지 않았습니다.", sourceLocation: sourceLocation)
}
