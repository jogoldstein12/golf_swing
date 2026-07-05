import Foundation
import SwiftData
import SwingKit

@MainActor
enum AnalysisJobRecovery {
    static func reconcile(context: ModelContext) throws {
        let jobs = try context.fetch(FetchDescriptor<AnalysisJobRecord>())
        let completed = try context.fetch(FetchDescriptor<SwingRecord>())
        let completedIDs = Set(completed.map(\.id))
        var jobsByID = Dictionary(uniqueKeysWithValues: jobs.map { ($0.id, $0) })
        var changed = false

        for job in jobs {
            if !SwingStore.videoExists(named: job.videoFileName) {
                job.stage = .failed
                job.progress = 0
                job.message = "The retained video is unavailable."
                job.lastErrorCategory = "missingInput"
                job.updatedAt = Date()
                changed = true
            } else if !job.stage.isTerminal {
                job.stage = .failed
                job.message = "Analysis was interrupted. You can retry this swing."
                job.lastErrorCategory = "interrupted"
                job.updatedAt = Date()
                changed = true
            }
        }

        for manifest in SwingStore.jobManifests() where jobsByID[manifest.id] == nil {
            if completedIDs.contains(manifest.id) {
                try? SwingStore.markJobCompleted(jobID: manifest.id)
                continue
            }
            let inputExists = SwingStore.videoExists(named: manifest.inputRelativePath)
            let record = AnalysisJobRecord(
                id: manifest.id,
                createdAt: manifest.createdAt,
                stage: .failed,
                message: inputExists
                    ? "Analysis was interrupted. You can retry this swing."
                    : "The retained video is unavailable.",
                videoFileName: manifest.inputRelativePath,
                originalFileName: manifest.originalFileName,
                view: CaptureView(rawValue: manifest.viewRaw) ?? .downTheLine,
                club: manifest.club,
                handednessPreference: HandednessPreference(
                    rawValue: manifest.handednessPreferenceRaw ?? ""
                ) ?? .automatic,
                trimStart: manifest.trimStart,
                trimEnd: manifest.trimEnd,
                sourceMetadata: manifest.sourceMetadata,
                lastErrorCategory: inputExists ? "interrupted" : "missingInput"
            )
            context.insert(record)
            jobsByID[record.id] = record
            changed = true
        }

        if changed { try context.save() }
    }
}
