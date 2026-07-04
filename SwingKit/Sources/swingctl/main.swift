// swingctl — runs the SwingKit measurement pipeline on video files from the Mac CLI.
// The accuracy-validation loop: same code as the app, real sample swings in, hard
// numbers + annotated frames out.
//
//   swingctl extract <video> [--start s] [--end s] [--fps n] [--no3d]
//            [--json out.json] [--annotate dir [--every n]]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import SwingKit
import UniformTypeIdentifiers

func die(_ msg: String) -> Never {
    FileHandle.standardError.write(("swingctl: " + msg + "\n").data(using: .utf8)!)
    exit(1)
}

func opt(_ name: String) -> String? {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
    return a[i + 1]
}

let args = CommandLine.arguments
if args.count >= 2, args[1] == "coach" {
    runCoach(Array(args.dropFirst(2)))
}
if args.count >= 2, args[1] == "analyze" {
    runAnalyze(Array(args.dropFirst(2)))
}
if args.count >= 2, args[1] == "trim" {
    runTrim(Array(args.dropFirst(2)))
}
guard args.count >= 3, args[1] == "extract" else {
    print("usage: swingctl extract <video> [--start s --end s] [--fps n] [--no3d] [--json out] [--annotate dir --every n]")
    print("       swingctl analyze <video> [--view dtl|faceon] [--json out.json] [--annotate dir]")
    print("       swingctl trim <video> <out> <start> <end>")
    print("       swingctl coach <report.json> [--skill level] [--claude] [--write]")
    exit(64)
}
let videoURL = URL(fileURLWithPath: args[2])

var window: ClosedRange<Double>?
if let s = opt("--start"), let e = opt("--end"), let a = Double(s), let b = Double(e) {
    window = a...b
}
let options = PoseExtractor.Options(
    window: window,
    sampleFPS: opt("--fps").flatMap(Double.init),
    include3D: !args.contains("--no3d")
)

let sema = DispatchSemaphore(value: 0)
Task {
    do {
        let clock = ContinuousClock()
        var result: PoseExtractor.Result?
        let elapsed = try await clock.measure {
            result = try await PoseExtractor().extract(from: videoURL, options: options) { p in
                FileHandle.standardError.write(String(format: "\r%3.0f%%", p * 100).data(using: .utf8)!)
            }
        }
        guard let result else { die("no result") }
        FileHandle.standardError.write("\r".data(using: .utf8)!)
        let n3 = result.frames.filter { !$0.j3.isEmpty }.count
        let n2 = result.frames.filter { !$0.j2.isEmpty }.count
        print(String(format: "%@  %.1fs @ %.0ffps  %dx%d", videoURL.lastPathComponent,
                     result.duration, result.nativeFPS,
                     Int(result.videoSize.width), Int(result.videoSize.height)))
        print(String(format: "frames %d (2D %d, 3D %d)  wall %.1fs",
                     result.frames.count, n2, n3, elapsed.seconds))

        if let path = opt("--json") {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            try enc.encode(result.frames).write(to: URL(fileURLWithPath: path))
            print("tracks -> \(path)")
        }

        if let dir = opt("--annotate") {
            let every = opt("--every").flatMap(Int.init) ?? 5
            try annotate(video: videoURL, frames: result.frames, outDir: dir, every: every,
                         window: window)
        }
        exit(0)
    } catch { die("\(error)") }
}
sema.wait()

/// Draw the tracked 2D skeleton onto sampled video frames for visual verification.
func annotate(video: URL, frames: [PoseFrame], outDir: String, every: Int,
              window: ClosedRange<Double>?) throws {
    let asset = AVURLAsset(url: video)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .zero
    try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

    for (i, frame) in frames.enumerated() where i % every == 0 {
        let time = CMTime(seconds: frame.time, preferredTimescale: 600)
        guard let cg = try? gen.copyCGImage(at: time, actualTime: nil) else { continue }
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { continue }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        // CG origin is bottom-left; contract j2 is top-left. Flip y when drawing.
        func pt(_ p: SIMD2<Double>) -> CGPoint {
            CGPoint(x: p.x * Double(w), y: (1 - p.y) * Double(h))
        }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setStrokeColor(CGColor(srgbRed: 0.98, green: 0.95, blue: 0.9, alpha: 0.9))
        ctx.setLineWidth(Double(min(w, h)) * 0.004)
        for (a, b) in Bones.all {
            guard let pa = frame.j2[a], let pb = frame.j2[b] else { continue }
            ctx.move(to: pt(pa)); ctx.addLine(to: pt(pb))
        }
        ctx.strokePath()
        ctx.setFillColor(CGColor(srgbRed: 0.7, green: 0.88, blue: 0.1, alpha: 0.95))
        for (_, p) in frame.j2 {
            let c = pt(p)
            let r = Double(min(w, h)) * 0.006
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }
        if let grip = frame.grip2 {
            ctx.setFillColor(CGColor(srgbRed: 1, green: 0.3, blue: 0.15, alpha: 0.95))
            let c = pt(grip)
            let r = Double(min(w, h)) * 0.009
            ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        }

        guard let out = ctx.makeImage() else { continue }
        let name = String(format: "t%07.3f.png", frame.time)
        let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { continue }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }
    print("annotated frames -> \(outDir)")
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) * 1e-18 }
}
