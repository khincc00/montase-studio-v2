import AVFoundation
import CoreGraphics
import Foundation

/// Merender komposisi ke berkas MP4 lewat AVAssetReader dan AVAssetWriter.
/// Dengan jalur ini ukuran, codec, dan bitrate dikontrol penuh, dan frame yang dikirim sudah melewati compositor.
enum Transcoder {
    struct Settings {
        var size: CGSize
        var codec: AVVideoCodecType
        var bitrate: Int
        var frameRate: Int
    }

    enum TranscodeError: LocalizedError {
        case failed
        case cancelled

        var errorDescription: String? {
            switch self {
            case .failed: return "Ekspor gagal."
            case .cancelled: return "Ekspor dibatalkan."
            }
        }
    }

    /// Pasangan writer input dan reader output. Hanya diakses dari satu antrean dispatch per pasangan.
    private struct Pump: @unchecked Sendable {
        let input: AVAssetWriterInput
        let output: AVAssetReaderOutput
    }

    final class Session {
        private let reader: AVAssetReader
        private let writer: AVAssetWriter
        private let videoOutput: AVAssetReaderOutput?
        private let audioOutput: AVAssetReaderOutput?
        private let videoInput: AVAssetWriterInput?
        private let audioInput: AVAssetWriterInput?
        private let totalSeconds: Double

        fileprivate init(
            reader: AVAssetReader,
            writer: AVAssetWriter,
            videoOutput: AVAssetReaderOutput?,
            audioOutput: AVAssetReaderOutput?,
            videoInput: AVAssetWriterInput?,
            audioInput: AVAssetWriterInput?,
            totalSeconds: Double
        ) {
            self.reader = reader
            self.writer = writer
            self.videoOutput = videoOutput
            self.audioOutput = audioOutput
            self.videoInput = videoInput
            self.audioInput = audioInput
            self.totalSeconds = max(totalSeconds, 0.001)
        }

        /// Membatalkan pembacaan; `run` lalu melempar `cancelled` dan menghapus berkas parsial.
        func cancel() {
            reader.cancelReading()
        }

        func run(progress: @escaping (Double) -> Void) async throws {
            guard reader.startReading() else { throw reader.error ?? TranscodeError.failed }
            guard writer.startWriting() else { throw writer.error ?? TranscodeError.failed }
            writer.startSession(atSourceTime: .zero)

            let total = totalSeconds
            let videoQueue = DispatchQueue(label: "montase.transcode.video")
            let audioQueue = DispatchQueue(label: "montase.transcode.audio")

            // Pasangan input/output hanya dipakai dari antrean masing-masing; dibungkus agar aman dikirim ke task.
            let video = videoInput.flatMap { input in videoOutput.map { Pump(input: input, output: $0) } }
            let audio = audioInput.flatMap { input in audioOutput.map { Pump(input: input, output: $0) } }

            await withTaskGroup(of: Void.self) { group in
                if let video {
                    group.addTask {
                        await Session.pump(video.input, from: video.output, queue: videoQueue) { seconds in
                            progress(min(max(seconds / total, 0), 1))
                        }
                    }
                }
                if let audio {
                    group.addTask {
                        await Session.pump(audio.input, from: audio.output, queue: audioQueue) { _ in }
                    }
                }
            }

            if reader.status == .cancelled || reader.status == .failed {
                writer.cancelWriting()
                if reader.status == .cancelled { throw TranscodeError.cancelled }
                throw reader.error ?? TranscodeError.failed
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                writer.finishWriting { continuation.resume() }
            }
            if writer.status != .completed {
                throw writer.error ?? TranscodeError.failed
            }
            progress(1)
        }

        private static func pump(
            _ input: AVAssetWriterInput,
            from output: AVAssetReaderOutput,
            queue: DispatchQueue,
            onTime: @escaping (Double) -> Void
        ) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        guard let sample = output.copyNextSampleBuffer() else {
                            input.markAsFinished()
                            continuation.resume()
                            return
                        }
                        onTime(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
                        input.append(sample)
                    }
                }
            }
        }
    }

    static func makeSession(
        _ output: CompositionBuilder.Output,
        settings: Settings,
        to url: URL,
        totalSeconds: Double
    ) throws -> Session {
        try? FileManager.default.removeItem(at: url)

        let reader = try AVAssetReader(asset: output.composition)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        var videoOutput: AVAssetReaderOutput?
        var videoInput: AVAssetWriterInput?
        let videoTracks = output.composition.tracks(withMediaType: .video)
        if let videoComposition = output.videoComposition, !videoTracks.isEmpty {
            // YUV video-range: konversi range dilakukan di reader, sehingga encoder menerima data yang sesuai.
            // Mengirim BGRA full-range ke encoder membuat hasil ekspor lebih terang dan kontras (≈255/219).
            let readerOutput = AVAssetReaderVideoCompositionOutput(
                videoTracks: videoTracks,
                videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
            )
            readerOutput.videoComposition = videoComposition
            reader.add(readerOutput)

            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: settings.codec,
                AVVideoWidthKey: Int(settings.size.width),
                AVVideoHeightKey: Int(settings.size.height),
                AVVideoColorPropertiesKey: [
                    AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                    AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                    AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_601_4,
                ],
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: settings.bitrate,
                    AVVideoExpectedSourceFrameRateKey: settings.frameRate,
                    AVVideoMaxKeyFrameIntervalKey: settings.frameRate * 2,
                ],
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            videoOutput = readerOutput
            videoInput = input
        }

        var audioOutput: AVAssetReaderOutput?
        var audioInput: AVAssetWriterInput?
        let audioTracks = output.composition.tracks(withMediaType: .audio)
        if !audioTracks.isEmpty {
            let readerOutput = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ])
            readerOutput.audioMix = output.audioMix
            reader.add(readerOutput)

            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 2,
                AVSampleRateKey: 48_000,
                AVEncoderBitRateKey: 192_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioOutput = readerOutput
            audioInput = input
        }

        return Session(
            reader: reader,
            writer: writer,
            videoOutput: videoOutput,
            audioOutput: audioOutput,
            videoInput: videoInput,
            audioInput: audioInput,
            totalSeconds: totalSeconds
        )
    }
}
