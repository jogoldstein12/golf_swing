import Foundation
import Observation
import SwingKit

/// Holds only privacy-safe metadata exported by SwingKit. The latest snapshot is
/// persisted so a device tester can share it even after relaunching the app.
@Observable
@MainActor
final class DiagnosticsStore {
    static let shared = DiagnosticsStore()

    private(set) var latest: AnalysisDiagnostics?
    private(set) var latestExportURL: URL?
    private var activeJobID: UUID?

    private init() {
        let url = Self.directory.appendingPathComponent("latest-analysis.json")
        guard let data = try? Data(contentsOf: url),
              let value = try? Self.decoder.decode(AnalysisDiagnostics.self, from: data)
        else { return }
        latest = value
        latestExportURL = url
    }

    func begin(jobID: UUID) {
        activeJobID = jobID
    }

    func update(_ diagnostics: AnalysisDiagnostics) {
        if let activeJobID, diagnostics.jobID != activeJobID { return }
        if let current = latest, current.jobID == diagnostics.jobID {
            if current.finishedAt != nil, diagnostics.finishedAt == nil { return }
            if diagnostics.stageDurations.count < current.stageDurations.count { return }
        }
        latest = diagnostics
        do {
            try FileManager.default.createDirectory(
                at: Self.directory,
                withIntermediateDirectories: true
            )
            let url = Self.directory.appendingPathComponent("latest-analysis.json")
            try diagnostics.exportedJSON().write(to: url, options: .atomic)
            latestExportURL = url
        } catch {
            // Diagnostics must never interfere with analysis or persistence.
            latestExportURL = nil
        }
    }

    private static var directory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
