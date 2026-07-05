// Track B results-experience smoke tests: the lead card leads with the top coaching
// goal, and a low-confidence report leads with the confidence state (never a score).
import XCTest

final class LeadCardTests: XCTestCase {

    /// The lead card surfaces the #1 coaching goal's headline as the first finding.
    func testLeadCardShowsTopGoal() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        // The demo report's priority-1 goal.
        XCTAssertTrue(
            app.staticTexts["Shallow the shaft in transition"].waitForExistence(timeout: 15)
        )
        // Its single next action is labelled on the card.
        XCTAssertTrue(app.staticTexts["DO THIS NEXT"].exists)
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
