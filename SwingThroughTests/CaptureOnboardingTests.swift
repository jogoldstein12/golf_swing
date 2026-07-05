import XCTest
@testable import SwingThrough

@MainActor
final class CaptureOnboardingTests: XCTestCase {
    // The persisted flag is the sole gate on the first-run walkthrough.
    func testShouldPresentOnlyWhenNotYetSeen() {
        XCTAssertTrue(CaptureOnboarding.shouldPresent(hasSeenOnboarding: false))
        XCTAssertFalse(CaptureOnboarding.shouldPresent(hasSeenOnboarding: true))
    }

    // The gate reads through the same defaults key CaptureScreen binds via @AppStorage.
    func testPersistedFlagRoundTripsGate() {
        let defaults = UserDefaults.standard
        let key = CaptureOnboarding.hasSeenDefaultsKey
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        XCTAssertTrue(CaptureOnboarding.shouldPresent(
            hasSeenOnboarding: defaults.bool(forKey: key)),
            "Unset flag (fresh install) must present the walkthrough")

        defaults.set(true, forKey: key)
        XCTAssertFalse(CaptureOnboarding.shouldPresent(
            hasSeenOnboarding: defaults.bool(forKey: key)),
            "Once seen, the walkthrough must not present again")
    }
}
