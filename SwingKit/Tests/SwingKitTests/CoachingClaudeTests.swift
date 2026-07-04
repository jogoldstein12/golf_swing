// ClaudeCoach tests that never touch the network: the missing-key guard, request-body shape,
// and tool_use response parsing are all exercised offline.
import XCTest
@testable import SwingKit

private struct NilKeyProvider: APIKeyProvider {
    func apiKey() -> String? { nil }
}

final class CoachingClaudeTests: XCTestCase {

    func testMissingAPIKeyThrowsWithoutNetworkCall() async {
        let coach = ClaudeCoach(apiKeyProvider: NilKeyProvider())
        let report = CoachingRuleBasedTestsSupport.minimalReport()
        do {
            _ = try await coach.coach(report, context: .init())
            XCTFail("expected .noAPIKey")
        } catch let error as CoachingError {
            guard case .noAPIKey = error else {
                XCTFail("expected .noAPIKey, got \(error)")
                return
            }
        } catch {
            XCTFail("expected CoachingError, got \(error)")
        }
    }

    func testRequestBodyForcesStructuredToolChoice() throws {
        let data = try ClaudeCoach.makeRequestBody(model: "claude-opus-4-8", payloadJSON: "{}")
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["model"] as? String, "claude-opus-4-8")
        let toolChoice = obj?["tool_choice"] as? [String: Any]
        XCTAssertEqual(toolChoice?["type"] as? String, "tool")
        XCTAssertEqual(toolChoice?["name"] as? String, "emit_coaching_plan")
        let tools = obj?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.count, 1)
        XCTAssertEqual(tools?.first?["name"] as? String, "emit_coaching_plan")
        let messages = obj?["messages"] as? [[String: Any]]
        XCTAssertEqual(messages?.first?["content"] as? String, "{}")
    }

    func testParsesToolUseResponseIntoCoachingPlan() throws {
        let responseJSON = """
        {
          "content": [
            {"type": "text", "text": "..."},
            {
              "type": "tool_use",
              "name": "emit_coaching_plan",
              "input": {
                "verdict": "Compact and powerful — the shaft steepens slightly at the top.",
                "goals": [
                  {
                    "priority": 1, "title": "Shallow the shaft in transition",
                    "detail": "Feel the trail elbow lead down.",
                    "metricLabel": "Swing plane at P5", "current": "+4.2° steep", "target": "±1.5°",
                    "drill": "Pump drill", "drillDetail": "Pause at the top, drop hands to trail pocket."
                  }
                ]
              }
            }
          ]
        }
        """
        let plan = try ClaudeCoach.parsePlan(from: responseJSON.data(using: .utf8)!)
        XCTAssertEqual(plan.source, .claude)
        XCTAssertEqual(plan.goals.count, 1)
        XCTAssertEqual(plan.goals[0].title, "Shallow the shaft in transition")
        XCTAssertEqual(plan.goals[0].metricLabel, "Swing plane at P5")
    }

    func testMissingToolUseBlockThrowsMalformedResponse() {
        let responseJSON = #"{"content": [{"type": "text", "text": "no tool use here"}]}"#
        XCTAssertThrowsError(try ClaudeCoach.parsePlan(from: responseJSON.data(using: .utf8)!)) { error in
            guard case CoachingError.malformedResponse = error else {
                XCTFail("expected .malformedResponse, got \(error)")
                return
            }
        }
    }
}

enum CoachingRuleBasedTestsSupport {
    static func minimalReport() -> SwingReport {
        SwingReport(
            club: "7 iron", view: .downTheLine, duration: 1.0, frameRate: 60,
            frames: [], checkpoints: [], plane: PlaneAnalysis(basePlaneAngle: 60, deviationByPosition: [:], stateByPosition: [:]),
            sequence: KinematicSequence(peaks: []),
            pelvisDOF: [:], chestDOF: [:], metrics: [], markers: [],
            score: SwingScore(total: 0, components: []))
    }
}
