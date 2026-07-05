// Merges a down-the-line pass and a face-on pass of the same swing into one report.
//
// Merge rules:
//  - Everything else (frames, checkpoints, handedness, plane, tempo, sequence, turn/
//    bend/sideBend, thrust) comes from the DTL pass. Plane is DTL-exclusive by
//    definition (down-the-line is the only view it's measured from). Turn/bend/
//    sideBend/sequence are body-relative 3D quantities that are equally valid from
//    either single view in principle, so we keep one canonical source rather than
//    average two independently-noisy estimates. Thrust is the translational axis
//    DTL's own camera geometry actually observes (see SixDOFAnalyzer.swift).
//  - Sway (pelvis/chest, at every checkpoint) is overwritten from the face-on pass —
//    the one axis DTL's camera geometry forshortens away and can't measure at all.
//  - Metrics/score are rebuilt to include face-on's "Pelvis Sway" (DTL alone never
//    produces that metric — see MetricsBuilder, which gates it on view) alongside
//    DTL's own metrics, so the fused score reflects the complete picture.
import Foundation

extension SwingReport {
    public static func fused(dtl: SwingReport, faceOn: SwingReport) -> SwingReport {
        var merged = dtl
        merged.view = .fused

        func mergeSway(_ dtlDOF: [SwingPosition: SixDOF], _ faceOnDOF: [SwingPosition: SixDOF]) -> [SwingPosition: SixDOF] {
            var out = dtlDOF
            for pos in Array(out.keys) {
                if let faceOnSway = faceOnDOF[pos]?.sway { out[pos]?.sway = faceOnSway }
            }
            return out
        }
        merged.pelvisDOF = mergeSway(dtl.pelvisDOF, faceOn.pelvisDOF)
        merged.chestDOF = mergeSway(dtl.chestDOF, faceOn.chestDOF)

        var metrics = dtl.metrics
        if let swayMetric = faceOn.metrics.first(where: { $0.label == "Pelvis Sway" }) {
            metrics.append(swayMetric)
        }
        merged.metrics = metrics

        let inputs = MetricsBuilder.Inputs(
            view: .fused, frames: dtl.frames,
            timing: SwingTiming(checkpoints: dtl.checkpoints, handedness: dtl.handedness ?? .right,
                               tempoBackswingSeconds: 0, tempoDownswingSeconds: 0),
            plane: dtl.plane, pelvisDOF: merged.pelvisDOF, chestDOF: merged.chestDOF, sequence: dtl.sequence)
        let quality = MetricsBuilder.reportQuality(inputs)
        merged.quality = quality
        merged.schemaVersion = 2
        merged.score = MetricsBuilder.score(inputs, metrics: metrics, quality: quality)

        return merged
    }
}
