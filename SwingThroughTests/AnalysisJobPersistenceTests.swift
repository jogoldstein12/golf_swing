import SwiftData
import XCTest
import SwingKit
@testable import SwingThrough

@MainActor
final class AnalysisJobPersistenceTests: XCTestCase {
    func testV1StoreMigratesToV2WithoutChangingSwingRecord() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        let id = UUID()

        do {
            let schema = Schema(versionedSchema: SwingThroughSchemaV1.self)
            let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            context.insert(SwingRecord(
                id: id,
                date: Date(timeIntervalSince1970: 1234),
                club: "7 Iron",
                score: 81,
                viewRaw: CaptureView.downTheLine.rawValue,
                reportFileName: "report.json",
                videoFileName: "video.mov",
                isSample: false
            ))
            try context.save()
        }

        let schema = Schema(versionedSchema: SwingThroughSchemaV2.self)
        let configuration = ModelConfiguration("migration", schema: schema, url: storeURL)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: SwingThroughMigrationPlan.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<SwingRecord>())

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].id, id)
        XCTAssertEqual(records[0].club, "7 Iron")
        XCTAssertEqual(records[0].score, 81)
        XCTAssertEqual(records[0].reportFileName, "report.json")
        XCTAssertEqual(records[0].videoFileName, "video.mov")
        XCTAssertTrue(try context.fetch(FetchDescriptor<AnalysisJobRecord>()).isEmpty)
    }

    func testRecoveryMarksNonterminalJobInterruptedAndRetainsInput() throws {
        let schema = Schema(versionedSchema: SwingThroughSchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("source-\(UUID().uuidString).mov")
        try Data([0, 1, 2]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let id = UUID()
        let relative = try SwingStore.stageJobVideo(
            at: source, jobID: id, view: .downTheLine, club: "7 Iron"
        )
        defer { try? SwingStore.removeJobFiles(jobID: id) }
        let job = AnalysisJobRecord(
            id: id,
            stage: .tracking3D,
            message: "Tracking",
            videoFileName: relative,
            view: .downTheLine,
            club: "7 Iron"
        )
        context.insert(job)
        try context.save()

        try AnalysisJobRecovery.reconcile(context: context)

        XCTAssertEqual(job.stage, .failed)
        XCTAssertEqual(job.lastErrorCategory, "interrupted")
        XCTAssertTrue(SwingStore.videoExists(named: relative))
    }

    func testRelativePathCannotEscapeSwingDirectory() {
        XCTAssertThrowsError(try SwingStore.validatedURL(forRelativePath: "../secret.mov"))
        XCTAssertThrowsError(try SwingStore.validatedURL(forRelativePath: "/tmp/secret.mov"))
    }
}
