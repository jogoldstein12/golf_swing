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

    /// NP-3 — the "Power sequence" panel exists below the metrics, is collapsed by
    /// default, and expanding it never asserts a confident "in order" claim the demo's
    /// own peaks don't back: DemoData's sequence is a complete, confident, non-degenerate
    /// read (trustworthy) whose peak order is pelvis → arms → torso → club — NOT the
    /// ideal ground-up order — so the honest verdict is "Out of order", never "In order".
    func testPowerSequenceSectionCollapsedThenShowsHonestVerdict() {
        let app = XCUIApplication()
        app.launchEnvironment["ST_SCREEN"] = "analysis"
        app.launch()

        XCTAssertTrue(app.otherElements["glanceStrip"].waitForExistence(timeout: 15))

        let section = app.otherElements["powerSequenceSection"]
        XCTAssertTrue(section.waitForExistence(timeout: 10))

        // Collapsed by default: neither the confident verdict nor the caution caption
        // is on screen until the section is expanded.
        XCTAssertFalse(app.staticTexts["IN ORDER"].exists)
        XCTAssertFalse(app.staticTexts["OUT OF ORDER"].exists)
        XCTAssertFalse(
            app.staticTexts["Body rotation was too unsteady at the top to judge the order"].exists
        )

        let disclosureLabel = app.staticTexts["POWER SEQUENCE"].firstMatch
        XCTAssertTrue(disclosureLabel.waitForExistence(timeout: 5))
        disclosureLabel.tap()

        // The demo's real peaks are trustworthy but out of order (arms before torso):
        // the honest read is "Out of order", and the confident "In order" claim must
        // be absent.
        XCTAssertTrue(app.staticTexts["OUT OF ORDER"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["IN ORDER"].exists)
        XCTAssertFalse(
            app.staticTexts["Body rotation was too unsteady at the top to judge the order"].exists
        )
    }
}
