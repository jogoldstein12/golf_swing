// Track B results-experience smoke tests: the lead card leads with the top coaching
// goal, and a low-confidence report leads with the confidence state (never a score).
import XCTest

final class LeadCardTests: XCTestCase {

    /// The scored results screen surfaces the #1 coaching goal as the lead finding —
    /// now via the glance strip + coaching canvas (WS-E), which replaced the lead card
    /// for scored reads.
    func testLeadCardShowsTopGoal() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        // Wait for the scored lead to settle, then assert its content (a direct wait on
        // the text alone can race a slow cold-boot render).
        XCTAssertTrue(app.otherElements["glanceStrip"].waitForExistence(timeout: 20))
        // The demo report's priority-1 goal, carried by the glance strip.
        XCTAssertTrue(app.staticTexts["Shallow the shaft in transition"].exists)
        // The coaching canvas surfaces its single next action.
        XCTAssertTrue(app.buttons["seeFix"].waitForExistence(timeout: 5))
    }

    /// A low-confidence read leads with the confidence explanation and never renders a
    /// precise 0–100 score.
    func testLowConfidenceLeadsWithConfidenceState() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysisLowConf"
        app.launch()

        XCTAssertTrue(
            app.staticTexts["We couldn't measure this one cleanly."].waitForExistence(timeout: 15)
        )
        // ScoreBlock shows "Not scored" instead of a number under insufficiency.
        XCTAssertTrue(app.staticTexts["Not scored"].exists)
        XCTAssertFalse(app.staticTexts["/100"].exists)
    }
}
