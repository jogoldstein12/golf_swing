// Local persistence: SwiftData record per swing + report JSON and video files in
// Application Support. The record carries what the gallery needs (date, club, score);
// the full SwingReport loads lazily from disk when a swing is opened.
import Foundation
import SwingKit

enum SwingStore {
    static var swingsDirectory: URL {
        let dir = URL.applicationSupportDirectory.appendingPathComponent("Swings", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var jobsDirectory: URL {
        let dir = swingsDirectory.appendingPathComponent("Jobs", isDirectory: true)
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

    /// Move an app-owned temporary import/capture into durable storage before any
    /// analysis begins. Read-only bundle/external sources are copied instead.
    static func stageJobVideo(at sourceURL: URL, jobID: UUID,
                              view: CaptureView, club: String,
                              handednessPreference: HandednessPreference = .automatic,
                              trimStart: Double? = nil,
                              trimEnd: Double? = nil,
                              sourceMetadata: VideoPreflightMetadata? = nil) throws -> String {
        let ext = sourceURL.pathExtension.isEmpty ? "mp4" : sourceURL.pathExtension.lowercased()
        let relativePath = "Jobs/\(jobID.uuidString)/source.\(ext)"
        let destination = try validatedURL(forRelativePath: relativePath)
        if sourceURL.standardizedFileURL == destination.standardizedFileURL {
            guard FileManager.default.fileExists(atPath: destination.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return relativePath
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            return relativePath
        }

        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = AnalysisJobManifest(
            id: jobID,
            createdAt: Date(),
            inputRelativePath: relativePath,
            originalFileName: sourceURL.lastPathComponent,
            viewRaw: view.rawValue,
            club: club,
            handednessPreferenceRaw: handednessPreference.rawValue,
            trimStart: trimStart,
            trimEnd: trimEnd,
            sourceMetadata: sourceMetadata
        )
        try manifest.write(to: directory.appendingPathComponent("manifest.json"))

        let sourcePath = sourceURL.standardizedFileURL.path
        let temporaryPath = FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"
        let swingRootPath = swingsDirectory.standardizedFileURL.path + "/"
        let isOwnedCapture = sourcePath.hasPrefix(swingRootPath)
            && sourceURL.lastPathComponent.hasPrefix("swing-")
        do {
            if sourcePath.hasPrefix(temporaryPath) || isOwnedCapture {
                try FileManager.default.moveItem(at: sourceURL, to: destination)
            } else {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
            }
        } catch {
            if sourcePath.hasPrefix(temporaryPath) || isOwnedCapture {
                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destination)
                    try? FileManager.default.removeItem(at: sourceURL)
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    throw error
                }
            } else {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
        return relativePath
    }

    static func videoURL(named name: String) throws -> URL {
        try validatedURL(forRelativePath: name)
    }

    static func videoExists(named name: String) -> Bool {
        guard let url = try? videoURL(named: name) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func removeVideo(named name: String) throws {
        let url = try videoURL(named: name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func removeReport(named name: String) throws {
        let url = swingsDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func removeJobFiles(jobID: UUID) throws {
        let directory = try validatedURL(forRelativePath: "Jobs/\(jobID.uuidString)")
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    static func markJobCompleted(jobID: UUID) throws {
        let manifest = try validatedURL(
            forRelativePath: "Jobs/\(jobID.uuidString)/manifest.json"
        )
        if FileManager.default.fileExists(atPath: manifest.path) {
            try FileManager.default.removeItem(at: manifest)
        }
    }

    /// Remove only unaccepted app-owned imports/captures. Bundle and arbitrary
    /// external URLs are never deleted by setup cancellation.
    static func removePendingSourceIfOwned(_ url: URL) {
        let path = url.standardizedFileURL.path
        let isTemporary = path.hasPrefix(
            FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"
        )
        let isUnacceptedCapture = path.hasPrefix(swingsDirectory.standardizedFileURL.path + "/")
            && url.lastPathComponent.hasPrefix("swing-")
        if isTemporary || isUnacceptedCapture {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func jobManifests() -> [AnalysisJobManifest] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: jobsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return directories.compactMap {
            AnalysisJobManifest.load(from: $0.appendingPathComponent("manifest.json"))
        }
    }

    static func videoURL(for record: SwingRecord) -> URL? {
        if let name = record.videoFileName {
            guard let url = try? videoURL(named: name) else { return nil }
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
            report = DemoData.load()?.report
        } else {
            report = loadReport(named: record.reportFileName)
        }
        guard let report else { return nil }
        let size = CGSize(width: report.videoWidth ?? 1440, height: report.videoHeight ?? 2560)
        return AnalysisModel(report: report, videoURL: videoURL, videoSize: size)
    }

    static func validatedURL(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let root = swingsDirectory.standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return candidate
    }
}

struct AnalysisJobManifest: Codable, Sendable {
    var id: UUID
    var createdAt: Date
    var inputRelativePath: String
    var originalFileName: String?
    var viewRaw: String
    var club: String
    var handednessPreferenceRaw: String?
    var trimStart: Double?
    var trimEnd: Double?
    var sourceMetadata: VideoPreflightMetadata?

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    static func load(from url: URL) -> AnalysisJobManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Self.self, from: data)
    }
}
