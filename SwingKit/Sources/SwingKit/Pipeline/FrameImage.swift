// Grabs a single decoded frame from the source video as a CGImage, at the video's own
// preferred orientation — used by the swing-plane shaft/ball detector, which needs
// actual pixels (not just joint tracks), and by swingctl's annotated-frame renderer.
import AVFoundation
import CoreGraphics

enum FrameImage {
    static func cgImage(from url: URL, at time: Double) throws -> CGImage {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.requestedTimeToleranceBefore = .zero
        gen.requestedTimeToleranceAfter = .zero
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        return try gen.copyCGImage(at: cmTime, actualTime: nil)
    }

    /// Row-major 8-bit grayscale buffer of the image, top row first (matches our
    /// top-left-origin j2 contract directly — verified empirically against real
    /// address frames in VALIDATION.md: sky rows near index 0 read bright, ground
    /// rows near height-1 read as grass, matching the visual top/bottom).
    static func grayscale(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int)? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }
        let count = width * height
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: count)
        defer { buffer.deallocate() }
        buffer.initialize(repeating: 0, count: count)
        guard let ctx = CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let data = Array(UnsafeBufferPointer(start: buffer, count: count))
        return (data, width, height)
    }
}
