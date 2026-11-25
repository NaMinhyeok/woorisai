import XCTest

@MainActor
final class CalendarUITests: XCTestCase {
  func testCalendarTabOpensMonthAndCreateForm() {
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
    app.buttons["calendar.create"].tap()
    XCTAssertTrue(app.textFields["calendar.title"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["calendar.save"].exists)
  }
}
