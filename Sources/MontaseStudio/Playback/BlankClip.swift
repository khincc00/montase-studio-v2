import AVFoundation
import CoreVideo
import Foundation

/// Klip hitam sementara. Dipakai sebagai sumber filler bila timeline hanya berisi teks (tanpa media video).
enum BlankClip {
    private static var cache: [String: URL] = [:]

    static func url(size: CGSize, seconds: Int = 1) async throws -> URL {
        let key = "\(Int(size.width))x\(Int(size.height))x\(seconds)"
        if let cached = cache[key], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseBlank-\(key).mp4")
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let frames = 30 * seconds
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pixelBuffer)
        if let buffer = pixelBuffer {
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        guard let buffer = pixelBuffer else { throw CocoaError(.fileWriteUnknown) }

        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(5))
            }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }

        cache[key] = url
        return url
    }
}
