// Deterministic interaction scripts for frame-level verification. Run these while
// `simctl io recordVideo` captures the screen, then dump + diff frames.
// Pacing sleeps are deliberate: they give transitions time to fully settle so
// recorded frames isolate each animation.
import XCTest

final class DriveTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterLaunch()
    }

    private func continueAfterLaunch() {
        continueAfterFailure = false
    }

    /// Home → analysis → panes → checkpoints → marker → back.
    func testMainFlow() {
        let app = XCUIApplication()
        app.launch()

        // Home settles
        XCTAssertTrue(app.staticTexts["Swing Through"].waitForExistence(timeout: 10))
        sleep(2)

        // Open the sample swing
        app.staticTexts["Today"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Top"].waitForExistence(timeout: 15))
        sleep(2)

        // Checkpoints
        for label in ["Top", "Impact", "Follow", "Address"] {
            app.staticTexts[label].firstMatch.tap()
            sleep(2)
        }

        // Panes
        for pane in ["3D", "SPLIT", "VIDEO"] {
            app.staticTexts[pane].firstMatch.tap()
            sleep(2)
        }

        // Playback
        app.buttons.matching(NSPredicate(format: "label == ''")).element(boundBy: 0)
        sleep(1)

        // Scroll down through metrics + goals, then back up
        app.swipeUp(velocity: .slow)
        sleep(1)
        app.swipeUp(velocity: .slow)
        sleep(2)
        app.swipeDown(velocity: .fast)
        sleep(1)

        // Back to home
        app.staticTexts["SWINGS"].firstMatch.tap()
        sleep(2)
    }
}
