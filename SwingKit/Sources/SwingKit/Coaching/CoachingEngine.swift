// The interpretation layer's public contract. A CoachingEngine turns a measured SwingReport
// into words — it never sees video or frames, only the numbers already computed by the
// measurement pipeline (Report.swift). Two implementations: RuleBasedCoach (deterministic,
// offline) and ClaudeCoach (LLM-grounded, premium). CoachingService picks between them.
import Foundation

/// Per-session context that shapes tone and continuity without changing the underlying
/// measurements. Never influences which faults are real — only how they're framed.
public struct CoachingContext: Codable, Sendable {
    public var skillLevel: String?       // "beginner" | "intermediate" | "advanced" | nil
    public var club: String?
    public var recentGoalTitles: [String]  // continuity across sessions — avoid repeating verbatim

    public init(skillLevel: String? = nil, club: String? = nil, recentGoalTitles: [String] = []) {
        self.skillLevel = skillLevel
        self.club = club
        self.recentGoalTitles = recentGoalTitles
    }
}

public protocol CoachingEngine: Sendable {
    func coach(_ report: SwingReport, context: CoachingContext) async throws -> CoachingPlan
}

/// Resolves the Claude API key for injection. Default chain: ANTHROPIC_API_KEY env var → nil.
/// A Keychain-backed provider comes later from the app side — this protocol exists so that
/// swap is a one-line change at the call site, never a rewrite of ClaudeCoach.
public protocol APIKeyProvider: Sendable {
    func apiKey() -> String?
}

public struct EnvironmentAPIKeyProvider: APIKeyProvider {
    public init() {}
    public func apiKey() -> String? {
        let value = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
        return (value?.isEmpty ?? true) ? nil : value
    }
}

public enum CoachingError: Error, CustomStringConvertible, Sendable {
    case noAPIKey
    case network(String)
    case httpStatus(Int)
    case malformedResponse(String)
    case decoding(String)

    public var description: String {
        switch self {
        case .noAPIKey: return "no ANTHROPIC_API_KEY available"
        case .network(let msg): return "network error: \(msg)"
        case .httpStatus(let code): return "unexpected HTTP status \(code)"
        case .malformedResponse(let msg): return "malformed response: \(msg)"
        case .decoding(let msg): return "failed to decode coaching plan: \(msg)"
        }
    }
}
