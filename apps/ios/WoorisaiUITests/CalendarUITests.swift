import XCTest

@MainActor
final class CalendarUITests: XCTestCase {
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
    let add = app.buttons["calendar.empty.add"]
    guard add.waitForExistence(timeout: 5) else { return XCTFail("Empty day is not actionable") }
    add.tap()
    assertCreateForm(in: app)
  }

  private func openCalendar() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--login-options-ui-test-scenario", "success"]
    app.launch()
    let participant = app.descendants(matching: .any)["loginOptions.participant.1"]
    XCTAssertTrue(participant.waitForExistence(timeout: 10))
    participant.tap()
    let pin = app.descendants(matching: .any)["authentication.pin"]
    XCTAssertTrue(pin.waitForExistence(timeout: 10))
    pin.tap()
    pin.typeText("0123")
    let tab = app.tabBars.buttons["일정"]
    XCTAssertTrue(tab.waitForExistence(timeout: 10))
    tab.tap()
    XCTAssertTrue(app.staticTexts["calendar.month"].waitForExistence(timeout: 10))
    return app
  }

  private func assertCreateForm(in app: XCUIApplication) {
    XCTAssertTrue(app.textFields["calendar.title"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["calendar.save"].exists)
  }
}
