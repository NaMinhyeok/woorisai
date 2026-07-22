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

    let reason = element("relationship.reason", in: app)
    XCTAssertTrue(reason.exists)
    scrollToHittable(reason, in: app)
    reason.tap()

    dismissKeyboard(in: app)
    XCTAssertTrue(reason.exists)
  }

  func testDiaryEditorKeyboardHasExplicitDismissAction() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    app.tabBars.buttons["일기"].tap()
    XCTAssertTrue(element("diary.failed", in: app).waitForExistence(timeout: 5))

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
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    scrollToHittable(pin, in: app)
    pin.tap()
    pin.typeText("012")

    let dismissKeyboard = element("keyboard.dismiss", in: app)
    XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
    dismissKeyboard.tap()

    let cancel = element("authentication.cancel", in: app)
    let submit = element("authentication.submit", in: app)
    XCTAssertTrue(cancel.waitForExistence(timeout: 5))
    XCTAssertTrue(submit.waitForExistence(timeout: 5))
    scrollToHittable(submit, in: app)
    XCTAssertEqual(cancel.frame.midX, submit.frame.midX, accuracy: 1)
    XCTAssertGreaterThan(submit.frame.minY, cancel.frame.maxY)
  }

  func testAuthenticatedRelationshipShowsScoresHistoryThreadAndLocalSignOut() {
    let app = launch(scenario: "relationship")
    enterPIN("0123", participantSlot: 1, in: app)

    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("relationship.hero", in: app).exists)
    XCTAssertTrue(element("relationship.scores", in: app).exists)

    let outgoingScore = element("relationship.outgoingScore", in: app)
    let incomingScore = element("relationship.incomingScore", in: app)
    XCTAssertEqual(outgoingScore.value as? String, "70점")
    XCTAssertEqual(incomingScore.value as? String, "82점")

    let preview = element("relationship.scorePreview", in: app)
    XCTAssertTrue(preview.exists)
    XCTAssertEqual(preview.value as? String, "현재 70점, 목표 70점, 변화 없음")

    let history = element("relationship.history.101", in: app)
    scrollToHittable(history, in: app)
    XCTAssertTrue(history.exists)
    history.tap()
    XCTAssertTrue(element("relationship.thread.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertTrue(element("relationship.thread.hero", in: app).exists)
    XCTAssertTrue(element("relationship.thread.comment.301", in: app).exists)
    XCTAssertTrue(app.staticTexts["여름"].exists)
    XCTAssertTrue(app.staticTexts["나도 고마워"].exists)

    app.navigationBars.buttons.element(boundBy: 0).tap()
    let signOut = element("relationship.signOut", in: app)
    XCTAssertTrue(signOut.waitForExistence(timeout: 5))
    signOut.tap()

    XCTAssertTrue(element("loginOptions.loaded", in: app).waitForExistence(timeout: 5))
    XCTAssertFalse(element("relationship.loaded", in: app).exists)
  }

  func testConflictDoesNotRetryAndOffersExplicitReload() {
    let app = launch(scenario: "relationshipConflict")
    enterPIN("0123", participantSlot: 1, in: app)
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))

    let stepper = app.steppers["relationship.targetScore"]
    XCTAssertTrue(stepper.exists)
    let increment = stepper.buttons.element(boundBy: 1)
    XCTAssertTrue(increment.exists)
    scrollToHittable(increment, in: app)
    increment.tap()

    let preview = element("relationship.scorePreview", in: app)
    XCTAssertEqual(preview.value as? String, "현재 70점, 목표 71점, 1점 올라감")

    let create = element("relationship.createScoreChange", in: app)
    XCTAssertTrue(create.isEnabled)
    scrollToHittable(create, in: app)
    create.tap()

    XCTAssertTrue(app.alerts["최신 내용이 필요해요"].waitForExistence(timeout: 5))
    let reload = app.alerts.buttons["최신 내용 불러오기"]
    XCTAssertTrue(reload.exists)
    reload.tap()
    XCTAssertTrue(element("relationship.loaded", in: app).waitForExistence(timeout: 5))
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
    XCTAssertTrue(app.staticTexts["점수로는 다 담지 못한 오늘의 이야기를 함께 남겨요."].exists)
    XCTAssertTrue(element("diary.retry", in: app).exists)
    XCTAssertTrue(element("diary.createEntry.open", in: app).exists)
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
    let preview = element("relationship.scorePreview", in: app)
    scrollToVisible(preview, in: app, maximumSwipes: 20)
    assertContainedHorizontally(preview, in: app)

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
    scrollToVisible(longReason, in: app, maximumSwipes: 20)
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
    let diaryTab = app.tabBars.buttons["일기"]
    XCTAssertTrue(diaryTab.waitForExistence(timeout: 5))
    diaryTab.tap()

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
    XCTAssertTrue(diaryContent.waitForExistence(timeout: 5))
    scrollToVisible(diaryContent, in: app, maximumSwipes: 20)
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
    let participant = element("loginOptions.participant.\(participantSlot)", in: app)
    XCTAssertTrue(participant.waitForExistence(timeout: 5))
    scrollToHittable(participant, in: app, maximumSwipes: 20)
    participant.tap()
    submitPIN(value, in: app)
  }

  private func submitPIN(_ value: String, in app: XCUIApplication) {
    let pin = element("authentication.pin", in: app)
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    scrollToHittable(pin, in: app, maximumSwipes: 20)
    pin.tap()
    pin.typeText(value)

    if app.keyboards.firstMatch.exists {
      let dismissKeyboard = element("keyboard.dismiss", in: app)
      if dismissKeyboard.waitForExistence(timeout: 2) {
        dismissKeyboard.tap()
      }
      XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
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

  private func scrollToHittable(
    _ target: XCUIElement,
    in app: XCUIApplication,
    maximumSwipes: Int = 8
  ) {
    for _ in 0..<maximumSwipes where !target.isHittable {
      app.swipeUp()
    }
    XCTAssertTrue(target.isHittable)
  }

  private func dismissKeyboard(in app: XCUIApplication) {
    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
    let dismissKeyboard = element("keyboard.dismiss", in: app)
    XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 5))
    dismissKeyboard.tap()
    XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
  }

  private func scrollToVisible(
    _ target: XCUIElement,
    in app: XCUIApplication,
    maximumSwipes: Int = 8
  ) {
    for _ in 0..<maximumSwipes where !target.exists || !target.frame.intersects(app.frame) {
      app.swipeUp()
    }
    XCTAssertTrue(target.exists)
    XCTAssertTrue(target.frame.intersects(app.frame))
  }

  private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: identifier).firstMatch
  }

  private func assertContainedHorizontally(
    _ element: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    let tolerance: CGFloat = 1
    XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX - tolerance, file: file, line: line)
    XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX + tolerance, file: file, line: line)
  }
}
