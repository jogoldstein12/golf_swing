// WS-E coaching-canvas + practice-loop smoke tests: the calm glance strip leads the
// scored results screen, a goal's drill opens the practice page, and no raw provenance
// jargon ("Inferred" / "Interpolated") ever reaches the UI.
import XCTest

final class WSECanvasUITests: XCTestCase {

    /// The scored results screen leads with the calm glance strip.
    func testGlanceStripShows() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        XCTAssertTrue(
            app.otherElements["glanceStrip"].waitForExistence(timeout: 15)
        )
    }

    /// Tapping a goal's drill opens the practice page with its "Work on this" commit.
    func testGoalDrillIsTappable() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        let drill = app.buttons["goalDrill"].firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 15))
        drill.tap()

        XCTAssertTrue(
            app.buttons["workOnThis"].waitForExistence(timeout: 10),
            "the drill-detail page should surface its 'Work on this' commit"
        )
    }

    /// The results screen never surfaces the raw pipeline provenance words.
    func testNoProvenanceJargon() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        // Let the screen settle.
        XCTAssertTrue(app.otherElements["glanceStrip"].waitForExistence(timeout: 15))

        // Reveal the measurements block, where provenance is rendered per row.
        let seeAll = app.staticTexts["SEE ALL MEASUREMENTS"].firstMatch
        if seeAll.waitForExistence(timeout: 3) { seeAll.tap() }

        XCTAssertFalse(app.staticTexts["Inferred"].exists)
        XCTAssertFalse(app.staticTexts["Interpolated"].exists)
    }
}
