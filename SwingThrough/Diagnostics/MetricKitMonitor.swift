import Foundation
import MetricKit
import os

/// Receives Apple-provided crash, hang, CPU, and memory reports from prior launches.
/// Payloads stay in Application Support and never contain video or pose tracks.
final class MetricKitMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricKitMonitor()

    private let logger = Logger(subsystem: "com.swingthrough.SwingThrough", category: "MetricKit")
    private var started = false

    private override init() {
        super.init()
    }

    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "metrics")
        logger.log("received \(payloads.count, privacy: .public) metric payload(s)")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        persist(payloads.map { $0.jsonRepresentation() }, prefix: "diagnostics")
        logger.log("received \(payloads.count, privacy: .public) diagnostic payload(s)")
    }

    private func persist(_ payloads: [Data], prefix: String) {
        guard !payloads.isEmpty else { return }
        do {
            let directory = URL.applicationSupportDirectory
                .appendingPathComponent("Diagnostics/MetricKit", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (index, payload) in payloads.enumerated() {
                let stamp = Int(Date().timeIntervalSince1970)
                let url = directory.appendingPathComponent("\(prefix)-\(stamp)-\(index).json")
                try payload.write(to: url, options: .atomic)
            }
        } catch {
            logger.error("could not persist MetricKit payload category=\(prefix, privacy: .public)")
        }
    }
}
