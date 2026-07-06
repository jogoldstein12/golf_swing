import Foundation
import SwiftData
import SwingKit

enum SwingThroughSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [SwingRecord.self] }

    @Model
    final class SwingRecord {
        @Attribute(.unique) var id: UUID
        var date: Date
        var club: String
        var score: Int
        var viewRaw: String
        var reportFileName: String
        var videoFileName: String?
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
}

enum SwingThroughSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SwingThroughSchemaV1.SwingRecord.self, AnalysisJobRecord.self]
    }

    @Model
    final class AnalysisJobRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var updatedAt: Date
        var stageRaw: String
        var progress: Double
        var message: String
        var videoFileName: String
        var originalFileName: String?
        var viewRaw: String
        var club: String
        var attemptCount: Int
        var lastErrorCategory: String?
        var completedSwingID: UUID?
        var sourceDuration: Double?
        var sourceFPS: Double?
        var sourceWidth: Int?
        var sourceHeight: Int?
        var trimStart: Double?
        var trimEnd: Double?
        var handednessPreferenceRaw: String?
        var sourceCodec: String?
        var sourceIsHDR: Bool?

        init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(),
             stage: AnalysisStage = .queued, progress: Double = 0, message: String = "Waiting",
             videoFileName: String, originalFileName: String? = nil,
             view: CaptureView, club: String, attemptCount: Int = 0,
             handednessPreference: HandednessPreference = .automatic,
             trimStart: Double? = nil, trimEnd: Double? = nil,
             sourceMetadata: VideoPreflightMetadata? = nil,
             lastErrorCategory: String? = nil, completedSwingID: UUID? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.stageRaw = stage.rawValue
            self.progress = progress
            self.message = message
            self.videoFileName = videoFileName
            self.originalFileName = originalFileName
            self.viewRaw = view.rawValue
            self.club = club
            self.attemptCount = attemptCount
            self.handednessPreferenceRaw = handednessPreference.rawValue
            self.trimStart = trimStart
            self.trimEnd = trimEnd
            self.sourceDuration = sourceMetadata?.duration
            self.sourceFPS = sourceMetadata?.nominalFPS
            self.sourceWidth = sourceMetadata?.displayWidth
            self.sourceHeight = sourceMetadata?.displayHeight
            self.sourceCodec = sourceMetadata?.codec
            self.sourceIsHDR = sourceMetadata?.isHDR
            self.lastErrorCategory = lastErrorCategory
            self.completedSwingID = completedSwingID
        }

        var stage: AnalysisStage {
            get { AnalysisStage(rawValue: stageRaw) ?? .failed }
            set { stageRaw = newValue.rawValue }
        }

        var view: CaptureView {
            CaptureView(rawValue: viewRaw) ?? .downTheLine
        }

        var handednessPreference: HandednessPreference {
            HandednessPreference(rawValue: handednessPreferenceRaw ?? "") ?? .automatic
        }

        var sourceWindow: ClosedRange<Double>? {
            guard let trimStart, let trimEnd, trimEnd > trimStart else { return nil }
            return trimStart...trimEnd
        }

        var draft: AnalysisJobDraft {
            AnalysisJobDraft(
                id: id, stage: stage, club: club, view: view,
                videoFileName: videoFileName, attemptCount: attemptCount,
                lastErrorCategory: lastErrorCategory, updatedAt: updatedAt
            )
        }
    }
}

enum SwingThroughSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [SwingThroughSchemaV1.SwingRecord.self,
         SwingThroughSchemaV2.AnalysisJobRecord.self,
         FocusRecord.self]
    }

    /// WS-E — the pinned carry-forward focus: one thing the golfer is working on for a
    /// (club, view), verified by the next same-club swing. At most one active (unresolved)
    /// per (club, view); resolving sets `resolvedSwingID`.
    @Model
    final class FocusRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var club: String
        var viewRaw: String
        var goalTitle: String
        var metricLabel: String
        var cue: String
        var drillName: String
        var resolvedSwingID: UUID?

        init(id: UUID = UUID(), createdAt: Date = Date(), club: String, viewRaw: String,
             goalTitle: String, metricLabel: String, cue: String, drillName: String,
             resolvedSwingID: UUID? = nil) {
            self.id = id
            self.createdAt = createdAt
            self.club = club
            self.viewRaw = viewRaw
            self.goalTitle = goalTitle
            self.metricLabel = metricLabel
            self.cue = cue
            self.drillName = drillName
            self.resolvedSwingID = resolvedSwingID
        }

        var isResolved: Bool { resolvedSwingID != nil }
    }
}

enum SwingThroughMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SwingThroughSchemaV1.self, SwingThroughSchemaV2.self, SwingThroughSchemaV3.self]
    }

    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3] }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SwingThroughSchemaV1.self,
        toVersion: SwingThroughSchemaV2.self
    )

    // FocusRecord is purely additive, so a lightweight migration suffices.
    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SwingThroughSchemaV2.self,
        toVersion: SwingThroughSchemaV3.self
    )
}

typealias SwingRecord = SwingThroughSchemaV1.SwingRecord
typealias AnalysisJobRecord = SwingThroughSchemaV2.AnalysisJobRecord
typealias FocusRecord = SwingThroughSchemaV3.FocusRecord
