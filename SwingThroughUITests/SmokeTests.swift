import XCTest

final class SmokeTests: XCTestCase {
    func testLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["Swing Through"].waitForExistence(timeout: 10))
    }

    func testAnalyzingScreenExposesCancelAction() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analyzing"
        app.launch()

        XCTAssertTrue(app.buttons["cancelAnalysis"].waitForExistence(timeout: 10))
    }
}
