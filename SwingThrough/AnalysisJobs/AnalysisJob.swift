import Foundation
import SwingKit

enum AnalysisStage: String, Codable, CaseIterable, Sendable {
    case queued
    case preparing
    case detectingSwing
    case tracking2D
    case tracking3D
    case measuring
    case resultsReady
    case enhancingCoaching
    case saving
    case completed
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .completed || self == .failed || self == .cancelled
    }

    var rank: Int {
        switch self {
        case .queued: 0
        case .preparing: 1
        case .tracking2D: 2
        case .detectingSwing: 3
        case .tracking3D: 4
        case .measuring: 5
        case .resultsReady: 6
        case .enhancingCoaching: 7
        case .saving: 8
        case .completed: 9
        case .failed, .cancelled: 10
        }
    }
}

struct AnalysisProgress: Sendable, Equatable {
    var jobID: UUID
    var executionID: UUID
    var stage: AnalysisStage
    var fraction: Double
    var message: String
    var estimatedSecondsRemaining: Double?

    init(jobID: UUID, executionID: UUID, stage: AnalysisStage, fraction: Double,
         message: String, estimatedSecondsRemaining: Double? = nil) {
        self.jobID = jobID
        self.executionID = executionID
        self.stage = stage
        self.fraction = min(1, max(0, fraction))
        self.message = message
        self.estimatedSecondsRemaining = estimatedSecondsRemaining
    }
}

struct AnalysisJobRequest: Sendable {
    var jobID: UUID
    var executionID: UUID
    var videoURL: URL
    var view: CaptureView
    var sourceWindow: ClosedRange<Double>?
    var handednessOverride: Handedness?
}

struct AnalysisJobDraft: Identifiable, Sendable, Equatable {
    var id: UUID
    var stage: AnalysisStage
    var club: String
    var view: CaptureView
    var videoFileName: String
    var attemptCount: Int
    var lastErrorCategory: String?
    var updatedAt: Date

    var statusLabel: String {
        switch (stage, lastErrorCategory) {
        case (_, "interrupted"): "Interrupted"
        case (.cancelled, _): "Canceled"
        case (.failed, _): "Couldn’t analyze"
        case (.queued, _), (.preparing, _): "Waiting"
        default: "Processing"
        }
    }
}

enum HandednessPreference: String, Codable, CaseIterable, Sendable, Identifiable {
    case automatic
    case right
    case left

    var id: String { rawValue }

    var resolved: Handedness? {
        switch self {
        case .automatic: nil
        case .right: .right
        case .left: .left
        }
    }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .right: "Right-handed"
        case .left: "Left-handed"
        }
    }
}

struct SwingSetupSelection: Sendable {
    var videoURL: URL
    var metadata: VideoPreflightMetadata
    var trimStart: Double
    var trimEnd: Double
    var view: CaptureView
    var club: String
    var handedness: HandednessPreference

    var sourceWindow: ClosedRange<Double> { trimStart...trimEnd }
}
