import XCTest

final class SmokeTests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Swing Through"].waitForExistence(timeout: 10))
    }
}
