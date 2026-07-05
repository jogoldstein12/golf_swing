import AVFoundation
import CoreMedia
import Foundation

public struct VideoPreflightLimits: Sendable, Equatable {
    public var minimumDuration: Double
    public var maximumDuration: Double

    public init(minimumDuration: Double = 0.5, maximumDuration: Double = 120) {
        self.minimumDuration = minimumDuration
        self.maximumDuration = maximumDuration
    }
}
public struct VideoPreflightMetadata: Codable, Sendable, Equatable {
    public var duration: Double
    public var nominalFPS: Double
    public var displayWidth: Int
    public var displayHeight: Int
    public var codec: String
    public var isHDR: Bool
    public var isReadable: Bool

    public init(duration: Double, nominalFPS: Double, displayWidth: Int,
                displayHeight: Int, codec: String, isHDR: Bool,
                isReadable: Bool = true) {
        self.duration = duration
        self.nominalFPS = nominalFPS
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
        self.codec = codec
        self.isHDR = isHDR
        self.isReadable = isReadable
    }
}

public enum VideoPreflightError: LocalizedError, Equatable, Sendable {
    case noVideoTrack
    case tooShort(actual: Double, minimum: Double)
    case tooLong(actual: Double, maximum: Double)
    case unsupportedCodec(String)
    case unreadable
    case invalidDimensions

    public var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            "That file does not contain a video track."
        case .tooShort:
            "That video is too short to contain a complete swing."
        case .tooLong(_, let maximum):
            "Choose a video under \(Int(maximum)) seconds, then trim it around one swing."
        case .unsupportedCodec(let codec):
            "The video codec (\(codec)) is not supported on this device."
        case .unreadable:
            "The video is not fully available or could not be read."
        case .invalidDimensions:
            "The video has invalid display dimensions."
        }
    }
}

public struct VideoPreflightService: Sendable {
    public var limits: VideoPreflightLimits

    public init(limits: VideoPreflightLimits = .init()) {
        self.limits = limits
    }

    public func inspect(url: URL) async throws -> VideoPreflightMetadata {
        try Task.checkCancellation()
        guard FileManager.default.fileExists(atPath: url.path),
              FileManager.default.isReadableFile(atPath: url.path)
        else { throw VideoPreflightError.unreadable }

        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isReadable) else {
            throw VideoPreflightError.unreadable
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoPreflightError.noVideoTrack
        }
        try Task.checkCancellation()

        let duration = try await asset.load(.duration).seconds
        let fps = Double(try await track.load(.nominalFrameRate))
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let displaySize = naturalSize.applying(transform)
        let descriptions = try await track.load(.formatDescriptions)
        let codec = descriptions.first.map { Self.fourCC(CMFormatDescriptionGetMediaSubType($0)) }
            ?? "unknown"
        let metadata = VideoPreflightMetadata(
            duration: duration,
            nominalFPS: max(0, fps),
            displayWidth: Int(abs(displaySize.width).rounded()),
            displayHeight: Int(abs(displaySize.height).rounded()),
            codec: codec,
            isHDR: descriptions.contains(where: Self.isHDR),
            isReadable: true
        )
        try Self.validate(metadata, limits: limits)
        return metadata
    }

    static func validate(_ metadata: VideoPreflightMetadata,
                         limits: VideoPreflightLimits) throws {
        guard metadata.isReadable, metadata.duration.isFinite else {
            throw VideoPreflightError.unreadable
        }
        guard metadata.displayWidth > 0, metadata.displayHeight > 0 else {
            throw VideoPreflightError.invalidDimensions
        }
        guard metadata.duration >= limits.minimumDuration else {
            throw VideoPreflightError.tooShort(
                actual: metadata.duration, minimum: limits.minimumDuration
            )
        }
        guard metadata.duration <= limits.maximumDuration else {
            throw VideoPreflightError.tooLong(
                actual: metadata.duration, maximum: limits.maximumDuration
            )
        }
        let supported = ["avc1", "avc3", "hvc1", "hev1", "mp4v", "ap4h", "ap4x", "apcn", "apcs", "apco"]
        guard supported.contains(metadata.codec.lowercased()) else {
            throw VideoPreflightError.unsupportedCodec(metadata.codec)
        }
    }

    private static func fourCC(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "unknown"
    }

    private static func isHDR(_ description: CMFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [String: Any] else {
            return false
        }
        let text = extensions.values.map { String(describing: $0).lowercased() }
            .joined(separator: " ")
        return text.contains("2020") || text.contains("hlg")
            || text.contains("smpte_st_2084") || text.contains("pq")
    }
}
