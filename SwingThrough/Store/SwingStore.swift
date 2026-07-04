// Local persistence: SwiftData record per swing + report JSON and video files in
// Application Support. The record carries what the gallery needs (date, club, score);
// the full SwingReport loads lazily from disk when a swing is opened.
import Foundation
import SwiftData
import SwingKit

@Model
final class SwingRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var club: String
    var score: Int
    var viewRaw: String
    var reportFileName: String
    var videoFileName: String?
    /// The bundled demo swing (present until the user records their own).
    var isSample: Bool

    init(id: UUID, date: Date, club: String, score: Int, viewRaw: String,
         reportFileName: String, videoFileName: String?, isSample: Bool = false) {
        self.id = id
        self.date = date
        self.club = club
        self.score = score
        self.viewRaw = viewRaw
        self.reportFileName = reportFileName
        self.videoFileName = videoFileName
        self.isSample = isSample
    }
}

enum SwingStore {
    static var swingsDirectory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Swings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveReport(_ report: SwingReport) throws -> String {
        let name = "\(report.id.uuidString).json"
        let data = try JSONEncoder().encode(report)
        try data.write(to: swingsDirectory.appendingPathComponent(name), options: .atomic)
        return name
    }

    static func loadReport(named name: String) -> SwingReport? {
        let url = swingsDirectory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SwingReport.self, from: data)
    }

    /// Copy a captured video into the store; returns the stored file name.
    static func adoptVideo(at src: URL, id: UUID) throws -> String {
        let name = "\(id.uuidString).\(src.pathExtension.isEmpty ? "mp4" : src.pathExtension)"
        let dst = swingsDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
        return name
    }

    static func videoURL(for record: SwingRecord) -> URL? {
        if let name = record.videoFileName {
            let url = swingsDirectory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if record.isSample {
            return Bundle.main.url(forResource: "sample_dtl", withExtension: "mp4")
        }
        return nil
    }

    /// Build the analysis model for a stored swing.
    static func analysisModel(for record: SwingRecord) -> AnalysisModel? {
        guard let videoURL = videoURL(for: record) else { return nil }
        let report: SwingReport?
        if record.isSample {
            report = DemoData.load().report
        } else {
            report = loadReport(named: record.reportFileName)
        }
        guard let report else { return nil }
        let size = CGSize(width: report.videoWidth ?? 1440, height: report.videoHeight ?? 2560)
        return AnalysisModel(report: report, videoURL: videoURL, videoSize: size)
    }
}
