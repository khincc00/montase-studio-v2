import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MontaseStudio

/// Uji end-to-end dengan media nyata yang dibuat ffmpeg. Dilewati jika ffmpeg tidak terpasang.
@MainActor
final class PipelineIntegrationTests: XCTestCase {
    private var workDir: URL!
    private var ffmpegPath: String?

    override func setUp() async throws {
        ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipUnless(ffmpegPath != nil, "ffmpeg tidak ditemukan; uji integrasi dilewati")

        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseIT-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    private func ffmpeg(_ arguments: [String]) throws -> URL {
        let output = workDir.appendingPathComponent(UUID().uuidString + ".mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath!)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y"] + arguments + [output.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "ffmpeg gagal membuat media uji")
        return output
    }

    private func makeLandscape() throws -> URL {
        try ffmpeg(["-f", "lavfi", "-i", "testsrc=size=1920x1080:rate=30", "-f", "lavfi", "-i", "sine=frequency=440",
                    "-t", "3", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest"])
    }

    private func makePortrait() throws -> URL {
        try ffmpeg(["-f", "lavfi", "-i", "testsrc=size=720x1280:rate=30", "-f", "lavfi", "-i", "sine=frequency=880",
                    "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest"])
    }

    private func makeMusic() throws -> URL {
        try ffmpeg(["-f", "lavfi", "-i", "sine=frequency=330", "-t", "3", "-c:a", "aac"])
    }

    private func makeUHD() throws -> URL {
        try ffmpeg(["-f", "lavfi", "-i", "testsrc=size=3840x2160:rate=30", "-t", "1", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", "-an"])
    }

    /// Menyimpan frame untuk diperiksa secara visual. Lokasinya dicetak agar mudah dibuka.
    private func saveFrame(_ asset: AVAsset, seconds: Double, name: String) async throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseIT-frames/\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        print("FRAME \(name): \(url.path)")
    }

    // MARK: - Ekspor lengkap: transform, crop, warna, teks, fade, speed, EQ, portrait HEVC

    func testExportPortraitHEVCWithEffectsStack() async throws {
        let landscapeItem = try await MediaImporter.probe(makeLandscape())
        let portraitItem = try await MediaImporter.probe(makePortrait())
        let musicItem = try await MediaImporter.probe(makeMusic())

        var project = Project()
        let landscape = project.registerMedia(landscapeItem)
        let portrait = project.registerMedia(portraitItem)
        let music = project.registerMedia(musicItem)
        let v1 = project.tracks[1].id
        let v2 = project.tracks[0].id
        let a1 = project.tracks[2].id

        let base = try XCTUnwrap(project.addClip(mediaID: landscape.id, toTrack: v1, at: .zero))
        XCTAssertTrue(project.setSpeed(clipID: base, speed: 2)) // 3 s sumber → 1.5 s timeline

        let overlay = try XCTUnwrap(project.addClip(mediaID: portrait.id, toTrack: v2, at: Ticks(seconds: 0.5)))
        project.updateClip(id: overlay) {
            $0.transform.scale = 0.8
            $0.transform.rotation = 15
            $0.transform.cropTop = 0.1
            $0.grade.exposure = 0.5
            $0.grade.saturation = 0.3
            $0.fadeOut = Ticks(seconds: 0.5)
        }
        let title = try XCTUnwrap(project.addTitle(TitleStyle(text: "Halo Dunia"), toTrack: v2, at: Ticks(seconds: 2.5), duration: Ticks(seconds: 1.5)))
        XCTAssertNotNil(project.clip(id: title))
        _ = try XCTUnwrap(project.addClip(mediaID: music.id, toTrack: a1, at: .zero))
        project.updateTrack(id: a1) { $0.eq.high = 6; $0.volume = 0.8 }
        project.addMarker(at: Ticks(seconds: 1), name: "Tengah")


        let exporter = ExportController()
        exporter.settings = ExportSettings(resolution: .hd, orientation: .portrait, codec: .hevc)
        let output = workDir.appendingPathComponent("portrait.mp4")
        await exporter.export(project, to: output)
        XCTAssertNil(exporter.lastError, exporter.lastError ?? "")
        XCTAssertEqual(exporter.progress, 1, accuracy: 0.001)

        let exported = AVURLAsset(url: output)
        let duration = try await exported.load(.duration).seconds
        let videoTracks = try await exported.loadTracks(withMediaType: .video)
        let video = try XCTUnwrap(videoTracks.first)
        let size = try await video.load(.naturalSize)
        XCTAssertEqual(duration, project.duration.seconds, accuracy: 0.15)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
        let audioTracks = try await exported.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)

        // Frame: 0.25 s (hanya landscape cepat), 1.0 s (portrait di atas landscape), 3.0 s (teks saja).
        try await saveFrame(exported, seconds: 0.25, name: "portrait-0.25")
        try await saveFrame(exported, seconds: 1.0, name: "portrait-1.0")
        try await saveFrame(exported, seconds: 3.0, name: "portrait-3.0")
    }

    // MARK: - Ekspor landscape H.264 dengan Sebelum/Sesudah

    func testOriginalModeBypassesEffects() async throws {
        let item = try await MediaImporter.probe(makePortrait())
        var project = Project()
        let media = project.registerMedia(item)
        let track = project.tracks[1].id
        let clipID = try XCTUnwrap(project.addClip(mediaID: media.id, toTrack: track, at: .zero))
        project.updateClip(id: clipID) { $0.grade.exposure = 3; $0.transform.scale = 0.5 }

        let graded = try await CompositionBuilder.build(project: project, options: .init(renderSize: CGSize(width: 1920, height: 1080)))
        let original = try await CompositionBuilder.build(
            project: project,
            options: .init(renderSize: CGSize(width: 1920, height: 1080), applyEffects: false)
        )

        XCTAssertNotNil(graded.videoComposition)
        XCTAssertNotNil(original.videoComposition)
        XCTAssertEqual(graded.skippedClipCount, 0)
        let layers = original.videoComposition?.instructions.compactMap { ($0 as? EffectInstruction)?.layers.first }
        XCTAssertEqual(layers?.first?.grade, ColorGrade())
        XCTAssertEqual(layers?.first?.opacity, 1)
    }

    // MARK: - Timeline hanya teks

    func testTitleOnlyTimelineExportsWithText() async throws {
        var project = Project()
        let track = try XCTUnwrap(project.topVideoTrackID())
        var style = TitleStyle(text: "TEKS SAJA")
        style.fontSize = 120
        _ = try XCTUnwrap(project.addTitle(style, toTrack: track, at: .zero, duration: Ticks(seconds: 2)))

        let exporter = ExportController()
        exporter.settings = ExportSettings(resolution: .hd, orientation: .landscape, codec: .h264)
        let output = workDir.appendingPathComponent("title-only.mp4")
        await exporter.export(project, to: output)
        XCTAssertNil(exporter.lastError, exporter.lastError ?? "")

        let asset = AVURLAsset(url: output)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.15)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        let bright = brightPixelRatio(frame)
        XCTAssertGreaterThan(bright, 0.001, "teks tidak terlihat di frame export")
    }

    /// Porsi piksel terang pada gambar; teks putih di latar hitam menghasilkan porsi kecil tetapi nyata.
    private func brightPixelRatio(_ image: CGImage) -> Double {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return Double(pixels.filter { $0 > 200 }.count) / Double(pixels.count)
    }

    // MARK: - Pengukuran performa ekspor

    func testExportThroughputMeasurement() async throws {
        let item = try await MediaImporter.probe(makeLandscape())
        var project = Project()
        let media = project.registerMedia(item)
        let v1 = project.tracks[1].id
        let v2 = project.tracks[0].id
        // 10 klip di V1 + 10 overlay di V2 (total timeline 30 s), dengan efek ringan pada overlay.
        for index in 0..<10 {
            let start = Ticks(seconds: Double(index) * 3)
            _ = project.addClip(mediaID: media.id, toTrack: v1, at: start)
            let overlay = try XCTUnwrap(project.addClip(mediaID: media.id, toTrack: v2, at: start + Ticks(seconds: 1)))
            project.updateClip(id: overlay) { $0.transform.scale = 0.5; $0.grade.saturation = 1.2 }
        }

        let exporter = ExportController()
        exporter.settings = ExportSettings(resolution: .hd, orientation: .landscape, codec: .h264)
        let output = workDir.appendingPathComponent("throughput.mp4")
        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            await exporter.export(project, to: output)
        }
        XCTAssertNil(exporter.lastError, exporter.lastError ?? "")
        print("PERF export 1080p H.264, timeline \(project.duration.seconds) s, real time \(elapsed)")
    }

    // MARK: - Proxy untuk sumber 4K

    func testProxyIsGeneratedForUHDSource() async throws {
        let item = try await MediaImporter.probe(makeUHD())
        XCTAssertTrue(item.isLarge)

        let proxies = ProxyManager()
        proxies.request([item])
        var waited = 0
        while proxies.status(for: item) == .queued || isGenerating(proxies.status(for: item)), waited < 240 {
            try await Task.sleep(for: .milliseconds(250))
            waited += 1
        }

        XCTAssertEqual(proxies.status(for: item), .ready, "status: \(proxies.status(for: item))")
        let proxyURL = ProxyManager.url(for: item.id)
        defer { try? FileManager.default.removeItem(at: proxyURL) }

        let proxy = AVURLAsset(url: proxyURL)
        let proxyTracks = try await proxy.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(proxyTracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 960)
        XCTAssertEqual(size.width / size.height, 16.0 / 9.0, accuracy: 0.02)
    }

    private func isGenerating(_ status: ProxyManager.Status) -> Bool {
        if case .generating = status { return true }
        return false
    }
}
