import Foundation
import SwingKit

actor AnalysisFileStore {
    func stageVideo(at sourceURL: URL, jobID: UUID,
                    view: CaptureView, club: String,
                    handednessPreference: HandednessPreference = .automatic,
                    trimStart: Double? = nil,
                    trimEnd: Double? = nil,
                    sourceMetadata: VideoPreflightMetadata? = nil) throws -> String {
        try SwingStore.stageJobVideo(
            at: sourceURL, jobID: jobID, view: view, club: club,
            handednessPreference: handednessPreference,
            trimStart: trimStart,
            trimEnd: trimEnd,
            sourceMetadata: sourceMetadata
        )
    }

    func removeVideo(named name: String) throws {
        try SwingStore.removeVideo(named: name)
    }

    func videoExists(named name: String) -> Bool {
        SwingStore.videoExists(named: name)
    }

    func videoURL(named name: String) throws -> URL {
        try SwingStore.videoURL(named: name)
    }

    func discard(jobID: UUID) throws {
        try SwingStore.removeJobFiles(jobID: jobID)
    }

    func markCompleted(jobID: UUID) throws {
        try SwingStore.markJobCompleted(jobID: jobID)
    }

    func saveReport(_ report: SwingReport) throws -> String {
        try SwingStore.saveReport(report)
    }

    func removeReport(named name: String) throws {
        try SwingStore.removeReport(named: name)
    }
}
