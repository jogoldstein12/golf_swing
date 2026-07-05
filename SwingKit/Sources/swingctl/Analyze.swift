// swingctl analyze / trim — the accuracy-validation loop for the full measurement
// pipeline (as opposed to `extract`, which only exercises stage 1).
//
//   swingctl analyze <video> [--view dtl|faceon] [--json out.json]
//                    [--diagnostics diagnostics.json] [--annotate dir]
//   swingctl trim <video> <out> <start> <end>
import AVFoundation
import CoreGraphics
import CoreText
import Foundation
import SwingKit
import UniformTypeIdentifiers

func runAnalyze(_ args: [String]) -> Never {
    guard let videoPath = args.first, !videoPath.hasPrefix("--") else {
        die("usage: swingctl analyze <video> [--view dtl|faceon] [--json out.json] [--diagnostics diagnostics.json] [--annotate dir]")
    }
    func localOpt(_ name: String) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    let videoURL = URL(fileURLWithPath: videoPath)
    let view: CaptureView = (localOpt("--view") ?? "dtl") == "faceon" ? .faceOn : .downTheLine
    let jsonPath = localOpt("--json")
    let diagnosticsPath = localOpt("--diagnostics")
    let annotateDir = localOpt("--annotate")

    let sema = DispatchSemaphore(value: 0)
    var analysisResult: Result<SwingAnalysisResult, Error>?
    Task {
        do {
            let result = try await SwingAnalyzer.analyzeWithDiagnostics(
                url: videoURL,
                view: view,
                progress: { p in
                    let text = String(format: "\r%3.0f%%", p * 100)
                    if let data = text.data(using: .utf8) {
                        FileHandle.standardError.write(data)
                    }
                }
            )
            analysisResult = .success(result)
        } catch {
            analysisResult = .failure(error)
        }
        sema.signal()
    }
    sema.wait()
    if let data = "\r".data(using: .utf8) {
        FileHandle.standardError.write(data)
    }

    guard let analysisResult else { die("analyze produced no result") }
    let result: SwingAnalysisResult
    switch analysisResult {
    case .failure(let error):
        if let diagnosticsPath, let failure = error as? SwingAnalysisFailure {
            writeDiagnostics(failure.diagnostics, to: diagnosticsPath)
        }
        die("analyze failed: \(error.localizedDescription)")
    case .success(let value):
        result = value
    }
    let report = result.report

    if let diagnosticsPath {
        writeDiagnostics(result.diagnostics, to: diagnosticsPath)
    }

    printAnalysisSummary(report, videoName: videoURL.lastPathComponent)

    if let jsonPath {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try enc.encode(report).write(to: URL(fileURLWithPath: jsonPath))
            print("\nreport -> \(jsonPath)")
        } catch { die("failed writing report json: \(error)") }
    }

    if let annotateDir {
        do {
            try annotateCheckpoints(video: videoURL, report: report, outDir: annotateDir)
        } catch { die("annotate failed: \(error)") }
    }
    exit(0)
}

private func writeDiagnostics(_ diagnostics: AnalysisDiagnostics, to path: String) {
    do {
        try diagnostics.exportedJSON().write(to: URL(fileURLWithPath: path), options: .atomic)
        print("\ndiagnostics -> \(path)")
    } catch {
        die("failed writing diagnostics json: \(error)")
    }
}

func runTrim(_ args: [String]) -> Never {
    guard args.count >= 4, let start = Double(args[2]), let end = Double(args[3]) else {
        die("usage: swingctl trim <video> <out> <start> <end>")
    }
    let inURL = URL(fileURLWithPath: args[0])
    let outURL = URL(fileURLWithPath: args[1])
    if FileManager.default.fileExists(atPath: outURL.path) {
        try? FileManager.default.removeItem(at: outURL)
    }
    let asset = AVURLAsset(url: inURL)
    guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
        die("couldn't create export session")
    }
    export.outputURL = outURL
    export.outputFileType = .mp4
    export.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600),
                                   end: CMTime(seconds: end, preferredTimescale: 600))
    let sema = DispatchSemaphore(value: 0)
    export.exportAsynchronously { sema.signal() }
    sema.wait()
    if export.status == .completed {
        print("trimmed -> \(outURL.path)")
        exit(0)
    }
    die("export failed: \(export.error?.localizedDescription ?? "unknown error")")
}

// MARK: - Summary

private func printAnalysisSummary(_ report: SwingReport, videoName: String) {
    print("\(videoName)  view=\(report.view.rawValue)  handedness=\(report.handedness?.rawValue ?? "?")")
    print(String(format: "window %.2fs - %.2fs   frames analyzed: %d   score: %d/100",
                 report.windowStart ?? 0, report.windowEnd ?? report.duration,
                 report.frames.count, report.score.total))

    print("\nCHECKPOINTS")
    for mark in report.checkpoints {
        print(String(format: "  %-4@ %-18@ t=%6.3fs  frame#%d",
                     mark.position.shortName, mark.position.name, mark.time, mark.frameIndex))
    }

    print("\nMETRICS")
    for m in report.metrics {
        print(String(format: "  %-30@ %8.2f%-3@  ideal[%.1f, %.1f]  %@",
                     m.label, m.value, m.unit, m.idealLow, m.idealHigh, m.inBand ? "OK" : "--"))
    }

    print("\nKINEMATIC SEQUENCE  (ideal order: pelvis -> torso -> leadArm -> club)")
    for p in report.sequence.peaks.sorted(by: { $0.time < $1.time }) {
        print(String(format: "  %-10@ t=%6.3fs  peak=%8.1f", p.segment.rawValue, p.time, p.peakDegPerSec))
    }
    print("  in order: \(report.sequence.peaks.count == 4 && report.sequence.isInOrder ? "YES" : "NO")"
          + (report.sequence.lowConfidence == true ? "  (LOW CONFIDENCE - orientation untrusted in downswing)" : ""))

    print("\nSCORE")
    for c in report.score.components {
        print(String(format: "  %-14@ %4.2f  (weight %.0f%%)", c.label, c.score, c.weight * 100))
    }
    print(String(format: "  TOTAL %d/100", report.score.total))

    print("\nPLANE")
    if let basis = report.plane.basis {
        var line = String(format: "  basis=%@  baseAngle=%.1f°", basis.rawValue, report.plane.basePlaneAngle)
        if let shift = report.plane.planeShift3D { line += String(format: "  3D-cross-check=%.1f°", shift) }
        print(line)
        for (pos, dev) in report.plane.deviationByPosition.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let state = report.plane.stateByPosition[pos]?.rawValue ?? "?"
            print(String(format: "  %@ deviation %.1f° (%@)", pos.shortName, dev, state))
        }
    } else {
        print("  unavailable — shaft and grip->ball detection both failed their quality gates")
    }

    if !report.markers.isEmpty {
        print("\nMARKERS")
        for m in report.markers {
            print("  [\(m.kind.rawValue)] \(m.position.shortName) \(m.joint.rawValue): \(m.title) — \(m.detail)")
        }
    }
}

// MARK: - Annotated checkpoint frames

/// Renders the source frame at each checkpoint with the tracked skeleton, base plane
/// line (down-the-line), grip's P4->P7 path, and a burned-in label — the visual
/// evidence for docs/VALIDATION.md.
private func annotateCheckpoints(video: URL, report: SwingReport, outDir: String) throws {
    let asset = AVURLAsset(url: video)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    let p4 = report.mark(.p4), p7 = report.mark(.p7)

    for mark in report.checkpoints {
        guard let frame = report.frame(at: mark.time) else { continue }
        let time = CMTime(seconds: mark.time, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { continue }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { continue }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // CG origin is bottom-left; contract j2 is top-left. Flip y when drawing.
        func pt(_ p: SIMD2<Double>) -> CGPoint { CGPoint(x: p.x * Double(w), y: (1 - p.y) * Double(h)) }
        let unit = Double(min(w, h))

        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(srgbRed: 0.98, green: 0.95, blue: 0.9, alpha: 0.9))
        ctx.setLineWidth(unit * 0.004)
        for (a, b) in Bones.all {
            guard let pa = frame.j2[a], let pb = frame.j2[b] else { continue }
            ctx.move(to: pt(pa)); ctx.addLine(to: pt(pb))
        }
        ctx.strokePath()
        ctx.setFillColor(CGColor(srgbRed: 0.7, green: 0.88, blue: 0.1, alpha: 0.95))
        for (_, p) in frame.j2 {
            let c = pt(p); let r = unit * 0.006
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        if let grip = frame.grip2 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.15, alpha: 0.95))
            let c = pt(grip); let r = unit * 0.009
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }

        // Base plane line (down-the-line only; absent honestly when unavailable).
        if let line = report.plane.basePlaneLine2D, line.count == 2 {
            ctx.setStrokeColor(CGColor(srgbRed: 0.3, green: 0.9, blue: 0.55, alpha: 0.85))
            ctx.setLineWidth(unit * 0.0028)
            ctx.move(to: pt(line[0])); ctx.addLine(to: pt(line[1]))
            ctx.strokePath()
        }

        // Grip's downswing path, P4 -> P7.
        if let p4, let p7 {
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.6, blue: 0.1, alpha: 0.85))
            ctx.setLineWidth(unit * 0.0022)
            var started = false
            for f in report.frames where f.time >= p4.time && f.time <= p7.time {
                guard let g = f.grip2 else { continue }
                let c = pt(g)
                if !started { ctx.move(to: c); started = true } else { ctx.addLine(to: c) }
            }
            if started { ctx.strokePath() }
        }

        drawLabel(labelText(for: mark, report: report), in: ctx, width: w, height: h)

        guard let out = ctx.makeImage() else { continue }
        let name = String(format: "%@_t%07.3f.png", mark.position.shortName, mark.time)
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { continue }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }
    print("annotated checkpoint frames -> \(outDir)")
}

private func labelText(for mark: CheckpointMark, report: SwingReport) -> String {
    var s = String(format: "%@ · %@ · t=%.2fs", mark.position.shortName, mark.position.name, mark.time)
    if mark.position == .p4, let dev = report.plane.deviationByPosition[.p5] {
        s += String(format: "  ·  plane %.1f° at P5", dev)
    }
    if mark.position == .p7, let dev = report.plane.deviationByPosition[.p6] {
        s += String(format: "  ·  plane %.1f° at P6", dev)
    }
    if let turn = report.chestDOF[mark.position]?.turn { s += String(format: "  ·  shoulder %.0f°", abs(turn)) }
    if let turn = report.pelvisDOF[mark.position]?.turn { s += String(format: "  ·  hip %.0f°", abs(turn)) }
    return s
}

/// Draws `text` as a banner across the top of the image. The context here is
/// standard (unflipped) Quartz — origin bottom-left, y up — which is exactly what
/// CoreText expects natively, so no extra text-matrix flip is needed (only the
/// skeleton points need the manual y-flip, via `pt()` above, since those come from
/// our top-left-origin j2 contract).
private func drawLabel(_ text: String, in ctx: CGContext, width: Int, height: Int) {
    let fontSize = CGFloat(max(16, Double(min(width, height)) * 0.024))
    let font = CTFontCreateWithName("Menlo-Bold" as CFString, fontSize, nil)
    let color = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
    let attrString = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
    let line = CTLineCreateWithAttributedString(attrString)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    let pad = fontSize * 0.7
    let boxHeight = bounds.height + pad * 2
    let boxTop = CGFloat(height)
    ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
    ctx.fill(CGRect(x: 0, y: boxTop - boxHeight, width: CGFloat(width), height: boxHeight))
    ctx.textPosition = CGPoint(x: pad, y: boxTop - boxHeight + pad - bounds.origin.y)
    CTLineDraw(line, ctx)
}
