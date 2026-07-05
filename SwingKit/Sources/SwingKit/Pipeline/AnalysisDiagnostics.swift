import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Privacy-safe performance metadata for one analysis run.
///
/// This type intentionally cannot contain video URLs, joint coordinates, API keys,
/// or coaching text. Exported diagnostics are safe to attach to a beta bug report.
public struct AnalysisDiagnostics: Codable, Equatable, Sendable {
    public var jobID: UUID
    public var startedAt: Date
    public var finishedAt: Date?
    public var sourceDuration: Double
    public var sourceFPS: Double
    public var sourceWidth: Int
    public var sourceHeight: Int
    public var sampled2DFrames: Int
    public var sampled3DFrames: Int
    public var droppedFrames: Int
    public var recoverableFrameErrors: Int
    public var stageDurations: [String: Double]
    public var peakMemoryBytes: UInt64?
    public var thermalStates: [String]
    public var failureCategory: String?

    public init(
        jobID: UUID = UUID(),
        startedAt: Date = Date(),
        finishedAt: Date? = nil,
        sourceDuration: Double = 0,
        sourceFPS: Double = 0,
        sourceWidth: Int = 0,
        sourceHeight: Int = 0,
        sampled2DFrames: Int = 0,
        sampled3DFrames: Int = 0,
        droppedFrames: Int = 0,
        recoverableFrameErrors: Int = 0,
        stageDurations: [String: Double] = [:],
        peakMemoryBytes: UInt64? = nil,
        thermalStates: [String] = [],
        failureCategory: String? = nil
    ) {
        self.jobID = jobID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.sourceDuration = sourceDuration
        self.sourceFPS = sourceFPS
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.sampled2DFrames = sampled2DFrames
        self.sampled3DFrames = sampled3DFrames
        self.droppedFrames = droppedFrames
        self.recoverableFrameErrors = recoverableFrameErrors
        self.stageDurations = stageDurations
        self.peakMemoryBytes = peakMemoryBytes
        self.thermalStates = thermalStates
        self.failureCategory = failureCategory
    }

    /// Sum of explicitly measured pipeline stages. Stages may be nested in future
    /// versions, so callers should use this as a work total rather than wall time.
    public var measuredStageDuration: Double {
        stageDurations.values.reduce(0, +)
    }

    public mutating func recordStage(_ name: String, duration: TimeInterval) {
        stageDurations[name, default: 0] += max(0, duration)
    }

    public mutating func recordThermalState(_ state: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState) {
        let value: String = switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
        if thermalStates.last != value {
            thermalStates.append(value)
        }
    }

    public mutating func recordPeakMemory(_ bytes: UInt64?) {
        guard let bytes else { return }
        peakMemoryBytes = max(peakMemoryBytes ?? 0, bytes)
    }

    /// Store only a stable error category. Localized descriptions and userInfo can
    /// contain file paths, request bodies, or provider messages and are never kept.
    public mutating func recordFailure(_ error: Error) {
        failureCategory = Self.safeFailureCategory(error)
        finishedAt = Date()
    }

    public mutating func finish() {
        finishedAt = Date()
    }

    public func exportedJSON(prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func safeFailureCategory(_ error: Error) -> String {
        if error is CancellationError { return "cancelled" }
        let nsError = error as NSError
        let family: String = switch nsError.domain {
        case "SwingKit": "swingkit"
        case "AVFoundationErrorDomain": "avfoundation"
        case "VNErrorDomain": "vision"
        case NSURLErrorDomain: "network"
        case NSCocoaErrorDomain: "cocoa"
        default: "other"
        }
        return "\(family).\(nsError.code)"
    }
}

enum AnalysisMemory {
    static func residentBytes() -> UInt64? {
#if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
#else
        return nil
#endif
    }
}

/// Small value-type gate used at the producer so UI work is never enqueued faster
/// than the configured rate. Supplying `now` keeps the behavior deterministic in tests.
struct AnalysisProgressThrottler: Sendable {
    private let minimumInterval: TimeInterval
    private var lastEmissionTime: TimeInterval?

    init(maximumUpdatesPerSecond: Double = 10) {
        minimumInterval = 1 / max(1, maximumUpdatesPerSecond)
    }

    mutating func shouldEmit(progress: Double, now: TimeInterval) -> Bool {
        if progress >= 1 {
            lastEmissionTime = now
            return true
        }
        guard let lastEmissionTime else {
            self.lastEmissionTime = now
            return true
        }
        guard now - lastEmissionTime >= minimumInterval else { return false }
        self.lastEmissionTime = now
        return true
    }
}

enum AnalysisStageTimer {
    static func measure<T>(
        stage: String,
        diagnostics: inout AnalysisDiagnostics,
        now: () -> TimeInterval = { Date().timeIntervalSinceReferenceDate },
        begin: () -> Void = {},
        end: (_ succeeded: Bool) -> Void = { _ in },
        operation: () async throws -> T
    ) async throws -> T {
        try Task.checkCancellation()
        begin()
        let started = now()
        do {
            let value = try await operation()
            try Task.checkCancellation()
            diagnostics.recordStage(stage, duration: now() - started)
            end(true)
            return value
        } catch {
            diagnostics.recordStage(stage, duration: now() - started)
            end(false)
            throw error
        }
    }
}
