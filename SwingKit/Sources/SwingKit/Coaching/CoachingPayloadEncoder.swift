// Produces the compact payload ClaudeCoach sends as the user message: measured data ONLY,
// with frames/tracks stripped (they're huge and irrelevant — the model reasons from numbers,
// never pixels). Deterministic and Equatable so it can be golden-file tested without a network
// call: same report + context in, byte-identical structure out.
import Foundation

public enum CoachingPayloadEncoder {

    public struct PositionValue: Codable, Equatable, Sendable {
        public let position: String
        public let time: Double
    }

    public struct PlanePoint: Codable, Equatable, Sendable {
        public let position: String
        public let deviationDeg: Double
        public let state: String
    }

    public struct SequencePeak: Codable, Equatable, Sendable {
        public let segment: String
        public let time: Double
        public let peakDegPerSec: Double
    }

    public struct SixDOFPayload: Codable, Equatable, Sendable {
        public let turn: Double
        public let bend: Double
        public let sideBend: Double
        public let sway: Double
        public let lift: Double
        public let thrust: Double

        public init(_ d: SixDOF) {
            turn = d.turn; bend = d.bend; sideBend = d.sideBend
            sway = d.sway; lift = d.lift; thrust = d.thrust
        }
    }

    public struct DOFEntry: Codable, Equatable, Sendable {
        public let position: String
        public let dof: SixDOFPayload
    }

    public struct MetricPayload: Codable, Equatable, Sendable {
        public let label: String
        public let value: Double
        public let unit: String
        public let idealLow: Double
        public let idealHigh: Double
        public let inBand: Bool
    }

    public struct ComponentPayload: Codable, Equatable, Sendable {
        public let label: String
        public let score: Double
        public let weight: Double
    }

    public struct ScorePayload: Codable, Equatable, Sendable {
        public let total: Int
        public let components: [ComponentPayload]
    }

    public struct ContextPayload: Codable, Equatable, Sendable {
        public let skillLevel: String?
        public let club: String?
        public let recentGoalTitles: [String]
    }

    public struct Payload: Codable, Equatable, Sendable {
        public let view: String
        public let club: String
        public let handedness: String?
        public let durationSeconds: Double
        public let checkpoints: [PositionValue]
        public let planeBasis: String?
        public let basePlaneAngle: Double
        public let planeShift3D: Double?
        public let plane: [PlanePoint]
        public let sequenceIdealOrder: [String]
        public let sequenceIsInOrder: Bool
        public let sequencePeaks: [SequencePeak]
        public let pelvisDOF: [DOFEntry]
        public let chestDOF: [DOFEntry]
        public let metrics: [MetricPayload]
        public let score: ScorePayload
        public let context: ContextPayload
    }

    public static func encode(report: SwingReport, context: CoachingContext) -> Payload {
        let checkpoints = report.checkpoints
            .sorted { $0.position < $1.position }
            .map { PositionValue(position: $0.position.shortName, time: $0.time) }

        let planePositions = Set(report.plane.deviationByPosition.keys)
            .union(report.plane.stateByPosition.keys)
            .sorted()
        let plane = planePositions.map { pos in
            PlanePoint(position: pos.shortName,
                       deviationDeg: report.plane.deviationByPosition[pos] ?? 0,
                       state: (report.plane.stateByPosition[pos] ?? .neutral).rawValue)
        }

        let sequencePeaks = report.sequence.peaks.map {
            SequencePeak(segment: $0.segment.rawValue, time: $0.time, peakDegPerSec: $0.peakDegPerSec)
        }

        func dofEntries(_ dof: [SwingPosition: SixDOF]) -> [DOFEntry] {
            dof.keys.sorted().compactMap { position in
                dof[position].map { DOFEntry(position: position.shortName, dof: SixDOFPayload($0)) }
            }
        }

        let metrics = report.metrics.map {
            MetricPayload(label: $0.label, value: $0.value, unit: $0.unit,
                          idealLow: $0.idealLow, idealHigh: $0.idealHigh, inBand: $0.inBand)
        }

        let score = ScorePayload(
            total: report.score.total,
            components: report.score.components.map { ComponentPayload(label: $0.label, score: $0.score, weight: $0.weight) })

        let ctx = ContextPayload(skillLevel: context.skillLevel, club: context.club,
                                 recentGoalTitles: context.recentGoalTitles)

        return Payload(
            view: report.view.rawValue,
            club: report.club,
            handedness: report.handedness?.rawValue,
            durationSeconds: report.duration,
            checkpoints: checkpoints,
            planeBasis: report.plane.basis?.rawValue,
            basePlaneAngle: report.plane.basePlaneAngle,
            planeShift3D: report.plane.planeShift3D,
            plane: plane,
            sequenceIdealOrder: report.sequence.idealOrder.map(\.rawValue),
            sequenceIsInOrder: report.sequence.isInOrder,
            sequencePeaks: sequencePeaks,
            pelvisDOF: dofEntries(report.pelvisDOF),
            chestDOF: dofEntries(report.chestDOF),
            metrics: metrics,
            score: score,
            context: ctx)
    }

    public static func encodeJSONData(report: SwingReport, context: CoachingContext) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(encode(report: report, context: context))
    }

    public static func encodeJSONString(report: SwingReport, context: CoachingContext) throws -> String {
        let data = try encodeJSONData(report: report, context: context)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
