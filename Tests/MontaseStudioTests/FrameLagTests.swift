import AVFoundation
import CoreGraphics
import XCTest
@testable import MontaseStudio

/// Mengukur lag frame: media uji menyandikan nomor frame di luminansinya, sehingga selisih
/// nomor frame file export dan composition pada waktu yang sama langsung terlihat.
@MainActor
final class FrameLagTests: XCTestCase {
    private var ffmpegPath: String?
    private var workDir: URL!

    override func setUp() async throws {
        ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipUnless(ffmpegPath != nil, "ffmpeg tidak ditemukan")
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseLag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    /// Setiap frame ke-n memiliki luminansi n mod 256 (30 fps).
    private func makeIndexedClip(seconds: Int) throws -> URL {
        let output = workDir.appendingPathComponent("index.mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath!)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y",
                             "-f", "lavfi", "-i", "color=c=black:s=320x240:r=30:d=\(seconds),geq=lum='16+mod(floor(T*30)\\,200)':cb=128:cr=128",
                             "-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv420p", output.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return output
    }

    private func meanLuma(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let space = CGColorSpaceCreateDeviceGray()
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count)
    }

    /// Nomor frame dari luminansi rata-rata; 16 adalah offset limited-range.
    private func frameIndex(_ luma: Double) -> Int { Int((luma - 16).rounded()) }

    /// Membandingkan nomor frame export vs composition pada beberapa waktu. Mengembalikan selisih per waktu.
    private var sourceGenerator: AVAssetImageGenerator?

    private func measure(_ project: Project, times: [Double]) async throws -> [(Double, Int, Int)] {
        let size = CGSize(width: 320, height: 240)
        let output = try await CompositionBuilder.build(project: project, options: .init(renderSize: size))
        let file = workDir.appendingPathComponent("export-\(UUID().uuidString).mp4")
        let session = try Transcoder.makeSession(output, settings: .init(size: size, codec: .h264, bitrate: 4_000_000, frameRate: 30), to: file, totalSeconds: project.duration.seconds)
        try await session.run { _ in }

        let composed = AVAssetImageGenerator(asset: output.composition)
        composed.videoComposition = output.videoComposition
        composed.requestedTimeToleranceBefore = .zero
        composed.requestedTimeToleranceAfter = .zero
        let exported = AVAssetImageGenerator(asset: AVURLAsset(url: file))
        exported.requestedTimeToleranceBefore = .zero
        exported.requestedTimeToleranceAfter = .zero

        var rows: [(Double, Int, Int)] = []
        for t in times {
            let time = CMTime(seconds: t, preferredTimescale: 600)
            let e = try await exported.image(at: time).image
            let c = try await composed.image(at: time).image
            rows.append((t, frameIndex(meanLuma(e)), frameIndex(meanLuma(c))))
        }
        return rows
    }

    func testExportMatchesCompositionFrameForFrame() async throws {
        let clip = try makeIndexedClip(seconds: 4)
        let item = try await MediaImporter.probe(clip)
        sourceGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: clip))
        sourceGenerator?.requestedTimeToleranceBefore = .zero
        sourceGenerator?.requestedTimeToleranceAfter = .zero
        var project = Project()
        let media = project.registerMedia(item)
        _ = project.addClip(mediaID: media.id, toTrack: project.tracks[1].id, at: .zero)

        let rows = try await measure(project, times: [0.5, 1.0, 2.0, 3.0])
        for (t, e, c) in rows {
            XCTAssertEqual(e, c, accuracy: 1, "t=\(t)")
        }
    }

    func testExportMatchesCompositionWithDelayedOverlay() async throws {
        let clip = try makeIndexedClip(seconds: 4)
        let item = try await MediaImporter.probe(clip)
        var project = Project()
        let media = project.registerMedia(item)
        _ = project.addClip(mediaID: media.id, toTrack: project.tracks[1].id, at: .zero)
        _ = project.addClip(mediaID: media.id, toTrack: project.tracks[0].id, at: Ticks(seconds: 0.5))

        let rows = try await measure(project, times: [0.75, 1.0, 2.0, 3.0])
        for (t, e, c) in rows {
            XCTAssertEqual(e, c, accuracy: 1, "t=\(t)")
        }
    }
}
