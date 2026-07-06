import XCTest
import SwiftData
@testable import SwingThrough

final class SampleSeedTests: XCTestCase {

    @MainActor
    func testEnsureSeedsOnceAndIsIdempotent() throws {
        try XCTSkipIf(DemoData.load() == nil, "Bundled sample unavailable in this test host")

        let container = try ModelContainer(
            for: SwingRecord.self, AnalysisJobRecord.self, FocusRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        XCTAssertTrue(try ctx.fetch(FetchDescriptor<SwingRecord>()).isEmpty)

        // First call seeds exactly one sample record and persists it.
        XCTAssertTrue(SampleSeed.ensure(in: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SwingRecord>()).filter(\.isSample).count, 1)

        // Second call is a no-op — never duplicates the sample.
        XCTAssertTrue(SampleSeed.ensure(in: ctx))
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<SwingRecord>()).filter(\.isSample).count, 1)
    }
}
