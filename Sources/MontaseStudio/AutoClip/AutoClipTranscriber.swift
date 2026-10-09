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

    /// Menyalin track audio ke berkas M4A sementara. Berkas ini dihapus oleh pemanggil setelah selesai.
    static func extractAudio(from url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        guard try await !asset.loadTracks(withMediaType: .audio).isEmpty else { throw TranscribeError.noAudio }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw TranscribeError.failed("ekspor audio tidak didukung untuk media ini")
        }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("autoclip-\(UUID().uuidString).m4a")
        session.outputURL = output
        session.outputFileType = .m4a

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }
        guard session.status == .completed else {
            throw TranscribeError.failed(session.error?.localizedDescription ?? "audio tidak bisa disalin")
        }
        return output
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
