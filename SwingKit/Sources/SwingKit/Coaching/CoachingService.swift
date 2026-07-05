// The façade the app calls. Tries ClaudeCoach when a key is available, falls back to
// RuleBasedCoach on any error (missing key, timeout, malformed response, whatever) — the caller
// always gets a plan. Logs which path ran via os_log; never logs plan content or the API key.
import Foundation
import os

public struct CoachingService: Sendable {
    private let claude: ClaudeCoach
    private let rules: RuleBasedCoach
    private let apiKeyProvider: APIKeyProvider
    private let logger = Logger(subsystem: "com.swingthrough.SwingKit", category: "Coaching")
    private static let performanceLog = OSLog(
        subsystem: "com.swingthrough.SwingKit",
        category: "Analysis"
    )

    public init(apiKeyProvider: APIKeyProvider = EnvironmentAPIKeyProvider(),
                model: String = "claude-opus-4-8") {
        self.apiKeyProvider = apiKeyProvider
        self.claude = ClaudeCoach(apiKeyProvider: apiKeyProvider, model: model)
        self.rules = RuleBasedCoach()
    }

    public func localCoach(_ report: SwingReport,
                           context: CoachingContext) async throws -> CoachingPlan {
        try Task.checkCancellation()
        return try await rules.coach(report, context: context)
    }

    /// Optional enhancement only. Callers already have local coaching and should
    /// preserve it when this throws or is cancelled.
    public func enhancedCoach(_ report: SwingReport,
                              context: CoachingContext) async throws -> CoachingPlan {
        try Task.checkCancellation()
        guard apiKeyProvider.apiKey() != nil else { throw CoachingError.noAPIKey }
        return try await claude.coach(report, context: context)
    }

    /// Returns a plan for every non-cancelled request. Cancellation is propagated so
    /// callers can stop an analysis job without waiting for network fallback work.
    public func coach(_ report: SwingReport, context: CoachingContext) async throws -> CoachingPlan {
        try Task.checkCancellation()
        if apiKeyProvider.apiKey() != nil {
            let interval = OSSignpostID(log: Self.performanceLog)
            os_signpost(.begin, log: Self.performanceLog, name: "RemoteCoaching",
                        signpostID: interval, "report=%{public}s", report.id.uuidString)
            do {
                let plan = try await claude.coach(report, context: context)
                os_signpost(.end, log: Self.performanceLog, name: "RemoteCoaching",
                            signpostID: interval, "report=%{public}s result=success", report.id.uuidString)
                logger.log("coaching served by: claude")
                return plan
            } catch is CancellationError {
                os_signpost(.end, log: Self.performanceLog, name: "RemoteCoaching",
                            signpostID: interval, "report=%{public}s result=cancelled", report.id.uuidString)
                throw CancellationError()
            } catch {
                os_signpost(.end, log: Self.performanceLog, name: "RemoteCoaching",
                            signpostID: interval, "report=%{public}s result=fallback", report.id.uuidString)
                logger.log("coaching: claude path failed, falling back to rules")
            }
        } else {
            logger.log("coaching: no API key available, using rules")
        }

        let interval = OSSignpostID(log: Self.performanceLog)
        os_signpost(.begin, log: Self.performanceLog, name: "LocalCoaching",
                    signpostID: interval, "report=%{public}s", report.id.uuidString)
        do {
            try Task.checkCancellation()
            let plan = try await rules.coach(report, context: context)
            os_signpost(.end, log: Self.performanceLog, name: "LocalCoaching",
                        signpostID: interval, "report=%{public}s result=success", report.id.uuidString)
            logger.log("coaching served by: rules")
            return plan
        } catch is CancellationError {
            os_signpost(.end, log: Self.performanceLog, name: "LocalCoaching",
                        signpostID: interval, "report=%{public}s result=cancelled", report.id.uuidString)
            throw CancellationError()
        } catch {
            os_signpost(.end, log: Self.performanceLog, name: "LocalCoaching",
                        signpostID: interval, "report=%{public}s result=failure", report.id.uuidString)
            // RuleBasedCoach doesn't throw in practice, but the protocol allows it —
            // never let this surface as a crash, and still honor "never zero goals".
            logger.log("coaching: rules path failed unexpectedly")
            return CoachingPlan(
                verdict: "Coaching is temporarily unavailable for this swing.",
                goals: [CoachGoal(priority: 1, title: "Try again",
                                   detail: "Coaching couldn't be generated for this swing. Re-run the analysis; if this repeats, the report may be missing required measurements.",
                                   metricLabel: "Coaching availability", current: "Unavailable", target: "Available",
                                   drill: Drills.mirrorCheckpoints.name, drillDetail: Drills.mirrorCheckpoints.detail)],
                source: .rules)
        }
    }
}
