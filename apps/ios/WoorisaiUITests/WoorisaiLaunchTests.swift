import XCTest

@MainActor
final class WoorisaiLaunchTests: XCTestCase {
  private static let scenarioArgument = "--login-options-ui-test-scenario"
  private static let header = "우리 둘만의 작은 마음 기록"
  private static let loadingMessage = "두 사람의 이름을 불러오고 있어요."
  private static let unavailableMessage =
    "지금은 로그인할 사람을 확인할 수 없어요. 잠시 후 다시 시도해 주세요."
  private static let failureMessage =
    "로그인 정보를 불러오지 못했어요. 네트워크 연결을 확인하고 다시 시도해 주세요."
  private static let longFirstName =
    "가나다라마바사아자차카타파하가나다라마바사아자차카타파하"
  private static let longSecondName = "우리사이에서사용하는아주긴두번째참가자이름"
  private static let accessibilityExtraExtraExtraLarge =
    "accessibility-extra-extra-extra-large"
  private static let relationshipMediaFixtures = [
    MediaFixture(
      id: "10000000-0000-0000-0000-000000000001",
      fileName: "portrait-heart.jpg",
      expectedViewerAspectRatio: 360 / 640
    ),
    MediaFixture(
      id: "10000000-0000-0000-0000-000000000002",
      fileName: "landscape-picnic.jpg",
      expectedViewerAspectRatio: 640 / 360
    ),
    MediaFixture(
      id: "10000000-0000-0000-0000-000000000003",
      fileName: "panorama-sunset.jpg",
      expectedViewerAspectRatio: 960 / 240
    ),
    MediaFixture(
      id: "10000000-0000-0000-0000-000000000004",
      fileName: "square-cookie.jpg",
      expectedViewerAspectRatio: 1
    ),
  ]
  private static let diaryMediaFixtures = [
    MediaFixture(
      id: "20000000-0000-0000-0000-000000000001",
      fileName: "portrait-flower.jpg",
      expectedViewerAspectRatio: 360 / 640
    ),
    MediaFixture(
      id: "20000000-0000-0000-0000-000000000002",
      fileName: "landscape-table.jpg",
      expectedViewerAspectRatio: 640 / 360
    ),
    MediaFixture(
      id: "20000000-0000-0000-0000-000000000003",
      fileName: "panorama-river.jpg",
      expectedViewerAspectRatio: 960 / 240
    ),
    MediaFixture(
      id: "20000000-0000-0000-0000-000000000004",
      fileName: "square-dessert.jpg",
      expectedViewerAspectRatio: 1
    ),
  ]

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testSuccessShowsBothParticipantNames() {
    let app = launch(scenario: "success")

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("loginOptions.participant.1", in: app).exists)
    XCTAssertTrue(element("loginOptions.participant.2", in: app).exists)
    XCTAssertTrue(app.staticTexts["봄"].exists)
    XCTAssertTrue(app.staticTexts["여름"].exists)
  }

  func testSuccessFollowsSystemAppearance() {
    let expectedColorScheme: String
    switch XCUIDevice.shared.appearance {
    case .light:
      expectedColorScheme = "light"
    case .dark:
      expectedColorScheme = "dark"
    case .unspecified:
      XCTFail("The test device must report a concrete system appearance")
      return
    @unknown default:
      XCTFail("The test device reported an unsupported system appearance")
      return
    }

    let app = launch(scenario: "success")

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    let colorScheme = element("loginOptions.colorScheme", in: app)
    XCTAssertTrue(colorScheme.exists)
    XCTAssertEqual(colorScheme.label, expectedColorScheme)
  }

  func testRelationshipReasonKeyboardHasExplicitDismissAction() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openRelationshipScoreComposer(in: app)

    let reason = element("relationship.reason", in: app)
    XCTAssertTrue(reason.waitForExistence(timeout: 5))
    scrollToHittable(reason, in: app)
    reason.tap()

    dismissKeyboard(in: app)
    XCTAssertTrue(reason.exists)
  }

  func testDiaryEditorKeyboardHasExplicitDismissAction() {
    let app = launch(scenario: "emptyContent")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))

    let openComposer = element("diary.createEntry.open", in: app)
    XCTAssertTrue(openComposer.exists)
    openComposer.tap()

    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()

    dismissKeyboard(in: app)
    XCTAssertTrue(content.exists)
  }

  func testSuccessSupportsAccessibilityExtraExtraExtraLargeText() {
    let app = launch(scenario: "longNames")

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    let dynamicTypeMarker = element("loginOptions.dynamicTypeSize", in: app)
    XCTAssertTrue(dynamicTypeMarker.exists)
    XCTAssertEqual(dynamicTypeMarker.label, Self.accessibilityExtraExtraExtraLarge)
    XCTAssertTrue(element("loginOptions.participant.1", in: app).exists)
    XCTAssertTrue(element("loginOptions.participant.2", in: app).exists)
    let firstName = app.staticTexts[Self.longFirstName]
    let secondName = app.staticTexts[Self.longSecondName]
    XCTAssertTrue(firstName.exists)
    XCTAssertTrue(secondName.exists)
    XCTAssertGreaterThan(firstName.frame.height, 80)
    let secondNameYBeforeScroll = secondName.frame.minY

    XCTAssertTrue(app.scrollViews.firstMatch.exists)
    app.swipeUp()
    XCTAssertLessThan(secondName.frame.minY, secondNameYBeforeScroll)
  }

  func testUnavailableCanRetryToSuccess() {
    let app = launch(scenario: "unavailableThenSuccess")

    XCTAssertTrue(element("loginOptions.unavailable", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[Self.unavailableMessage].exists)

    let retry = element("loginOptions.retry", in: app)
    XCTAssertTrue(retry.exists)
    retry.tap()

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["봄"].exists)
    XCTAssertTrue(app.staticTexts["여름"].exists)
  }

  func testLoadingStateIsDeterministic() {
    let app = launch(scenario: "loading")

    XCTAssertTrue(element("loginOptions.loading", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[Self.loadingMessage].exists)
  }

  func testGeneralFailureCanRetryToSuccess() {
    let app = launch(scenario: "failureThenSuccess")

    XCTAssertTrue(element("loginOptions.failed", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[Self.failureMessage].exists)

    let retry = element("loginOptions.retry", in: app)
    XCTAssertTrue(retry.exists)
    retry.tap()

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["봄"].exists)
    XCTAssertTrue(app.staticTexts["여름"].exists)
  }

  func testRejectedPINCanBeEnteredAgainThenShowsRelationship() {
    let app = launch(scenario: "authenticationRejectedThenSuccess")

    enterPIN("9999", participantSlot: 1, in: app)
    XCTAssertTrue(element("authentication.rejected", in: app).waitForExistence(timeout: 5))

    submitPIN("0123", in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("relationship.outgoingScore", in: app).waitForExistence(timeout: 5))
  }

  func testSessionCredentialRejectionReturnsToPINRecovery() {
    let app = launch(scenario: "sessionCredentialRejected")
    enterPIN("0123", participantSlot: 1, in: app)

    let rejected = element("authentication.rejected", in: app)
    XCTAssertTrue(rejected.waitForExistence(timeout: 10))
    XCTAssertTrue(element("authentication.pinEntry", in: app).exists)
    XCTAssertTrue(element("authentication.actionBar", in: app).exists)
    XCTAssertFalse(app.keyboards.firstMatch.exists)

    submitPIN("0123", in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 10))
  }

  func testNumberPadCanBeDismissedWithoutSubmitting() {
    let app = launch(scenario: "success")
    let participant = element("loginOptions.participant.1", in: app)
    XCTAssertTrue(participant.waitForExistence(timeout: 5))
    participant.tap()

    let pin = element("authentication.pin", in: app)
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    scrollToHittable(pin, in: app, maximumSwipes: 3)
    pin.tap()

    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
    let dismissKeyboard = element("keyboard.dismiss", in: app)
    XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
    dismissKeyboard.tap()

    let keyboardDismissed = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "exists == false"),
      object: keyboard
    )
    XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 5), .completed)
    XCTAssertTrue(element("authentication.pinEntry", in: app).exists)
    XCTAssertFalse(element("relationship.loaded", in: app).exists)
  }

  func testAccessibilityPINActionsStackVertically() {
    let app = launch(scenario: "longNames")
    let participant = element("loginOptions.participant.1", in: app)
    XCTAssertTrue(participant.waitForExistence(timeout: 5))
    scrollToHittable(participant, in: app)
    participant.tap()

    let pin = element("authentication.pin", in: app)
    XCTAssertTrue(pin.waitForExistence(timeout: 10))
    scrollToHittable(pin, in: app)
    pin.tap()
    pin.typeText("012")

    dismissKeyboard(in: app)

    let cancel = element("authentication.cancel", in: app)
    let submit = element("authentication.submit", in: app)
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    scrollToHittable(submit, in: app)
    XCTAssertEqual(cancel.frame.midX, submit.frame.midX, accuracy: 1)
    XCTAssertGreaterThan(submit.frame.minY, cancel.frame.maxY)
  }

  func testAuthenticatedRelationshipShowsScoresHistoryThreadAndLocksFromSettings() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("relationship.hero", in: app).exists)
    XCTAssertTrue(element("relationship.scores", in: app).exists)
    XCTAssertFalse(element("relationship.signOut", in: app).exists)

    let outgoingScore = element("relationship.outgoingScore", in: app)
    let incomingScore = element("relationship.incomingScore", in: app)
    XCTAssertEqual(outgoingScore.value as? String, "70점")
    XCTAssertEqual(incomingScore.value as? String, "82점")

    openRelationshipScoreComposer(in: app)
    let preview = element("relationship.scorePreview", in: app)
    XCTAssertTrue(preview.waitForExistence(timeout: 5))
    XCTAssertEqual(preview.value as? String, "현재 70점, 목표 70점, 변화 없음")
    closeCleanSheet(in: app)

    let history = element("relationship.history.101", in: app)
    scrollToHittable(history, in: app)
    XCTAssertTrue(history.exists)
    history.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("relationship.thread.hero", in: app).exists)
    XCTAssertTrue(element("relationship.thread.comment.301", in: app).exists)
    XCTAssertTrue(app.staticTexts["여름"].exists)
    XCTAssertTrue(app.staticTexts["나도 고마워"].exists)

    let commentInput = element("relationship.thread.commentInput", in: app)
    XCTAssertTrue(commentInput.waitForExistence(timeout: 5))
    commentInput.tap()
    commentInput.typeText("E2E relationship reply")
    dismissKeyboard(in: app)
    let createComment = element("relationship.thread.createComment", in: app)
    XCTAssertTrue(waitForEnabled(createComment))
    createComment.tap()
    XCTAssertTrue(
      element("relationship.thread.comment.302", in: app).waitForExistence(timeout: 10)
    )

    app.navigationBars.buttons.element(boundBy: 0).tap()
    lockSessionFromSettings(in: app)

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("relationship.loaded", in: app).exists)
  }

  func testManyHistoryKeepsDashboardCompactAndOpensArchive() {
    let app = launch(scenario: "manyHistory")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    for id in 101...103 {
      let history = element("relationship.history.\(id)", in: app)
      scrollToVisible(history, in: app, maximumSwipes: 20)
      XCTAssertTrue(history.exists)
    }
    XCTAssertFalse(element("relationship.history.104", in: app).exists)

    let openArchive = element("relationship.history.openArchive", in: app)
    scrollToHittable(openArchive, in: app, maximumSwipes: 20)
    openArchive.tap()
    XCTAssertTrue(element("relationship.history.archive", in: app).waitForExistence(timeout: 5))

    for id in 101...104 {
      let archivedHistory = element("relationship.history.\(id)", in: app)
      scrollToVisible(archivedHistory, in: app, maximumSwipes: 20)
      XCTAssertTrue(archivedHistory.exists)
    }
    XCTAssertFalse(element("relationship.history.nextPage", in: app).exists)
  }

  func testHistoryArchiveShowsPagingProgressFailureAndRetry() {
    let app = launch(scenario: "pagedHistoryFailure")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    let openArchive = element("relationship.history.openArchive", in: app)
    scrollToHittable(openArchive, in: app, maximumSwipes: 20)
    openArchive.tap()
    XCTAssertTrue(element("relationship.history.archive", in: app).waitForExistence(timeout: 5))

    let nextPage = element("relationship.history.nextPage", in: app)
    scrollToHittable(nextPage, in: app, maximumSwipes: 20)
    nextPage.tap()
    XCTAssertTrue(app.staticTexts["이전 기록 불러오는 중"].waitForExistence(timeout: 2))
    XCTAssertTrue(element("relationship.history.notice", in: app).waitForExistence(timeout: 10))

    let retry = element("relationship.history.retry", in: app)
    scrollToHittable(retry, in: app, maximumSwipes: 20)
    XCTAssertTrue(waitForEnabled(retry, timeout: 5))
    retry.tap()
    let lastHistory = element("relationship.history.104", in: app)
    scrollToVisible(lastHistory, in: app, maximumSwipes: 20)
    XCTAssertFalse(element("relationship.history.notice", in: app).exists)
    XCTAssertFalse(element("relationship.history.nextPage", in: app).exists)
  }

  func testBackgroundHidesAuthenticatedAccessibilityAndRestoresAfterActivation() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)
    let relationship = element("relationship.loaded", in: app)
    XCTAssertTrue(relationship.waitForExistence(timeout: 5))

    XCUIDevice.shared.press(.home)
    XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
    XCTAssertFalse(relationship.exists)

    app.activate()
    XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
    XCTAssertTrue(relationship.waitForExistence(timeout: 5))
  }

  func testConflictDoesNotRetryAndOffersExplicitReload() {
    let app = launch(scenario: "relationshipConflict")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openRelationshipScoreComposer(in: app)

    let increment = element("relationship.targetScore.increment", in: app)
    XCTAssertTrue(increment.waitForExistence(timeout: 5))
    scrollToHittable(increment, in: app)
    increment.tap()

    let preview = element("relationship.scorePreview", in: app)
    XCTAssertEqual(preview.value as? String, "현재 70점, 목표 71점, 1점 올라감")

    let create = element("relationship.createScoreChange", in: app)
    XCTAssertTrue(create.isEnabled)
    scrollToHittable(create, in: app)
    create.tap()

    let conflict = app.alerts.firstMatch
    XCTAssertTrue(conflict.waitForExistence(timeout: 5))
    let reload = conflict.buttons.firstMatch
    XCTAssertTrue(reload.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForHittable(reload, timeout: 5))
    reload.tap()
    XCTAssertTrue(conflict.waitForNonExistence(timeout: 5))
    XCTAssertTrue(element("relationship.composer", in: app).exists)
  }

  func testUnknownScoreOutcomeBuffersPushUntilExplicitResolution() {
    let app = launch(scenario: "relationshipUnknownOutcomeWithPush")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openRelationshipScoreComposer(in: app)
    let increment = element("relationship.targetScore.increment", in: app)
    XCTAssertTrue(increment.waitForExistence(timeout: 5))
    increment.tap()

    let submit = element("relationship.createScoreChange", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("relationship.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    XCTAssertTrue(element("relationship.composer", in: app).exists)
    XCTAssertFalse(element("relationship.thread.loaded", in: app).exists)
    XCTAssertFalse(submit.isEnabled)
    XCTAssertEqual(
      element("relationship.scorePreview", in: app).value as? String,
      "현재 70점, 목표 71점, 1점 올라감"
    )

    recovery.tap()
    let reload = element("relationship.mutation.reloadLatest", in: app)
    XCTAssertTrue(reload.waitForExistence(timeout: 5))
    reload.tap()

    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()
    let resolveSaved = element("relationship.mutation.resolveSaved", in: app)
    XCTAssertFalse(resolveSaved.exists && resolveSaved.isEnabled)
    let confirmRetry = element("relationship.mutation.confirmRetry", in: app)
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    XCTAssertTrue(element("relationship.composer", in: app).exists)
    XCTAssertFalse(element("relationship.thread.loaded", in: app).exists)
    XCTAssertTrue(waitForEnabled(submit, timeout: 5))
    submit.tap()

    XCTAssertTrue(element("relationship.composer", in: app).waitForNonExistence(timeout: 10))
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 10))
    XCTAssertTrue(element("relationship.thread.comment.301", in: app).exists)
  }

  func testUnknownRelationshipCommentOutcomeKeepsPushBufferedUntilRetrySucceeds() {
    let app = launch(scenario: "relationshipCommentUnknownOutcomeWithPush")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    let history = element("relationship.history.101", in: app)
    scrollToHittable(history, in: app, maximumSwipes: 20)
    history.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))

    let commentInput = element("relationship.thread.commentInput", in: app)
    XCTAssertTrue(commentInput.waitForExistence(timeout: 5))
    commentInput.tap()
    commentInput.typeText("E2E relationship comment unknown draft")
    dismissKeyboard(in: app)

    let submit = element("relationship.thread.createComment", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("relationship.commentMutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    XCTAssertFalse(element("relationship.thread.notFound", in: app).exists)

    recovery.tap()
    let reloadLatest = element("relationship.commentMutation.reloadLatest", in: app)
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()

    let notCommittedMessage = app.staticTexts[
      "제출 전 댓글이 모두 그대로이고 같은 새 댓글은 없어요. 직접 다시 시도할 수 있어요."
    ]
    XCTAssertTrue(notCommittedMessage.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()

    let resolveSaved = element("relationship.commentMutation.resolveSaved", in: app)
    XCTAssertFalse(resolveSaved.exists && resolveSaved.isEnabled)
    let confirmRetry = element("relationship.commentMutation.confirmRetry", in: app)
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    XCTAssertTrue(commentInput.waitForExistence(timeout: 5))
    XCTAssertTrue(
      (commentInput.value as? String)?.contains("E2E relationship comment unknown draft") == true
    )
    XCTAssertFalse(
      element("relationship.thread.notFound", in: app).waitForExistence(timeout: 2)
    )

    XCTAssertTrue(waitForEnabled(submit, timeout: 10))
    submit.tap()

    XCTAssertTrue(element("relationship.thread.notFound", in: app).waitForExistence(timeout: 10))
  }

  func testAuthenticatedDiaryTabShowsWarmPrivateJournalFailureState() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    let diaryTab = app.tabBars.buttons["일기"]
    XCTAssertTrue(diaryTab.exists)
    diaryTab.tap()

    XCTAssertTrue(element("diary.screen", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("diary.failed", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("diary.retry", in: app).exists)
    XCTAssertTrue(element("diary.createEntry.open", in: app).exists)
    XCTAssertFalse(element("diary.signOut", in: app).exists)
  }

  func testLongScoreReasonRemainsExpandedWhenKeyboardAppears() {
    let app = launch(scenario: "longScoreReason")
    enterPIN("0123", participantSlot: 1, in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    let historyReason = element("relationship.history.reason.701", in: app)
    scrollToVisible(historyReason, in: app, maximumSwipes: 20)
    let historyReasonHeight = historyReason.frame.height

    let history = element("relationship.history.701", in: app)
    scrollToHittable(history, in: app, maximumSwipes: 20)
    history.tap()

    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))
    let detailReason = element("relationship.thread.reason.701", in: app)
    XCTAssertTrue(detailReason.waitForExistence(timeout: 5))
    XCTAssertTrue(detailReason.label.contains("여섯 번째 줄까지 키보드가 떠도 보여야 해요."))
    XCTAssertGreaterThan(detailReason.frame.height, historyReasonHeight + 1)
    let expandedReasonHeight = detailReason.frame.height

    let commentInput = element("relationship.thread.commentInput", in: app)
    scrollToHittable(commentInput, in: app, maximumSwipes: 20)
    commentInput.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))

    XCTAssertGreaterThan(detailReason.frame.height, historyReasonHeight + 1)
    XCTAssertEqual(detailReason.frame.height, expandedReasonHeight, accuracy: 1)
  }

  func testAuthenticatedAdaptiveContentRemainsNavigableAtAccessibilityTextSize() {
    executionTimeAllowance = 600
    let app = launch(scenario: "adaptiveContent")
    enterPIN("0123", participantSlot: 1, in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    openRelationshipScoreComposer(in: app)
    let preview = element("relationship.scorePreview", in: app)
    scrollToVisible(preview, in: app, maximumSwipes: 20)
    assertContainedHorizontally(preview, in: app)
    closeCleanSheet(in: app)

    let history = element("relationship.history.401", in: app)
    scrollToHittable(history, in: app, maximumSwipes: 20)
    history.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))
    let longReason = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@",
        "작은 화면과 큰 글자에서도 전체 내용을 천천히 읽을 수 있어야 해요."
      )
    ).firstMatch
    XCTAssertTrue(longReason.waitForExistence(timeout: 5))
    scrollToVisible(longReason, in: app, maximumSwipes: 20, direction: .down)
    assertContainedHorizontally(longReason, in: app)

    let relationshipComment = element("relationship.thread.comment.402", in: app)
    scrollToVisible(relationshipComment, in: app, maximumSwipes: 20)
    assertContainedHorizontally(relationshipComment, in: app)
    let relationshipCommentText = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@",
        "자연스럽게 여러 줄로 보여야 해요."
      )
    ).firstMatch
    XCTAssertTrue(relationshipCommentText.waitForExistence(timeout: 5))

    app.navigationBars.buttons.element(boundBy: 0).tap()
    openDiaryTab(in: app)

    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    let entry = element("diary.entry.501", in: app)
    scrollToVisible(entry, in: app, maximumSwipes: 20)
    assertContainedHorizontally(entry, in: app)
    let conversation = element("diary.entry.501.conversation", in: app)
    scrollToHittable(conversation, in: app, maximumSwipes: 20)
    conversation.tap()

    XCTAssertTrue(element("diary.detail.loaded", in: app).waitForExistence(timeout: 5))
    let diaryContent = app.staticTexts.matching(
      NSPredicate(
        format: "label CONTAINS %@",
        "상세 화면에서 끝까지 읽을 수 있어야 합니다."
      )
    ).firstMatch
    scrollToVisible(diaryContent, in: app, maximumSwipes: 20, direction: .down)
    assertContainedHorizontally(diaryContent, in: app)
    let partnerComment = element("diary.comment.601", in: app)
    scrollToVisible(partnerComment, in: app, maximumSwipes: 20)
    assertContainedHorizontally(partnerComment, in: app)
    let partnerCommentText = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "본문이 서로 겹치지 않아야 해요.")
    ).firstMatch
    XCTAssertTrue(partnerCommentText.waitForExistence(timeout: 5))
    let ownComment = element("diary.comment.602", in: app)
    scrollToVisible(ownComment, in: app, maximumSwipes: 20)
    assertContainedHorizontally(ownComment, in: app)
    let ownCommentText = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "관리 버튼을 누를 수 있어야 해요.")
    ).firstMatch
    XCTAssertTrue(ownCommentText.waitForExistence(timeout: 5))

    let commentInput = element("diary.comment.input", in: app)
    XCTAssertTrue(commentInput.waitForExistence(timeout: 5))
    assertContainedHorizontally(commentInput, in: app)
    let createComment = element("diary.comment.create", in: app)
    XCTAssertTrue(createComment.exists)
    assertContainedHorizontally(createComment, in: app)
    commentInput.tap()
    dismissKeyboard(in: app)
  }

  func testSlotTwoReversesDirectionalScoresAndDiaryOwnership() {
    let app = launch(scenario: "adaptiveContent")
    enterPIN("0123", participantSlot: 2, in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertEqual(element("relationship.outgoingScore", in: app).value as? String, "82점")
    XCTAssertEqual(element("relationship.incomingScore", in: app).value as? String, "70점")

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    scrollToTop(in: app)
    XCTAssertFalse(element("diary.entry.edit", in: app).exists)
    XCTAssertFalse(element("diary.entry.delete", in: app).exists)

    let ownCommentMenu = element("diary.comment.601.menu", in: app)
    scrollToHittable(ownCommentMenu, in: app, maximumSwipes: 20)
    XCTAssertTrue(ownCommentMenu.exists)
    XCTAssertFalse(element("diary.comment.602.menu", in: app).exists)
  }

  func testMediaRichShowsPreloadedUploadAndAdaptiveGalleriesWithViewerRoundTrips() {
    executionTimeAllowance = 300
    let app = launch(scenario: "mediaRich")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openRelationshipScoreComposer(in: app)
    let preloadedUpload = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "media.upload.")
    ).firstMatch
    XCTAssertTrue(preloadedUpload.waitForExistence(timeout: 10))
    scrollToVisible(preloadedUpload, in: app, maximumSwipes: 20)
    XCTAssertTrue(
      app.staticTexts["portrait-selected.jpg"].waitForExistence(timeout: 10)
    )

    let increment = element("relationship.targetScore.increment", in: app)
    scrollToHittable(
      increment,
      in: app,
      maximumSwipes: 20,
      direction: .down
    )
    increment.tap()
    let submitScore = element("relationship.createScoreChange", in: app)
    XCTAssertTrue(waitForEnabled(submitScore, timeout: 10))
    submitScore.tap()
    XCTAssertTrue(element("relationship.composer", in: app).waitForNonExistence(timeout: 10))

    let mediaHistory = element("relationship.history.801", in: app)
    scrollToHittable(mediaHistory, in: app, maximumSwipes: 20)
    mediaHistory.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))
    let relationshipComment = element("relationship.thread.comment.802", in: app)
    scrollToVisible(relationshipComment, in: app, maximumSwipes: 20)
    assertSquareMediaTilesAndViewerRoundTrips(
      Self.relationshipMediaFixtures,
      within: relationshipComment,
      in: app
    )
    let relationshipVideoComment = element("relationship.thread.comment.803", in: app)
    scrollToVisible(relationshipVideoComment, in: app, maximumSwipes: 20)
    assertVideoViewerRoundTrips(
      attachmentID: "10000000-0000-0000-0000-000000000005",
      fileName: "tiny-memory.mp4",
      within: relationshipVideoComment,
      in: app
    )

    app.navigationBars.buttons.element(boundBy: 0).tap()
    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 551, in: app)
    assertSquareMediaTilesAndViewerRoundTrips(
      Self.diaryMediaFixtures,
      within: app,
      in: app
    )
  }

  func testCorruptVideoCanBeDiscardedDownloadedAgainAndPlayed() {
    let app = launch(scenario: "mediaCorruptVideoThenRecovery")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    let mediaHistory = element("relationship.history.801", in: app)
    scrollToHittable(mediaHistory, in: app, maximumSwipes: 20)
    mediaHistory.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))

    let videoComment = element("relationship.thread.comment.803", in: app)
    scrollToVisible(videoComment, in: app, maximumSwipes: 20)
    let preview = videoComment.descendants(matching: .button).matching(
      NSPredicate(format: "label CONTAINS %@", "tiny-memory.mp4")
    ).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 10))
    scrollToHittable(preview, in: app, maximumSwipes: 20)
    preview.tap()

    let viewer = element("media.videoViewer", in: app)
    XCTAssertTrue(viewer.waitForExistence(timeout: 10))
    let failure = element("media.videoViewer.failure", in: app)
    if !failure.waitForExistence(timeout: 2) {
      let playPause = element("media.videoViewer.playPause", in: app)
      XCTAssertTrue(playPause.waitForExistence(timeout: 5))
      playPause.tap()
    }
    XCTAssertTrue(failure.waitForExistence(timeout: 10))
    XCTAssertTrue(element("media.videoViewer.close", in: app).exists)

    let retry = element("media.videoViewer.retry", in: app)
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    retry.tap()

    let recoveredPlayPause = element("media.videoViewer.playPause", in: app)
    XCTAssertTrue(recoveredPlayPause.waitForExistence(timeout: 10))
    let progress = element("media.videoViewer.progress", in: app)
    XCTAssertTrue(progress.waitForExistence(timeout: 5))
    XCTAssertEqual(progress.label, "동영상 재생 진행")
    XCTAssertTrue(waitForSemanticPlaybackDurationReady(progress, timeout: 5))
    let initialValue = semanticPlaybackValue(of: progress)
    XCTAssertNotNil(initialValue)

    recoveredPlayPause.tap()
    XCTAssertTrue(waitForLabel(recoveredPlayPause, equalTo: "동영상 일시 정지"))
    XCTAssertTrue(
      waitForSemanticPlaybackValueChange(
        progress,
        from: initialValue ?? "",
        timeout: 5
      )
    )

    let close = element("media.videoViewer.close", in: app)
    XCTAssertTrue(close.waitForExistence(timeout: 5))
    close.tap()
    XCTAssertTrue(viewer.waitForNonExistence(timeout: 5))
  }

  func testEmptyDiaryCreatesFirstEntry() {
    let app = launch(scenario: "emptyContent")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    let emptyCreate = element("diary.empty.create", in: app)
    XCTAssertTrue(emptyCreate.waitForExistence(timeout: 5))
    emptyCreate.tap()

    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()
    content.typeText("E2E first diary entry")
    dismissKeyboard(in: app)

    let submit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()
    XCTAssertTrue(element("diary.entry.901", in: app).waitForExistence(timeout: 10))
    XCTAssertFalse(element("diary.empty", in: app).exists)
  }

  func testDiaryCRUDUpdatesEntryCreatesEditsDeletesCommentAndDeletesEntry() {
    executionTimeAllowance = 300
    let app = launch(scenario: "diaryCRUD")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()
    let entryContent = element("diary.entry.content", in: app)
    XCTAssertTrue(entryContent.waitForExistence(timeout: 5))
    entryContent.tap()
    entryContent.typeText(" E2E edited")
    dismissKeyboard(in: app)
    let submitEntry = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submitEntry))
    submitEntry.tap()
    XCTAssertTrue(entryContent.waitForNonExistence(timeout: 10))

    let commentInput = element("diary.comment.input", in: app)
    XCTAssertTrue(commentInput.waitForExistence(timeout: 5))
    commentInput.tap()
    commentInput.typeText("E2E comment")
    dismissKeyboard(in: app)
    let createComment = element("diary.comment.create", in: app)
    XCTAssertTrue(waitForEnabled(createComment))
    createComment.tap()

    let createdComment = element("diary.comment.903", in: app)
    XCTAssertTrue(createdComment.waitForExistence(timeout: 10))
    let createdCommentMenu = element("diary.comment.903.menu", in: app)
    scrollToHittable(createdCommentMenu, in: app, maximumSwipes: 20)
    createdCommentMenu.tap()
    let editCommentAction = app.buttons["수정"]
    XCTAssertTrue(editCommentAction.waitForExistence(timeout: 5))
    editCommentAction.tap()

    let commentEditInput = element("diary.comment.edit.input", in: app)
    XCTAssertTrue(commentEditInput.waitForExistence(timeout: 5))
    commentEditInput.typeText(" E2E edited")
    dismissKeyboard(in: app)
    let submitCommentEdit = element("diary.comment.edit.submit", in: app)
    XCTAssertTrue(waitForEnabled(submitCommentEdit))
    submitCommentEdit.tap()
    XCTAssertTrue(commentEditInput.waitForNonExistence(timeout: 10))
    XCTAssertTrue(createdComment.exists)

    scrollToHittable(createdCommentMenu, in: app, maximumSwipes: 20)
    createdCommentMenu.tap()
    let deleteCommentAction = app.buttons["삭제"]
    XCTAssertTrue(deleteCommentAction.waitForExistence(timeout: 5))
    deleteCommentAction.tap()
    let confirmCommentDeletion = app.buttons["댓글 삭제"]
    XCTAssertTrue(confirmCommentDeletion.waitForExistence(timeout: 5))
    confirmCommentDeletion.tap()
    XCTAssertTrue(createdComment.waitForNonExistence(timeout: 10))

    scrollToTop(in: app)
    let deleteEntry = element("diary.entry.delete", in: app)
    XCTAssertTrue(deleteEntry.waitForExistence(timeout: 5))
    scrollToHittable(deleteEntry, in: app, maximumSwipes: 20, direction: .down)
    deleteEntry.tap()
    let confirmEntryDeletion = app.buttons.matching(
      NSPredicate(
        format: "label == %@ AND identifier != %@",
        "일기 삭제",
        "diary.entry.delete"
      )
    ).firstMatch
    XCTAssertTrue(confirmEntryDeletion.waitForExistence(timeout: 5))
    confirmEntryDeletion.tap()
    XCTAssertTrue(element("diary.detail.loaded", in: app).waitForNonExistence(timeout: 10))
    XCTAssertTrue(element("diary.empty", in: app).waitForExistence(timeout: 10))
  }

  func testDiaryConflictReloadsDetailAndPreservesEditorDraft() {
    let app = launch(scenario: "diaryConflict")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()
    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()
    content.typeText(" E2E conflict attempt")
    dismissKeyboard(in: app)
    let submit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let conflict = app.alerts.firstMatch
    XCTAssertTrue(conflict.waitForExistence(timeout: 5))
    let reload = conflict.buttons.firstMatch
    XCTAssertTrue(reload.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForHittable(reload, timeout: 5))
    reload.tap()
    XCTAssertTrue(conflict.waitForNonExistence(timeout: 5))
    XCTAssertTrue(content.waitForExistence(timeout: 10))
    XCTAssertTrue((content.value as? String)?.contains("E2E conflict attempt") == true)
    XCTAssertTrue(waitForEnabled(submit, timeout: 10))
  }

  func testUnknownDiaryOutcomePreservesDraftUntilExplicitRetry() {
    let app = launch(scenario: "diaryUnknownOutcome")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    let openComposer = element("diary.createEntry.open", in: app)
    XCTAssertTrue(openComposer.waitForExistence(timeout: 5))
    openComposer.tap()

    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()
    content.typeText("E2E unknown outcome draft")
    dismissKeyboard(in: app)

    let submit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("diary.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    XCTAssertTrue((content.value as? String)?.contains("E2E unknown outcome draft") == true)
    XCTAssertFalse(submit.isEnabled)

    recovery.tap()
    let reload = element("diary.mutation.reloadLatest", in: app)
    XCTAssertTrue(reload.waitForExistence(timeout: 5))
    reload.tap()
    XCTAssertTrue(content.waitForNonExistence(timeout: 10))

    XCTAssertTrue(openComposer.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForEnabled(openComposer, timeout: 10))
    openComposer.tap()
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    XCTAssertTrue((content.value as? String)?.contains("E2E unknown outcome draft") == true)
    XCTAssertTrue(recovery.waitForExistence(timeout: 5))

    recovery.tap()
    let confirmRetry = element("diary.mutation.confirmRetry", in: app)
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    XCTAssertTrue(waitForEnabled(submit, timeout: 10))
    submit.tap()
    XCTAssertTrue(element("diary.entry.901", in: app).waitForExistence(timeout: 10))
  }

  func testUnknownDiaryEditorOutcomesBlockDismissalUntilExplicitRetry() {
    let app = launch(scenario: "diaryEditorUnknownOutcome")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()

    let entryContent = element("diary.entry.content", in: app)
    XCTAssertTrue(entryContent.waitForExistence(timeout: 5))
    entryContent.tap()
    entryContent.typeText(" E2E entry unknown draft")
    dismissKeyboard(in: app)

    let entrySubmit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(entrySubmit))
    entrySubmit.tap()

    let recovery = element("diary.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    let entryCancel = app.navigationBars["일기 수정"].buttons["취소"]
    XCTAssertTrue(entryCancel.waitForExistence(timeout: 5))
    XCTAssertFalse(entryCancel.isEnabled)
    XCTAssertFalse(entryContent.isEnabled)
    XCTAssertTrue((entryContent.value as? String)?.contains("E2E entry unknown draft") == true)

    recovery.tap()
    let reloadLatest = element("diary.mutation.reloadLatest", in: app)
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()
    XCTAssertTrue(entryContent.waitForExistence(timeout: 10))
    XCTAssertTrue((entryContent.value as? String)?.contains("E2E entry unknown draft") == true)
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()
    let confirmRetry = element("diary.mutation.confirmRetry", in: app)
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    XCTAssertTrue(waitForEnabled(entryContent, timeout: 5))
    XCTAssertTrue(waitForEnabled(entrySubmit, timeout: 10))
    entrySubmit.tap()
    XCTAssertTrue(entryContent.waitForNonExistence(timeout: 10))

    let commentMenu = element("diary.comment.602.menu", in: app)
    scrollToHittable(commentMenu, in: app, maximumSwipes: 20)
    commentMenu.tap()
    let editCommentAction = app.buttons["수정"]
    XCTAssertTrue(editCommentAction.waitForExistence(timeout: 5))
    editCommentAction.tap()

    let commentContent = element("diary.comment.edit.input", in: app)
    XCTAssertTrue(commentContent.waitForExistence(timeout: 5))
    commentContent.tap()
    commentContent.typeText(" E2E comment unknown draft")
    dismissKeyboard(in: app)

    let commentSubmit = element("diary.comment.edit.submit", in: app)
    XCTAssertTrue(waitForEnabled(commentSubmit))
    commentSubmit.tap()

    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    let commentCancel = app.navigationBars["댓글 수정"].buttons["취소"]
    XCTAssertTrue(commentCancel.waitForExistence(timeout: 5))
    XCTAssertFalse(commentCancel.isEnabled)
    XCTAssertFalse(commentContent.isEnabled)
    XCTAssertTrue(
      (commentContent.value as? String)?.contains("E2E comment unknown draft") == true
    )

    recovery.tap()
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()
    XCTAssertTrue(commentContent.waitForExistence(timeout: 10))
    XCTAssertTrue(
      (commentContent.value as? String)?.contains("E2E comment unknown draft") == true
    )
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    XCTAssertTrue(waitForEnabled(commentContent, timeout: 5))
    XCTAssertTrue(waitForEnabled(commentSubmit, timeout: 10))
    commentSubmit.tap()
    XCTAssertTrue(commentContent.waitForNonExistence(timeout: 10))
    XCTAssertTrue(element("diary.comment.602", in: app).exists)
  }

  func testInconclusiveDiaryEditorOutcomeCanBeAbandonedWithoutRetransmission() {
    let app = launch(scenario: "diaryEditorInconclusiveOutcome")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()

    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()
    content.typeText(" E2E inconclusive local draft")
    dismissKeyboard(in: app)

    let submit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("diary.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    XCTAssertFalse(content.isEnabled)
    recovery.tap()
    let reloadLatest = element("diary.mutation.reloadLatest", in: app)
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()

    XCTAssertTrue(content.waitForExistence(timeout: 10))
    XCTAssertFalse(content.isEnabled)
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()

    let resolveSaved = element("diary.mutation.resolveSaved", in: app)
    let confirmRetry = element("diary.mutation.confirmRetry", in: app)
    let abandon = element("diary.mutation.abandonInconclusive", in: app)
    XCTAssertTrue(resolveSaved.waitForExistence(timeout: 5))
    XCTAssertFalse(resolveSaved.isEnabled)
    XCTAssertFalse(confirmRetry.isEnabled)
    XCTAssertTrue(waitForEnabled(abandon, timeout: 5))
    abandon.tap()

    let confirmAbandon = app.buttons["재전송 없이 초안 정리"]
    XCTAssertTrue(confirmAbandon.waitForExistence(timeout: 5))
    confirmAbandon.tap()

    XCTAssertTrue(content.waitForNonExistence(timeout: 10))
    XCTAssertTrue(
      app.staticTexts["다른 기기에서 먼저 저장된 최신 일기"].waitForExistence(timeout: 10)
    )
    XCTAssertTrue(waitForEnabled(editEntry, timeout: 5))
  }

  func testUnknownDiaryRetryKeepsBufferedPushUntilDraftIsResubmitted() {
    let app = launch(scenario: "diaryEditorUnknownOutcomeWithPush")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 501, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()

    let content = element("diary.entry.content", in: app)
    XCTAssertTrue(content.waitForExistence(timeout: 5))
    content.tap()
    content.typeText(" E2E buffered push draft")
    dismissKeyboard(in: app)

    let submit = element("diary.entry.submit", in: app)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("diary.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    recovery.tap()
    let reloadLatest = element("diary.mutation.reloadLatest", in: app)
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()

    XCTAssertTrue(content.waitForExistence(timeout: 10))
    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()
    let confirmRetry = element("diary.mutation.confirmRetry", in: app)
    XCTAssertTrue(confirmRetry.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 10))
    confirmRetry.tap()

    // The pending notification targets another entry. Manual retry must keep this draft mounted.
    XCTAssertTrue(content.exists)
    XCTAssertTrue(waitForEnabled(submit, timeout: 10))
    submit.tap()

    XCTAssertTrue(content.waitForNonExistence(timeout: 10))
    XCTAssertTrue(element("diary.detail.notFound", in: app).waitForExistence(timeout: 10))
  }

  func testMediaOnlyDiaryUnknownOutcomeComparesLatestAttachmentsBeforeRetry() {
    let app = launch(scenario: "diaryMediaEditorUnknownOutcome")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    openDiaryTab(in: app)
    XCTAssertTrue(element("diary.loaded", in: app).waitForExistence(timeout: 5))
    openDiaryDetail(entryID: 551, in: app)

    let editEntry = element("diary.entry.edit", in: app)
    scrollToHittable(editEntry, in: app, maximumSwipes: 20, direction: .down)
    editEntry.tap()

    let removePortrait = app.buttons["portrait-flower.jpg 첨부에서 제거"]
    XCTAssertTrue(removePortrait.waitForExistence(timeout: 10))
    scrollToHittable(removePortrait, in: app, maximumSwipes: 20)
    removePortrait.tap()

    let submit = element("diary.entry.submit", in: app)
    scrollToHittable(submit, in: app, maximumSwipes: 20)
    XCTAssertTrue(waitForEnabled(submit))
    submit.tap()

    let recovery = element("diary.mutation.openRecovery", in: app)
    XCTAssertTrue(recovery.waitForExistence(timeout: 10))
    recovery.tap()
    let reloadLatest = element("diary.mutation.reloadLatest", in: app)
    XCTAssertTrue(reloadLatest.waitForExistence(timeout: 5))
    reloadLatest.tap()

    let serverAttachments = element("diary.reconciliation.attachments", in: app)
    XCTAssertTrue(serverAttachments.waitForExistence(timeout: 10))
    scrollToVisible(serverAttachments, in: app, maximumSwipes: 20)
    XCTAssertTrue(app.staticTexts["서버에서 다시 읽은 첨부"].exists)
    XCTAssertTrue(app.staticTexts["4개"].exists)

    XCTAssertTrue(waitForEnabled(recovery, timeout: 10))
    recovery.tap()
    let resolveSaved = element("diary.mutation.resolveSaved", in: app)
    let confirmRetry = element("diary.mutation.confirmRetry", in: app)
    XCTAssertTrue(resolveSaved.waitForExistence(timeout: 5))
    XCTAssertFalse(resolveSaved.isEnabled)
    XCTAssertTrue(waitForEnabled(confirmRetry, timeout: 5))
    confirmRetry.tap()

    XCTAssertTrue(waitForEnabled(submit, timeout: 10))
    submit.tap()
    XCTAssertTrue(element("diary.entry.content", in: app).waitForNonExistence(timeout: 10))
  }

  private func launch(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = [Self.scenarioArgument, scenario]
    app.launch()

    XCTAssertTrue(element("loginOptions.screen", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts[Self.header].waitForExistence(timeout: 5))
    return app
  }

  private func enterPIN(
    _ value: String,
    participantSlot: Int,
    in app: XCUIApplication
  ) {
    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 10))
    let participant = element("loginOptions.participant.\(participantSlot)", in: app)
    XCTAssertTrue(participant.waitForExistence(timeout: 10))
    scrollToHittable(participant, in: app, maximumSwipes: 20)
    participant.tap()
    submitPIN(value, in: app)
  }

  private func openRelationshipScoreComposer(in app: XCUIApplication) {
    let openComposer = element("relationship.editScore.open", in: app)
    XCTAssertTrue(openComposer.waitForExistence(timeout: 5))
    scrollToHittable(openComposer, in: app, maximumSwipes: 20)
    openComposer.tap()
    XCTAssertTrue(element("relationship.composer", in: app).waitForExistence(timeout: 5))
  }

  private func openDiaryTab(in app: XCUIApplication) {
    let diaryTab = app.tabBars.buttons["일기"]
    XCTAssertTrue(diaryTab.waitForExistence(timeout: 5))
    diaryTab.tap()
    XCTAssertTrue(element("diary.screen", in: app).waitForExistence(timeout: 5))
  }

  private func openDiaryDetail(entryID: Int64, in app: XCUIApplication) {
    let conversation = element("diary.entry.\(entryID).conversation", in: app)
    scrollToHittable(conversation, in: app, maximumSwipes: 20)
    conversation.tap()
    XCTAssertTrue(element("diary.detail.loaded", in: app).waitForExistence(timeout: 5))
  }

  private func lockSessionFromSettings(in app: XCUIApplication) {
    let settingsTab = app.tabBars.buttons["설정"]
    XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
    settingsTab.tap()
    XCTAssertTrue(element("settings.screen", in: app).waitForExistence(timeout: 5))

    let lock = element("settings.lock", in: app)
    XCTAssertTrue(lock.waitForExistence(timeout: 5))
    lock.tap()
    let confirm = element("settings.lock.confirm", in: app)
    XCTAssertTrue(confirm.waitForExistence(timeout: 5))
    confirm.tap()
  }

  private func closeCleanSheet(in app: XCUIApplication) {
    let cancel = app.navigationBars.buttons.firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    cancel.tap()
    XCTAssertTrue(element("relationship.composer", in: app).waitForNonExistence(timeout: 5))
  }

  private func submitPIN(_ value: String, in app: XCUIApplication) {
    let pin = element("authentication.pin", in: app)
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    scrollToHittable(pin, in: app, maximumSwipes: 20)
    pin.tap()
    pin.typeText(value)

    if app.keyboards.firstMatch.exists {
      let keyboard = app.keyboards.firstMatch
      let dismissKeyboard = element("keyboard.dismiss", in: app)
      if dismissKeyboard.waitForExistence(timeout: 2) {
        XCTAssertTrue(waitForHittable(dismissKeyboard, timeout: 5))
        dismissKeyboard.tap()
      }
      XCTAssertTrue(keyboard.waitForNonExistence(timeout: 10))
    }

    let submit = element("authentication.submit", in: app)
    if !submit.exists {
      app.swipeUp()
    }
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForEnabled(submit))
    scrollToHittable(submit, in: app, maximumSwipes: 20)
    submit.tap()
  }

  private func waitForEnabled(_ target: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "enabled == true"),
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func waitForHittable(_ target: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == true"),
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func remainsHittable(
    _ target: XCUIElement,
    for duration: TimeInterval = 0.5
  ) -> Bool {
    guard target.isHittable else { return false }

    let losesHittability = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "hittable == false"),
      object: target
    )
    losesHittability.isInverted = true
    return XCTWaiter.wait(for: [losesHittability], timeout: duration) == .completed
  }

  private func scrollToHittable(
    _ target: XCUIElement,
    in app: XCUIApplication,
    maximumSwipes: Int = 8,
    direction: ScrollDirection = .up,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for attempt in 0...maximumSwipes {
      if remainsHittable(target) { return }
      guard attempt < maximumSwipes else { break }

      switch direction {
      case .up:
        app.swipeUp()
      case .down:
        app.swipeDown()
      }
    }
    XCTFail(
      "Element did not become stably hittable after \(maximumSwipes) swipes",
      file: file,
      line: line
    )
  }

  private func scrollToTop(in app: XCUIApplication, maximumSwipes: Int = 12) {
    for _ in 0..<maximumSwipes {
      app.swipeDown()
    }
  }

  private func dismissKeyboard(in app: XCUIApplication) {
    let keyboard = app.keyboards.firstMatch
    XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
    let dismissKeyboard = element("keyboard.dismiss", in: app)
    XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForHittable(dismissKeyboard, timeout: 5))
    dismissKeyboard.tap()
    XCTAssertTrue(keyboard.waitForNonExistence(timeout: 10))
    XCTAssertFalse(element("keyboard.dismiss", in: app).exists)
  }

  private func scrollToVisible(
    _ target: XCUIElement,
    in app: XCUIApplication,
    maximumSwipes: Int = 8,
    direction: ScrollDirection = .up
  ) {
    for _ in 0..<maximumSwipes {
      if target.exists, target.frame.intersects(app.frame) { break }
      switch direction {
      case .up:
        app.swipeUp()
      case .down:
        app.swipeDown()
      }
    }
    XCTAssertTrue(target.exists)
    XCTAssertTrue(target.frame.intersects(app.frame))
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func assertSquareMediaTilesAndViewerRoundTrips(
    _ fixtures: [MediaFixture],
    within container: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    for fixture in fixtures {
      let inline = container.descendants(matching: .any).matching(
        identifier: "media.inline.\(fixture.id)"
      ).firstMatch
      XCTAssertTrue(inline.waitForExistence(timeout: 10), file: file, line: line)
      scrollToVisible(inline, in: app, maximumSwipes: 20)

      let preview = container.descendants(matching: .button).matching(
        NSPredicate(format: "label CONTAINS %@", fixture.fileName)
      ).firstMatch
      XCTAssertTrue(preview.waitForExistence(timeout: 10), file: file, line: line)
      scrollToHittable(preview, in: app, maximumSwipes: 20)
      XCTAssertTrue(waitForEnabled(preview, timeout: 10), file: file, line: line)
      XCTAssertEqual(
        preview.frame.width,
        preview.frame.height,
        accuracy: 3,
        file: file,
        line: line
      )

      preview.tap()
      let viewer = element("media.viewer", in: app)
      XCTAssertTrue(viewer.waitForExistence(timeout: 10), file: file, line: line)
      XCTAssertTrue(
        waitForAspectRatio(
          viewer,
          expected: fixture.expectedViewerAspectRatio,
          timeout: 5
        ),
        "\(fixture.fileName) viewer must preserve its source aspect ratio",
        file: file,
        line: line
      )
      assertContainedHorizontally(viewer, in: app, file: file, line: line)
      XCTAssertLessThanOrEqual(viewer.frame.height, app.frame.height + 1, file: file, line: line)
      let close = element("media.viewer.close", in: app)
      XCTAssertTrue(close.waitForExistence(timeout: 5), file: file, line: line)
      close.tap()
      XCTAssertTrue(viewer.waitForNonExistence(timeout: 5), file: file, line: line)
    }
  }

  private func assertVideoViewerRoundTrips(
    attachmentID: String,
    fileName: String,
    within container: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let inline = container.descendants(matching: .any).matching(
      identifier: "media.inline.\(attachmentID)"
    ).firstMatch
    scrollToVisible(inline, in: app, maximumSwipes: 20)

    let preview = container.descendants(matching: .button).matching(
      NSPredicate(format: "label CONTAINS %@", fileName)
    ).firstMatch
    XCTAssertTrue(preview.waitForExistence(timeout: 10), file: file, line: line)
    scrollToHittable(preview, in: app, maximumSwipes: 20)
    XCTAssertEqual(
      preview.frame.width / preview.frame.height,
      16 / 9,
      accuracy: 0.08,
      file: file,
      line: line
    )

    for roundTrip in 1...2 {
      preview.tap()
      let viewer = element("media.videoViewer", in: app)
      XCTAssertTrue(
        viewer.waitForExistence(timeout: 10),
        "The private video viewer must appear on round trip \(roundTrip)",
        file: file,
        line: line
      )
      let player = element("media.videoViewer.player", in: app)
      XCTAssertTrue(player.waitForExistence(timeout: 5), file: file, line: line)
      let playPause = element("media.videoViewer.playPause", in: app)
      XCTAssertTrue(playPause.waitForExistence(timeout: 5), file: file, line: line)
      let progress = element("media.videoViewer.progress", in: app)
      XCTAssertTrue(progress.waitForExistence(timeout: 5), file: file, line: line)
      let close = element("media.videoViewer.close", in: app)
      XCTAssertTrue(close.waitForExistence(timeout: 5), file: file, line: line)

      XCTAssertEqual(progress.label, "동영상 재생 진행", file: file, line: line)
      XCTAssertTrue(
        waitForSemanticPlaybackDurationReady(progress, timeout: 5),
        file: file,
        line: line
      )
      let initialValue = semanticPlaybackValue(of: progress)
      XCTAssertNotNil(initialValue, file: file, line: line)
      playPause.tap()
      XCTAssertTrue(
        waitForLabel(playPause, equalTo: "동영상 일시 정지"),
        file: file,
        line: line
      )
      XCTAssertTrue(
        waitForSemanticPlaybackValueChange(
          progress,
          from: initialValue ?? "",
          timeout: 5
        ),
        "The fixture video must decode and advance on round trip \(roundTrip)",
        file: file,
        line: line
      )

      if roundTrip == 1 {
        playPause.tap()
        XCTAssertTrue(
          waitForLabel(playPause, equalTo: "동영상 재생"),
          file: file,
          line: line
        )
        let pausedValue = semanticPlaybackValue(of: progress)
        XCTAssertNotNil(pausedValue, file: file, line: line)
        XCTAssertTrue(
          accessibilityValueRemains(
            progress,
            equalTo: pausedValue ?? "",
            duration: 0.6
          ),
          "Progress must stop when the user pauses playback",
          file: file,
          line: line
        )

        playPause.tap()
        XCTAssertTrue(
          waitForLabel(playPause, equalTo: "동영상 일시 정지"),
          file: file,
          line: line
        )
        XCTAssertTrue(
          waitForSemanticPlaybackValueChange(
            progress,
            from: pausedValue ?? "",
            timeout: 5
          ),
          "Progress must resume after the user starts playback again",
          file: file,
          line: line
        )

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5), file: file, line: line)
        XCTAssertFalse(viewer.exists, file: file, line: line)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5), file: file, line: line)
        XCTAssertTrue(viewer.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertTrue(close.waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertEqual(playPause.label, "동영상 재생", file: file, line: line)
        let backgroundPausedValue = semanticPlaybackValue(of: progress)
        XCTAssertNotNil(backgroundPausedValue, file: file, line: line)
        XCTAssertTrue(
          accessibilityValueRemains(
            progress,
            equalTo: backgroundPausedValue ?? "",
            duration: 0.6
          ),
          "Progress must stay stopped after returning from the background",
          file: file,
          line: line
        )

        playPause.tap()
        XCTAssertTrue(
          waitForLabel(playPause, equalTo: "동영상 일시 정지"),
          "Playback must actually resume after returning from the background",
          file: file,
          line: line
        )
        XCTAssertTrue(
          waitForSemanticPlaybackValueChange(
            progress,
            from: backgroundPausedValue ?? "",
            timeout: 5
          ),
          "Progress must advance after background-paused playback resumes",
          file: file,
          line: line
        )

        XCTAssertTrue(
          waitForLabel(playPause, equalTo: "동영상 재생", timeout: 7),
          "The deterministic fixture must reach its natural end",
          file: file,
          line: line
        )
        let completedValue = semanticPlaybackValue(of: progress)
        XCTAssertNotNil(completedValue, file: file, line: line)

        playPause.tap()
        let didRestart = waitForPlaybackRestart(
          progress,
          from: completedValue ?? "",
          timeout: 3
        )
        XCTAssertTrue(
          didRestart,
          "Replay must seek back near zero instead of remaining at the end "
            + "(completed: \(completedValue ?? "missing"), observed: "
            + "\(semanticPlaybackValue(of: progress) ?? "missing"))",
          file: file,
          line: line
        )
        XCTAssertTrue(
          waitForLabel(playPause, equalTo: "동영상 일시 정지"),
          file: file,
          line: line
        )
        let restartedValue = semanticPlaybackValue(of: progress)
        XCTAssertNotNil(restartedValue, file: file, line: line)
        XCTAssertTrue(
          waitForPlaybackAdvanceNearBeginning(
            progress,
            from: restartedValue ?? "",
            before: completedValue ?? "",
            timeout: 5
          ),
          "Replay must continue advancing after it seeks to the beginning",
          file: file,
          line: line
        )
      }

      close.tap()
      XCTAssertTrue(viewer.waitForNonExistence(timeout: 5), file: file, line: line)
      XCTAssertTrue(inline.waitForExistence(timeout: 10), file: file, line: line)
      scrollToHittable(preview, in: app, maximumSwipes: 20)
    }
  }

  private func assertContainedHorizontally(
    _ element: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let tolerance: CGFloat = 1
    XCTAssertGreaterThanOrEqual(
      element.frame.minX,
      app.frame.minX - tolerance,
      file: file,
      line: line
    )
    XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + tolerance, file: file, line: line)
  }

  private func waitForAspectRatio(
    _ target: XCUIElement,
    expected: CGFloat,
    timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement, element.exists else { return false }
        let frame = element.frame
        guard frame.width > 1, frame.height > 1 else { return false }
        return abs((frame.width / frame.height) - expected) <= 0.08
      },
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func waitForLabel(
    _ target: XCUIElement,
    equalTo expectedLabel: String,
    timeout: TimeInterval = 5
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate(format: "label == %@", expectedLabel),
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func semanticPlaybackValue(of target: XCUIElement) -> String? {
    guard target.exists, let value = target.value as? String,
      value.contains("현재"), value.contains("전체"), value.contains("초")
    else {
      return nil
    }
    return value
  }

  private func waitForSemanticPlaybackDurationReady(
    _ target: XCUIElement,
    timeout: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement,
          element.exists,
          let value = element.value as? String
        else {
          return false
        }
        return value.contains("현재") && value.contains("전체") && value.contains("초")
          && !value.contains("확인 중")
      },
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func waitForSemanticPlaybackValueChange(
    _ target: XCUIElement,
    from initialValue: String,
    timeout: TimeInterval
  ) -> Bool {
    guard let initialPosition = playbackPosition(in: initialValue) else { return false }
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement,
          element.exists,
          let value = element.value as? String
        else {
          return false
        }
        return self.playbackPosition(in: value).map { $0 != initialPosition } ?? false
      },
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func playbackPosition(in accessibilityValue: String) -> String? {
    guard let separator = accessibilityValue.range(of: ", 전체") else { return nil }
    return String(accessibilityValue[..<separator.lowerBound])
  }

  private func waitForPlaybackRestart(
    _ target: XCUIElement,
    from completedValue: String,
    timeout: TimeInterval
  ) -> Bool {
    guard let completedSeconds = playbackSeconds(in: completedValue), completedSeconds > 0 else {
      return false
    }
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement,
          element.exists,
          let value = element.value as? String,
          let seconds = self.playbackSeconds(in: value)
        else {
          return false
        }
        return seconds < completedSeconds / 2
      },
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func playbackSeconds(in accessibilityValue: String) -> Double? {
    guard var position = playbackPosition(in: accessibilityValue),
      position.hasPrefix("현재 "), position.hasSuffix("초")
    else {
      return nil
    }
    position.removeFirst("현재 ".count)
    position.removeLast("초".count)
    let components = position.components(separatedBy: "분 ")
    if components.count == 2,
      let minutes = Double(components[0]),
      let seconds = Double(components[1])
    {
      return minutes * 60 + seconds
    }
    return Double(position)
  }

  private func waitForPlaybackAdvanceNearBeginning(
    _ target: XCUIElement,
    from restartedValue: String,
    before completedValue: String,
    timeout: TimeInterval
  ) -> Bool {
    guard let restartedSeconds = playbackSeconds(in: restartedValue),
      let completedSeconds = playbackSeconds(in: completedValue),
      restartedSeconds < completedSeconds / 2
    else {
      return false
    }
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement,
          element.exists,
          let value = element.value as? String,
          let seconds = self.playbackSeconds(in: value)
        else {
          return false
        }
        return seconds > restartedSeconds && seconds < completedSeconds * 0.75
      },
      object: target
    )
    return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
  }

  private func accessibilityValueRemains(
    _ target: XCUIElement,
    equalTo expectedValue: String,
    duration: TimeInterval
  ) -> Bool {
    let expectation = XCTNSPredicateExpectation(
      predicate: NSPredicate { object, _ in
        guard let element = object as? XCUIElement,
          element.exists,
          let value = element.value as? String
        else {
          return true
        }
        return value != expectedValue
      },
      object: target
    )
    expectation.isInverted = true
    return XCTWaiter.wait(for: [expectation], timeout: duration) == .completed
  }

  private struct MediaFixture {
    let id: String
    let fileName: String
    let expectedViewerAspectRatio: CGFloat
  }

  private enum ScrollDirection {
    case up
    case down
  }
}
