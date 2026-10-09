import AVFoundation
import CoreGraphics
import Foundation

/// Membaca metadata media dan membuat thumbnail. Tidak menyalin atau mengubah file asli.
enum MediaImporter {
    enum ImportError: LocalizedError {
        case noPlayableStreams(String)

        var errorDescription: String? {
            switch self {
            case .noPlayableStreams(let name):
                return "\(name) tidak berisi video atau audio yang bisa diputar."
            }
        }
    }

    static func probe(_ url: URL) async throws -> MediaItem {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard duration.isNumeric, duration.seconds > 0, !(videoTracks.isEmpty && audioTracks.isEmpty) else {
            throw ImportError.noPlayableStreams(url.lastPathComponent)
        }

        var width = 0
        var height = 0
        if let video = videoTracks.first {
            let natural = try await video.load(.naturalSize)
            let preferred = try await video.load(.preferredTransform)
            // Ukuran setelah rotasi, agar video ponsel portrait terbaca benar.
            let oriented = CGRect(origin: .zero, size: natural).applying(preferred)
            width = Int(abs(oriented.width).rounded())
            height = Int(abs(oriented.height).rounded())
        }

        return MediaItem(
            name: url.deletingPathExtension().lastPathComponent,
            path: url.path,
            duration: Ticks(seconds: duration.seconds),
            hasVideo: !videoTracks.isEmpty,
            hasAudio: !audioTracks.isEmpty,
            width: width,
            height: height
        )
    }

    static func thumbnail(for item: MediaItem) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 180)
        let time = CMTime(seconds: min(1, item.duration.seconds / 2), preferredTimescale: 600)
        return try? await generator.image(at: time).image
    }
}
