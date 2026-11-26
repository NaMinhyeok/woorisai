import XCTest

@MainActor
final class CalendarUITests: XCTestCase {
  func testHomeOpensUpcomingEventOnItsDay() {
    let app = launch(scenario: "calendarUX")
    let shortcut = app.buttons["relationship.upcomingEvent"]
    guard shortcut.waitForExistence(timeout: 10) else { return XCTFail("Missing upcoming event shortcut") }
    XCTAssertTrue(shortcut.label.contains("연남동 저녁 약속"))
    shortcut.tap()
    XCTAssertTrue(app.staticTexts["연남동 저녁 약속"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.navigationBars.firstMatch.exists)
    let selected = app.buttons.matching(NSPredicate(format: "selected == true")).allElementsBoundByIndex
    let date = selected.first { ($0.value as? String)?.contains("일정 1개") == true }
    guard let date else { return XCTFail("Selected date should describe its event count") }
    let selectedDate = date.label
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.name = "일정 첫 화면"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    app.buttons["calendar.create"].tap()
    let input = app.textFields["calendar.title"]
    XCTAssertTrue(input.waitForExistence(timeout: 5))
    input.tap()
    input.typeText("E2E same day")
    app.buttons["calendar.save"].tap()
    XCTAssertTrue(app.staticTexts["E2E same day"].waitForExistence(timeout: 10))
    let sameDate = app.buttons.matching(NSPredicate(format: "selected == true AND label == %@", selectedDate)).firstMatch
    XCTAssertTrue((sameDate.value as? String)?.contains("일정 2개") == true)
    app.buttons["calendar.event.700"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["calendar.event.detail"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["calendar.event.edit"].exists)
    app.navigationBars.buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["calendar.day.disclosure"].waitForExistence(timeout: 5))
    app.buttons["calendar.event.700"].tap()
    app.tabBars.buttons["우리 사이"].tap()
    XCTAssertTrue(shortcut.waitForExistence(timeout: 5))
    shortcut.tap()
    XCTAssertTrue(app.buttons["calendar.day.disclosure"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["calendar.event.edit"].exists)
  }

  func testCalendarKeepsOnePanelAcrossDateTapsAndDrag() {
    let app = openCalendar()
    let disclosure = app.buttons["calendar.day.disclosure"]
    XCTAssertFalse(disclosure.exists)
    let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.cell.")).allElementsBoundByIndex
    guard dates.count >= 3 else { return XCTFail("Expected selectable dates") }
    for date in dates.prefix(3) {
      let key = date.identifier
      app.buttons[key].tap()
      XCTAssertTrue(disclosure.exists)
      XCTAssertTrue(app.buttons[key].isSelected)
      XCTAssertTrue(app.tabBars.buttons["일기"].isHittable)
    }
    XCTAssertEqual(disclosure.value as? String, "접힘")
    let origin = disclosure.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
    origin.press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: 0, dy: -120)))
    XCTAssertEqual(disclosure.value as? String, "펼쳐짐")
    disclosure.tap()
    XCTAssertEqual(disclosure.value as? String, "접힘")
  }

  func testCalendarTabOpensMonthAndCreateForm() {
    let app = openCalendar()
    app.buttons["calendar.create"].tap()
    assertCreateForm(in: app)
  }

  func testCalendarSwipesBetweenMonthsAndReturnsToToday() {
    let app = openCalendar()
    let month = app.staticTexts["calendar.month"]
    let initialMonth = month.label
    let y = month.frame.maxY + 94 - app.frame.minY
    let origin = app.coordinate(withNormalizedOffset: .zero)
    let left = origin.withOffset(CGVector(dx: app.frame.width * 0.16, dy: y))
    let right = origin.withOffset(CGVector(dx: app.frame.width * 0.84, dy: y))

    right.press(forDuration: 0.05, thenDragTo: left)
    XCTAssertNotEqual(month.label, initialMonth)
    left.press(forDuration: 0.05, thenDragTo: right)
    XCTAssertEqual(month.label, initialMonth)

    right.press(forDuration: 0.05, thenDragTo: left)
    XCTAssertNotEqual(month.label, initialMonth)
    let today = app.buttons["calendar.today"]
    guard today.exists else { return XCTFail("Missing return-to-today control") }
    today.tap()
    XCTAssertEqual(month.label, initialMonth)
  }

  func testEmptyDayCardOpensCreateForm() {
    let app = openCalendar()
    let date = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "calendar.day.cell.")).firstMatch
    date.tap()
    let add = app.buttons["calendar.empty.add"]
    guard add.waitForExistence(timeout: 5) else { return XCTFail("Empty day is not actionable") }
    add.tap()
    assertCreateForm(in: app)
  }

  private func openCalendar() -> XCUIApplication {
    let app = launch(scenario: "success")
    let tab = app.tabBars.buttons["일정"]
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    XCTAssertTrue(app.staticTexts["calendar.month"].waitForExistence(timeout: 10))
    return app
  }

  private func launch(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--login-options-ui-test-scenario", scenario]
    app.launch()
    let participant = app.descendants(matching: .any)["loginOptions.participant.1"]
    XCTAssertTrue(participant.waitForExistence(timeout: 10))
    participant.tap()
    let pin = app.descendants(matching: .any)["authentication.pin"]
    XCTAssertTrue(pin.waitForExistence(timeout: 10))
    pin.tap()
    pin.typeText("0123")
    return app
  }

  private func assertCreateForm(in app: XCUIApplication) {
    XCTAssertTrue(app.textFields["calendar.title"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["calendar.save"].exists)
  }
}
