// swingctl coach — runs coaching on a saved SwingReport JSON from the CLI, the way to validate
// the coaching layer without the app.
//
//   swingctl coach <report.json> [--skill beginner|intermediate|advanced] [--claude] [--write]
import Foundation
import SwingKit

func runCoach(_ args: [String]) -> Never {
    guard let reportPath = args.first, !reportPath.hasPrefix("--") else {
        die("usage: swingctl coach <report.json> [--skill beginner|intermediate|advanced] [--claude] [--write]")
    }
    let useClaude = args.contains("--claude")
    let shouldWrite = args.contains("--write")
    let skill = coachOpt(args, "--skill")

    let url = URL(fileURLWithPath: reportPath)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        die("couldn't read \(reportPath): \(error)")
    }

    var report: SwingReport
    do {
        report = try JSONDecoder().decode(SwingReport.self, from: data)
    } catch {
        die("couldn't decode SwingReport from \(reportPath): \(error)")
    }

    if useClaude, ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] == nil {
        die("--claude requires ANTHROPIC_API_KEY in the environment")
    }

    let context = CoachingContext(skillLevel: skill, club: report.club, recentGoalTitles: [])

    let sema = DispatchSemaphore(value: 0)
    var planResult: Result<CoachingPlan, Error>?
    Task {
        do {
            let plan: CoachingPlan
            if useClaude {
                plan = try await ClaudeCoach().coach(report, context: context)
            } else {
                plan = try await RuleBasedCoach().coach(report, context: context)
            }
            planResult = .success(plan)
        } catch {
            planResult = .failure(error)
        }
        sema.signal()
    }
    sema.wait()

    switch planResult {
    case .none:
        die("coaching produced no result")
    case .failure(let error):
        die("coaching failed: \(error)")
    case .success(let plan):
        printCoachingPlan(plan)
        if shouldWrite {
            report.coaching = plan
            do {
                let enc = JSONEncoder()
                enc.outputFormatting = [.sortedKeys, .prettyPrinted]
                let out = try enc.encode(report)
                try out.write(to: url)
                print("\nwrote coaching -> \(reportPath)")
            } catch {
                die("failed writing report: \(error)")
            }
        }
    }
    exit(0)
}

private func coachOpt(_ args: [String], _ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

private func printCoachingPlan(_ plan: CoachingPlan) {
    print("VERDICT  (source: \(plan.source.rawValue))")
    print("  \(plan.verdict)")
    print("")
    for goal in plan.goals.sorted(by: { $0.priority < $1.priority }) {
        print("[\(goal.priority)] \(goal.title)")
        if let cue = goal.cue { print("    ➤ \(cue)") }
        print("    \(goal.detail)")
        print("    \(goal.metricLabel): \(goal.current) -> \(goal.target)")
        print("    Drill: \(goal.drill) — \(goal.drillDetail)")
        print("")
    }
}
