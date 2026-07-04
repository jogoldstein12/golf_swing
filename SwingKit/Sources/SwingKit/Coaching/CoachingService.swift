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

    public init(apiKeyProvider: APIKeyProvider = EnvironmentAPIKeyProvider(),
                model: String = "claude-opus-4-8") {
        self.apiKeyProvider = apiKeyProvider
        self.claude = ClaudeCoach(apiKeyProvider: apiKeyProvider, model: model)
        self.rules = RuleBasedCoach()
    }

    /// Always returns a plan — never throws. `plan.source` tells the caller which path ran.
    public func coach(_ report: SwingReport, context: CoachingContext) async -> CoachingPlan {
        if apiKeyProvider.apiKey() != nil {
            do {
                let plan = try await claude.coach(report, context: context)
                logger.log("coaching served by: claude")
                return plan
            } catch {
                logger.log("coaching: claude path failed, falling back to rules")
            }
        } else {
            logger.log("coaching: no API key available, using rules")
        }

        do {
            let plan = try await rules.coach(report, context: context)
            logger.log("coaching served by: rules")
            return plan
        } catch {
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
