// frames — tiny AVFoundation frame extractor (ffmpeg stand-in for this repo).
// Usage:
//   frames <video> <outdir> --times 0.5,1.0,2.5        exact timestamps (s)
//   frames <video> <outdir> --fps 10 [--start s] [--end s] [--scale 0.5]
//   frames <video> <outdir> --info                     print duration/fps/size only
import AVFoundation
import AppKit

func die(_ msg: String) -> Never { FileHandle.standardError.write((msg + "\n").data(using: .utf8)!); exit(1) }

let args = CommandLine.arguments
guard args.count >= 3 else { die("usage: frames <video> <outdir> [--times a,b,c | --fps n | --info] [--start s] [--end s] [--scale f]") }
let url = URL(fileURLWithPath: args[1])
let outDir = URL(fileURLWithPath: args[2])

func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

let asset = AVURLAsset(url: url)
let sema = DispatchSemaphore(value: 0)
Task {
    do {
        let duration = try await asset.load(.duration).seconds
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { die("no video track") }
        let fps = try await track.load(.nominalFrameRate)
        let size = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displaySize = size.applying(transform)
        print(String(format: "duration %.3fs  fps %.2f  size %dx%d", duration, fps,
                     Int(abs(displaySize.width)), Int(abs(displaySize.height))))
        if args.contains("--info") { exit(0) }

        var times: [Double] = []
        if let t = opt("--times") {
            times = t.split(separator: ",").compactMap { Double($0) }
        } else if let f = opt("--fps"), let outFps = Double(f) {
            let start = Double(opt("--start") ?? "0") ?? 0
            let end = min(Double(opt("--end") ?? "\(duration)") ?? duration, duration)
            var t = start
            while t < end { times.append(t); t += 1.0 / outFps }
        } else { die("need --times, --fps, or --info") }

        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        if let s = opt("--scale"), let scale = Double(s) {
            gen.maximumSize = CGSize(width: abs(displaySize.width) * scale, height: abs(displaySize.height) * scale)
        }
        for (i, t) in times.enumerated() {
            let (image, actual) = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600))
            let rep = NSBitmapImageRep(cgImage: image)
            guard let png = rep.representation(using: .png, properties: [:]) else { die("png encode failed") }
            let name = String(format: "f%04d_%.3f.png", i, actual.seconds)
            try png.write(to: outDir.appendingPathComponent(name))
        }
        print("wrote \(times.count) frames -> \(outDir.path)")
        exit(0)
    } catch { die("error: \(error)") }
}
sema.wait()
