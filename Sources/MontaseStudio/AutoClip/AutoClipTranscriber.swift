import AVFoundation
import Foundation
import Speech

/// Transkripsi lokal: audio diambil dari media, lalu dikenali dengan Speech framework secara on-device.
/// Tidak ada audio atau teks yang dikirim ke layanan luar.
enum AutoClipTranscriber {
    enum TranscribeError: LocalizedError {
        case noAudio
        case unauthorized
        case unsupportedLanguage(String)
        case offlineUnavailable(String)
        case noSpeech
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noAudio:
                return "Media tidak punya track audio untuk ditranskripsi."
            case .unauthorized:
                return "Izin pengenalan suara ditolak. Aktifkan di Pengaturan Sistem > Privasi & Keamanan > Pengenalan Ucapan."
            case .unsupportedLanguage(let name):
                return "Pengenalan suara tidak tersedia untuk bahasa \(name) di Mac ini."
            case .offlineUnavailable(let name):
                return "Model pengenalan suara offline untuk \(name) belum terpasang. Unduh di Pengaturan Sistem > Keyboard > Dikte."
            case .noSpeech:
                return "Tidak ada ucapan yang terdeteksi di media ini."
            case .failed(let message):
                return "Transkripsi gagal: \(message)"
            }
        }
    }

    /// Meminta izin pengenalan suara saat aplikasi pertama dibuka. Hanya memicu dialog jika statusnya belum ditentukan.
    static func requestAuthorizationOnFirstLaunch() {
        guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
        SFSpeechRecognizer.requestAuthorization { _ in }
    }

    static func requestAuthorization() async throws {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return }
        let status: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw TranscribeError.unauthorized }
    }

    /// Hasil salin audio: berkas WAV mono 16 kHz dan rentang waktu yang tidak bisa dibaca macOS.
    struct ExtractedAudio {
        let url: URL
        let duration: Double
        /// Rentang (detik) yang gagal didekode. Di berkas WAV, rentang ini diisi sunyi.
        let damaged: [ClosedRange<Double>]
    }

    /// Ukuran potongan pembacaan. Kegagalan decode dicatat per potongan, sehingga bagian rusak tidak menggagalkan seluruh file.
    static let chunkSeconds = 10.0
    static let sampleRate = 16_000.0

    /// Menyalin audio ke WAV mono 16 kHz, sepotong demi sepotong. Potongan yang tidak bisa didekode diisi sunyi.
    static func extractAudio(from url: URL) async throws -> ExtractedAudio {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw TranscribeError.noAudio }
        let total = try await asset.load(.duration).seconds
        guard total.isFinite, total > 0 else { throw TranscribeError.noAudio }

        let output = FileManager.default.temporaryDirectory.appendingPathComponent("autoclip-\(UUID().uuidString).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let file = try AVAudioFile(
            forWriting: output,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
        )

        var damaged: [ClosedRange<Double>] = []
        var start = 0.0
        while start < total {
            try Task.checkCancellation()
            let length = min(chunkSeconds, total - start)
            let expected = Int(length * sampleRate)
            var samples = [Float]()
            samples.reserveCapacity(expected)
            if readChunk(track: track, asset: asset, start: start, length: length, into: &samples) {
                if samples.count < expected {
                    samples += [Float](repeating: 0, count: expected - samples.count)
                }
            } else {
                samples = [Float](repeating: 0, count: expected)
                damaged.append(start...(start + length))
            }
            try write(samples, to: file, format: format)
            start += length
        }
        return ExtractedAudio(url: output, duration: total, damaged: mergeRanges(damaged))
    }

    /// Membaca satu potongan. Mengembalikan false jika AVFoundation melaporkan kegagalan di potongan itu.
    private static func readChunk(track: AVAssetTrack, asset: AVAsset, start: Double, length: Double, into samples: inout [Float]) -> Bool {
        guard let reader = try? AVAssetReader(asset: asset) else { return false }
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: length, preferredTimescale: 600)
        )
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { return false }

        while let buffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let byteCount = CMBlockBufferGetDataLength(block)
            var bytes = [UInt8](repeating: 0, count: byteCount)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: byteCount, destination: &bytes)
            bytes.withUnsafeBytes { raw in
                for index in 0..<(byteCount / MemoryLayout<Float>.size) {
                    samples.append(raw.loadUnaligned(fromByteOffset: index * MemoryLayout<Float>.size, as: Float.self))
                }
            }
        }
        return reader.status == .completed
    }

    private static func write(_ samples: [Float], to file: AVAudioFile, format: AVAudioFormat) throws {
        guard !samples.isEmpty, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData?[0] {
            for (index, sample) in samples.enumerated() {
                channel[index] = sample
            }
        }
        try file.write(from: buffer)
    }

    /// Menggabungkan rentang yang bersambung atau berdekatan.
    static func mergeRanges(_ ranges: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        var merged: [ClosedRange<Double>] = []
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = merged.last, range.lowerBound <= last.upperBound + 0.001 {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// Mengenali ucapan secara on-device dan mengembalikan setiap kata dengan waktunya.
    static func transcribe(audioURL: URL, localeIdentifier: String) async throws -> [SpokenWord] {
        let locale = Locale(identifier: localeIdentifier)
        let name = locale.localizedString(forIdentifier: localeIdentifier) ?? localeIdentifier
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscribeError.unsupportedLanguage(name)
        }
        guard recognizer.supportsOnDeviceRecognition else {
            throw TranscribeError.offlineUnavailable(name)
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.taskHint = .dictation

        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[SpokenWord], Error>) in
                box.task = recognizer.recognitionTask(with: request) { result, error in
                    guard !box.finished else { return }
                    if let error {
                        box.finished = true
                        continuation.resume(throwing: TranscribeError.failed(error.localizedDescription))
                        return
                    }
                    guard let result else { return }
                    // Pengenal mengirim beberapa hasil untuk satu berkas. Kata dari setiap hasil dikumpulkan,
                    // lalu kata yang sudah ada (berdasarkan waktu) dibuang agar tidak dobel.
                    box.append(result.bestTranscription.segments.map {
                        SpokenWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                    })
                    guard result.isFinal else { return }
                    box.finished = true
                    if box.words.isEmpty {
                        continuation.resume(throwing: TranscribeError.noSpeech)
                    } else {
                        continuation.resume(returning: box.words)
                    }
                }
            }
        } onCancel: {
            box.task?.cancel()
        }
    }

    /// Penampung tugas pengenalan agar bisa dibatalkan dari luar callback.
    private final class TaskBox: @unchecked Sendable {
        var task: SFSpeechRecognitionTask?
        var finished = false
        private(set) var words: [SpokenWord] = []

        /// Menambahkan kata yang belum ada. Kata dianggap baru jika mulai setelah kata terakhir yang tersimpan.
        func append(_ incoming: [SpokenWord]) {
            let lastEnd = words.last?.end ?? -1
            words += incoming.filter { $0.start > lastEnd - 0.05 }
        }
    }
}
