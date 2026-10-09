import AVFoundation
import CoreGraphics
import Foundation
import Observation

enum ExportResolution: String, CaseIterable, Identifiable {
    case hd
    case uhd

    var id: String { rawValue }
    var title: String { self == .hd ? "1080p" : "4K" }
}

enum ExportOrientation: String, CaseIterable, Identifiable {
    case landscape
    case portrait
    case square

    var id: String { rawValue }
    var title: String {
        switch self {
        case .landscape: return "Landscape"
        case .portrait: return "Portrait"
        case .square: return "Square"
        }
    }
}

enum ExportCodec: String, CaseIterable, Identifiable {
    case h264
    case hevc

    var id: String { rawValue }
    var title: String { self == .h264 ? "H.264" : "HEVC" }
}

enum ExportQuality: String, CaseIterable, Identifiable {
    case standard
    case high

    var id: String { rawValue }
    var title: String { self == .standard ? "Standar" : "Tinggi" }
    /// Faktor terhadap bitrate dasar; file tinggi lebih besar tetapi detail gerak lebih terjaga.
    var multiplier: Double { self == .standard ? 1.0 : 1.6 }
}

struct ExportSettings: Equatable {
    var resolution: ExportResolution = .hd
    var orientation: ExportOrientation = .landscape
    var codec: ExportCodec = .h264
    var quality: ExportQuality = .standard

    var size: CGSize {
        let long: CGFloat = resolution == .hd ? 1920 : 3840
        let short: CGFloat = resolution == .hd ? 1080 : 2160
        switch orientation {
        case .landscape: return CGSize(width: long, height: short)
        case .portrait: return CGSize(width: short, height: long)
        case .square: return CGSize(width: short, height: short)
        }
    }

    /// Bitrate target. HEVC membutuhkan sekitar dua pertiga bitrate H.264 untuk kualitas setara.
    var bitrate: Int {
        let base = Double(resolution == .hd ? 12_000_000 : 40_000_000) * quality.multiplier
        return Int(codec == .hevc ? base * 2 / 3 : base)
    }

    var videoCodec: AVVideoCodecType { codec == .h264 ? .h264 : .hevc }

    func estimatedMegabytes(duration: Ticks) -> Double {
        Double(bitrate) * duration.seconds / 8 / 1_000_000
    }
}

@MainActor
@Observable
final class ExportController {
    var settings = ExportSettings()
    private(set) var isRunning = false
    private(set) var progress = 0.0
    private(set) var lastError: String?
    private(set) var lastOutputURL: URL?

    @ObservationIgnored private var session: Transcoder.Session?

    func export(_ project: Project, to url: URL) async {
        isRunning = true
        progress = 0
        lastError = nil
        defer {
            isRunning = false
            session = nil
        }

        do {
            let size = settings.size
            let output = try await CompositionBuilder.build(
                project: project,
                options: .init(renderSize: size, frameRate: project.sequence.frameRate)
            )
            let transcoder = try Transcoder.makeSession(
                output,
                settings: .init(
                    size: size,
                    codec: settings.videoCodec,
                    bitrate: settings.bitrate,
                    frameRate: project.sequence.frameRate
                ),
                to: url,
                totalSeconds: project.duration.seconds
            )
            session = transcoder
            try await transcoder.run { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            lastOutputURL = url
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancel() {
        session?.cancel()
    }
}
