import AVFoundation
import CoreImage
import XCTest
@testable import MontaseStudio

/// Satu frame terang (flash) di detik ke-1 pada sumber; posisi flash di export harus sama persis.
@MainActor
final class FlashTimingTests: XCTestCase {
    private var ffmpegPath: String?
    private var workDir: URL!

    override func setUp() async throws {
        ffmpegPath = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipUnless(ffmpegPath != nil, "ffmpeg tidak ditemukan")
        workDir = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseFlash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let workDir { try? FileManager.default.removeItem(at: workDir) }
    }

    private func makeFlashClip() throws -> URL {
        let output = workDir.appendingPathComponent("flash.mp4")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath!)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y",
                             "-f", "lavfi", "-i", "color=c=black:s=320x240:r=30:d=4,geq=lum='if(eq(floor(T*30)\\,30)\\,128\\,16)':cb=128:cr=128",
                             "-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv420p", output.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return output
    }

    /// Indeks frame (dalam urutan presentasi) yang paling terang.
    private func brightestFrame(of asset: AVAsset) async throws -> Int {
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        reader.add(output)
        reader.startReading()
        var best = -1
        var bestValue = -1.0
        var index = 0
        let context = CIContext()
        while let sample = output.copyNextSampleBuffer() {
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                let image = CIImage(cvPixelBuffer: buffer)
                let average = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])!
                var pixel = [UInt8](repeating: 0, count: 4)
                context.render(average.outputImage!, toBitmap: &pixel, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                let value = Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])
                if value > bestValue { bestValue = value; best = index }
            }
            index += 1
        }
        return best
    }

    func testFlashPositionMatchesAcrossSourceCompositionAndExport() async throws {
        let clip = try makeFlashClip()
        let item = try await MediaImporter.probe(clip)
        var project = Project()
        let media = project.registerMedia(item)
        _ = project.addClip(mediaID: media.id, toTrack: project.tracks[1].id, at: .zero)

        let source = try await brightestFrame(of: AVURLAsset(url: clip))
        let output = try await CompositionBuilder.build(project: project, options: .init(renderSize: CGSize(width: 320, height: 240)))
        let file = workDir.appendingPathComponent("export.mp4")
        let session = try Transcoder.makeSession(output, settings: .init(size: CGSize(width: 320, height: 240), codec: .h264, bitrate: 4_000_000, frameRate: 30), to: file, totalSeconds: 4)
        try await session.run { _ in }
        let exported = try await brightestFrame(of: AVURLAsset(url: file))

        print("FLASH source=\(source) export=\(exported)")
        // Jalur preview sebenarnya: AVPlayerItem dengan videoComposition, dibaca lewat AVPlayerItemVideoOutput.
        let previewItem = AVPlayerItem(asset: output.composition)
        previewItem.videoComposition = output.videoComposition
        let previewOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        previewItem.add(previewOutput)
        // Sumber mentah lewat AVPlayerItemVideoOutput (tanpa composition) sebagai pembanding.
        let rawItem = AVPlayerItem(asset: AVURLAsset(url: clip))
        let rawOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        rawItem.add(rawOutput)
        let rawPlayer = AVPlayer(playerItem: rawItem)
        let rawTarget = CMTime(seconds: 1.0, preferredTimescale: 600)
        await rawPlayer.seek(to: rawTarget, toleranceBefore: .zero, toleranceAfter: .zero)
        rawPlayer.play()
        var rawWaited = 0
        while !rawOutput.hasNewPixelBuffer(forItemTime: rawTarget), rawWaited < 40 {
            try await Task.sleep(for: .milliseconds(50))
            rawWaited += 1
        }
        rawPlayer.pause()
        if rawOutput.hasNewPixelBuffer(forItemTime: rawTarget), let raw = rawOutput.copyPixelBuffer(forItemTime: rawTarget, itemTimeForDisplay: nil) {
            let image = CIImage(cvPixelBuffer: raw)
            let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])!
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(avg.outputImage!, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            print("LEVEL rawplayer t=1.0 rgb=\(px[0]),\(px[1]),\(px[2])")
        }
        let player = AVPlayer(playerItem: previewItem)
        let target = CMTime(seconds: 1.0, preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        var waited = 0
        while !previewOutput.hasNewPixelBuffer(forItemTime: target), waited < 40 {
            try await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        player.pause()
        if previewOutput.hasNewPixelBuffer(forItemTime: target), let buffer = previewOutput.copyPixelBuffer(forItemTime: target, itemTimeForDisplay: nil) {
            let image = CIImage(cvPixelBuffer: buffer)
            let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: image, kCIInputExtentKey: CIVector(cgRect: image.extent)])!
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(avg.outputImage!, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            print("LEVEL preview t=1.0 rgb=\(px[0]),\(px[1]),\(px[2])")
        } else {
            print("LEVEL preview t=1.0 no buffer")
        }
        for (label, asset) in [("source", AVURLAsset(url: clip)), ("export", AVURLAsset(url: file))] {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            for t in [0.5, 1.0] {
                let img = try await gen.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
                let ci = CIImage(cgImage: img)
                let avg = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)])!
                var px = [UInt8](repeating: 0, count: 4)
                CIContext().render(avg.outputImage!, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
                print("LEVEL \(label) t=\(t) rgb=\(px[0]),\(px[1]),\(px[2])")
            }
        }
        XCTAssertEqual(exported, source, "flash bergeser \(exported - source) frame di export")
    }
}
