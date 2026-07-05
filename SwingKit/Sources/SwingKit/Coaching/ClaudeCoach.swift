// The premium coaching path: Claude reasons over the compact measured-data payload and returns
// a CoachingPlan via forced tool use (structured output). The model NEVER sees video or frames —
// see CoachingPayloadEncoder for exactly what it does see. No key or network failure here ever
// crashes the caller: every failure mode throws a CoachingError so CoachingService can fall back
// to RuleBasedCoach.
import Foundation

public struct ClaudeCoach: CoachingEngine {
    public var model: String
    public var apiKeyProvider: APIKeyProvider
    public var session: URLSession
    public var timeout: TimeInterval

    private static let endpointString = "https://api.anthropic.com/v1/messages"
    private static let anthropicVersion = "2023-06-01"
    private static let toolName = "emit_coaching_plan"

    public init(apiKeyProvider: APIKeyProvider = EnvironmentAPIKeyProvider(),
                model: String = "claude-opus-4-8",
                session: URLSession = .shared,
                timeout: TimeInterval = 8) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.session = session
        self.timeout = timeout
    }

    public func coach(_ report: SwingReport, context: CoachingContext) async throws -> CoachingPlan {
        guard let key = apiKeyProvider.apiKey() else { throw CoachingError.noAPIKey }

        let payloadJSON: String
        do {
            payloadJSON = try CoachingPayloadEncoder.encodeJSONString(report: report, context: context)
        } catch {
            throw CoachingError.malformedResponse("failed to encode payload: \(error)")
        }

        let body: Data
        do {
            body = try Self.makeRequestBody(model: model, payloadJSON: payloadJSON)
        } catch {
            throw CoachingError.malformedResponse("failed to build request body: \(error)")
        }

        guard let endpoint = URL(string: Self.endpointString) else {
            throw CoachingError.network("invalid service endpoint")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = body

        let data = try await send(request)
        return try Self.parsePlan(from: data)
    }

    // MARK: - Networking

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw CoachingError.network("request failed")
        }

        guard let http = response as? HTTPURLResponse else {
            throw CoachingError.malformedResponse("no HTTP response")
        }
        if (200..<300).contains(http.statusCode) { return data }
        throw CoachingError.httpStatus(http.statusCode)
    }

    // MARK: - Request construction

    static func makeRequestBody(model: String, payloadJSON: String) throws -> Data {
        let goalSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "priority": ["type": "integer", "description": "1 = earliest link in the chain to fix first."],
                "title": ["type": "string", "description": "Imperative, specific — e.g. \"Shallow the shaft in transition\"."],
                "detail": ["type": "string", "description": "2-3 sentences explaining the WHY in swing-model terms, quoting the user's actual numbers."],
                "metricLabel": ["type": "string"],
                "current": ["type": "string", "description": "e.g. \"+4.2° steep\"."],
                "target": ["type": "string", "description": "e.g. \"±1.5°\"."],
                "drill": ["type": "string", "description": "Short drill name."],
                "drillDetail": ["type": "string", "description": "One or two sentences describing how to do the drill."],
            ],
            "required": ["priority", "title", "detail", "metricLabel", "current", "target", "drill", "drillDetail"],
            "additionalProperties": false,
        ]

        let inputSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "verdict": ["type": "string", "description": "One editorial sentence: the swing's character plus the one thing to change."],
                "goals": [
                    "type": "array",
                    "minItems": 2,
                    "maxItems": 4,
                    "items": goalSchema,
                ],
            ],
            "required": ["verdict", "goals"],
            "additionalProperties": false,
        ]

        let tool: [String: Any] = [
            "name": toolName,
            "description": "Emit the prioritized coaching plan grounded in the provided swing measurements.",
            "input_schema": inputSchema,
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1200,
            "system": systemPrompt,
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
            "messages": [
                ["role": "user", "content": payloadJSON],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Response parsing

    static func parsePlan(from data: Data) throws -> CoachingPlan {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CoachingError.malformedResponse("top-level JSON is not an object")
        }
        guard let content = obj["content"] as? [[String: Any]] else {
            throw CoachingError.malformedResponse("missing content array")
        }
        guard let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" && ($0["name"] as? String) == toolName }),
              let input = toolBlock["input"] as? [String: Any]
        else {
            throw CoachingError.malformedResponse("no \(toolName) tool_use block in response")
        }

        let inputData: Data
        do {
            inputData = try JSONSerialization.data(withJSONObject: input)
        } catch {
            throw CoachingError.malformedResponse("tool input is not serializable JSON")
        }

        do {
            let raw = try JSONDecoder().decode(RawPlan.self, from: inputData)
            let goals = raw.goals.map { g in
                CoachGoal(priority: g.priority, title: g.title, detail: g.detail, metricLabel: g.metricLabel,
                          current: g.current, target: g.target, drill: g.drill, drillDetail: g.drillDetail)
            }
            return CoachingPlan(verdict: raw.verdict, goals: goals, source: .claude)
        } catch {
            throw CoachingError.decoding("\(error)")
        }
    }

    private struct RawGoal: Decodable {
        let priority: Int
        let title: String
        let detail: String
        let metricLabel: String
        let current: String
        let target: String
        let drill: String
        let drillDetail: String
    }

    private struct RawPlan: Decodable {
        let verdict: String
        let goals: [RawGoal]
    }

    // MARK: - System prompt

    static let systemPrompt = """
    You are the coaching layer for Swing Through, a golf swing analysis app. You never see video \
    or frames — you reason ONLY from the computed biomechanics JSON in the user message. Never \
    invent a number that isn't present in that JSON.

    THE SWING MODEL, which grounds every note you write:
    1. Kinematic sequence: an efficient downswing unloads pelvis → torso → lead arm → club, each \
    segment peaking after its proximal driver. Arms or club firing early ("casting", over-the-top) \
    or pelvis and torso peaking together (no separation) leaks speed and consistency.
    2. Swing plane (down-the-line): the club should return through the "V" of the base plane line. \
    Over the top (positive deviation, steep, above the plane) causes pulls and slices; under plane \
    (negative, shallow, below the plane, trapped behind the body) causes blocks and hooks.
    3. Six degrees of freedom for pelvis and chest, all versus address: turn, bend, side bend, sway, \
    lift/drop, thrust. Early extension is the pelvis thrusting toward the ball while standing up — a \
    red flag for contact and low-point control. Sway is excessive lateral drift off a centered pivot.
    4. Tempo: backswing-to-downswing time ratio, tour benchmark about 3:1. A rushed transition is a \
    top cause of sequence breakdown.
    5. Turn magnitude: shoulder turn around 90° and hip turn around 45° at the top; under-turning \
    loses power.

    COACHING PRINCIPLE — fix the EARLIEST fault in the chain first: sequence and plane before \
    posture, posture before tempo, tempo before turn magnitude. Never lead with a cosmetic fix while \
    an earlier link in the chain is broken.

    VOICE — editorial, precise, quantified, warm but expert. No exclamation marks, no emoji, no \
    filler like "great job!" or generic tips. Quantify every claim with the numbers given in the \
    payload — never invent numbers that aren't there. One concrete drill per goal. Em-dashes welcome.

    Two examples of the target voice:
    1. title: "Shallow the shaft in transition" — detail: "Your one swing-changer. Feel the trail \
    elbow lead down in front of the hip as the pelvis opens — this drops the club under your steep \
    line and delivers it on plane, squaring the face sooner." — metricLabel: "Swing plane at P5" — \
    current: "+4.2° steep" — target: "±1.5°" — drill: "Pump drill" — drillDetail: "Pause at the top, \
    drop hands to the trail pocket, then fire."
    2. title: "Hold your spine angle" — detail: "Keep the pelvis back through impact instead of \
    thrusting toward the ball. Maintaining posture keeps the low point consistent and takes the \
    steepness out of the strike." — metricLabel: "Pelvis thrust at P7" — current: "+2.0 in" — \
    target: "±0.5 in" — drill: "Chair drill" — drillDetail: "Brush your seat against a chair back \
    through impact."

    OUTPUT — call emit_coaching_plan exactly once with:
    - verdict: one editorial sentence — the swing's character, built from its strongest measured \
    trait, plus the one thing to change (the highest-priority fault).
    - goals: 2 to 4 entries, priority-ordered (1 = fix first, matching the chain above). If every \
    measurement in the payload is inside its ideal band, return refinement goals for the tightest \
    margins instead of fabricating faults — never return zero goals.
    """
}
