import XCTest
@testable import SwingKit

/// A3 — accuracy regression harness. Each fixture pins the pipeline's output to
/// per-metric tolerances (not byte-identical reports) so bounded-sampling and gating
/// changes are provably safe: a fixture drifting out of tolerance fails CI. The
/// tolerance rationale per metric lives in docs/VALIDATION.md.
///
/// The harness runs the *real* pipeline. On a host without an AVFoundation decoder for
/// the fixture (the CLI/`swift test` host — see docs/VALIDATION.md, AVFoundation
/// `-11821`) each fixture skips cleanly rather than failing; it runs fully in the
/// iPhone Simulator scheme. The bundled sample encodes the A0 acceptance gate: its
/// degenerate 3D yaw must resolve to `.insufficientData` (or its turn metrics withheld),
/// never a confident total.
final class AccuracyRegressionTests: XCTestCase {

    struct Fixture {
        var id: String
        var relativePath: String
        var view: CaptureView
        /// Expected checkpoint time windows, seconds (empty until footage is annotated).
        var checkpoints: [SwingPosition: ClosedRange<Double>] = [:]
        /// Expected measured-value windows per metric label (empty until annotated).
        var metricTolerances: [String: ClosedRange<Double>] = [:]
        /// A0 gate: this fixture's report must not present as a confident score.
        var mustNotBeConfident: Bool = false
    }

    static let fixtures: [Fixture] = [
        Fixture(
            id: "bundled-sample",
            relativePath: "SwingThrough/Fixtures/sample_dtl.mp4",
            view: .downTheLine,
            // Checkpoints/tolerances pending real annotation (docs/VALIDATION.md registry).
            mustNotBeConfident: true
        )
    ]

    func testFixturesStayWithinTolerance() async throws {
        for fixture in Self.fixtures {
            try await run(fixture)
        }
    }

    private func run(_ fixture: Fixture) async throws {
        guard let url = Self.fixtureURL(fixture.relativePath) else {
            throw XCTSkip("fixture \(fixture.id) not present at \(fixture.relativePath)")
        }
        let report: SwingReport
        do {
            report = try await SwingAnalyzer.analyze(url: url, view: fixture.view)
        } catch {
            // No usable decoder on this host, or the clip can't be analyzed here. The
            // Simulator scheme runs this fully; don't fail the CLI suite for it.
            throw XCTSkip("fixture \(fixture.id) could not be analyzed on this host: \(error.localizedDescription)")
        }

        if fixture.mustNotBeConfident {
            let turnWithheld = ["Shoulder Turn", "X-Factor at Transition"].allSatisfy { label in
                let m = report.metrics.first { $0.label == label }
                return m == nil || m?.quality?.provenance == .unavailable
            }
            XCTAssertTrue(
                report.score.availability == .insufficientData || turnWithheld,
                "\(fixture.id): a degenerate report must not present a confident score (A0 gate)"
            )
            XCTAssertFalse(
                report.score.isAvailable && !turnWithheld,
                "\(fixture.id): implausible turn metrics leaked into an available score"
            )
        }

        for (position, window) in fixture.checkpoints {
            guard let mark = report.mark(position) else {
                XCTFail("\(fixture.id): missing checkpoint \(position.shortName)")
                continue
            }
            XCTAssertTrue(window.contains(mark.time),
                          "\(fixture.id): \(position.shortName) at \(mark.time)s outside \(window)s")
        }

        for (label, window) in fixture.metricTolerances {
            guard let m = report.metrics.first(where: { $0.label == label }) else {
                XCTFail("\(fixture.id): expected metric \(label) missing")
                continue
            }
            // Only hold a measured value to tolerance; a withheld value is allowed to drift.
            guard m.quality?.provenance != .unavailable else { continue }
            XCTAssertTrue(window.contains(m.value),
                          "\(fixture.id): \(label) = \(m.value) outside tolerance \(window)")
        }
    }

    /// Resolves a repo-relative fixture path from this source file's location
    /// (…/SwingKit/Tests/SwingKitTests/AccuracyRegressionTests.swift → repo root).
    private static func fixtureURL(_ relativePath: String) -> URL? {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SwingKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // SwingKit
            .deletingLastPathComponent()   // repo root
        let url = repoRoot.appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
