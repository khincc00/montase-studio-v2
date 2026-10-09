import Foundation
import Observation

/// Menjalankan Auto Clip dari awal sampai akhir: izin, salin audio, transkripsi, perencanaan, lalu ekspor setiap output.
/// Seluruh proses berjalan di Mac ini.
@MainActor
@Observable
final class AutoClipRunner {
    enum Stage: Equatable {
        case idle
        case authorizing
        case extractingAudio
        case transcribing
        case planning
        case exporting(current: Int, total: Int)
        case finished
        case cancelled
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .authorizing, .extractingAudio, .transcribing, .planning, .exporting: return true
            case .idle, .finished, .cancelled, .failed: return false
            }
        }

        var label: String {
            switch self {
            case .idle: return ""
            case .authorizing: return "Meminta izin pengenalan suara…"
            case .extractingAudio: return "Menyalin audio dari media…"
            case .transcribing: return "Mentranskripsi di perangkat ini…"
            case .planning: return "Menganalisis topik dan memilih segmen…"
            case .exporting(let current, let total): return "Mengekspor video \(current) dari \(total)…"
            case .finished: return "Selesai"
            case .cancelled: return "Dibatalkan"
            case .failed(let message): return message
            }
        }
    }

    /// Satu video final yang sudah diekspor.
    struct Result: Identifiable {
        let id: Int
        let title: String
        let fileURL: URL
        let duration: Double
        let project: Project
        let plan: OutputPlan
    }

    private(set) var stage: Stage = .idle
    private(set) var results: [Result] = []
    private(set) var report: AutoClipReport?
    private(set) var reportURL: URL?
    private(set) var topicCount = 0
    private(set) var transcriptWordCount = 0

    private var task: Task<Void, Never>?

    struct Request {
        let source: URL
        /// Media dari Library jika dipilih dari proyek; nil jika berkas dipilih langsung.
        let sourceItem: MediaItem?
        let count: Int
        let orientation: ExportOrientation
        let localeIdentifier: String
        let folder: URL
    }

    func start(_ request: Request, exporter: ExportController) {
        guard !stage.isBusy else { return }
        results = []
        report = nil
        reportURL = nil
        stage = .authorizing

        task = Task { [weak self] in
            guard let self else { return }
            await self.run(request, exporter: exporter)
        }
    }

    func cancel(exporter: ExportController) {
        task?.cancel()
        exporter.cancel()
    }

    private func run(_ request: Request, exporter: ExportController) async {
        var audioURL: URL?
        defer {
            if let audioURL { try? FileManager.default.removeItem(at: audioURL) }
        }

        do {
            try await AutoClipTranscriber.requestAuthorization()
            try Task.checkCancellation()

            stage = .extractingAudio
            audioURL = try await Self.step("Menyalin audio") {
                try await AutoClipTranscriber.extractAudio(from: request.source)
            }
            try Task.checkCancellation()

            stage = .transcribing
            let words = try await Self.step("Transkripsi") {
                try await AutoClipTranscriber.transcribe(audioURL: audioURL!, localeIdentifier: request.localeIdentifier)
            }
            transcriptWordCount = words.count
            try Task.checkCancellation()

            stage = .planning
            let silences = (try? AutoClipSilence.detect(in: audioURL!)) ?? []
            let topics = AutoClipPlanner.analyze(words: words, silences: silences)
            topicCount = topics.count
            let outputs = AutoClipPlanner.compose(topics: topics, count: request.count)
            guard !outputs.isEmpty else {
                throw AutoClipTranscriber.TranscribeError.failed("tidak ada segmen 5–120 detik yang bisa dibentuk dari transkrip ini")
            }
            let analysis = AutoClipReport.make(topics: topics, outputs: outputs)
            report = analysis

            let item = try await mediaItem(for: request)
            try FileManager.default.createDirectory(at: request.folder, withIntermediateDirectories: true)
            let jsonURL = request.folder.appendingPathComponent("autoclip-analisis.json")
            try JSONEncoder.autoClip.encode(analysis).write(to: jsonURL, options: .atomic)
            reportURL = jsonURL

            let settings = ExportSettings(resolution: .hd, orientation: request.orientation, codec: .h264, quality: .high)
            for (index, plan) in outputs.enumerated() {
                try Task.checkCancellation()
                stage = .exporting(current: index + 1, total: outputs.count)

                let title = analysis.videoFinalSiapPosting[index].judul
                let project = Self.makeProject(item: item, plan: plan, title: title, orientation: request.orientation)
                let fileURL = request.folder.appendingPathComponent(
                    "\(String(format: "%02d", plan.id)) \(Self.safeFileName(title)).mp4"
                )
                await exporter.export(project, to: fileURL, using: settings)
                if Task.isCancelled { throw CancellationError() }
                if let error = exporter.lastError {
                    throw StepError(step: stage.label, message: error, code: exporter.lastErrorCode)
                }

                results.append(Result(
                    id: plan.id,
                    title: title,
                    fileURL: fileURL,
                    duration: plan.duration,
                    project: project,
                    plan: plan
                ))
            }
            stage = .finished
        } catch is CancellationError {
            stage = .cancelled
        } catch let error as StepError {
            stage = .failed(error.report)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let nsError = error as NSError
            let code = nsError.domain == NSCocoaErrorDomain ? nil : "\(nsError.domain) \(nsError.code)"
            stage = Task.isCancelled ? .cancelled : .failed(StepError(step: stage.label, message: message, code: code).report)
        }
    }

    /// Menjalankan satu tahap dan membungkus kesalahannya dengan nama tahap dan kode sistem.
    private static func step<T>(_ name: String, _ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as AutoClipTranscriber.TranscribeError {
            if case .noSpeech = error { throw error }
            throw StepError(step: name, message: error.errorDescription ?? "", code: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let nsError = error as NSError
            throw StepError(step: name, message: error.localizedDescription, code: "\(nsError.domain) \(nsError.code)")
        }
    }

    /// Kesalahan dengan tahap, pesan, dan kode sistem, supaya laporan bisa ditelusuri.
    struct StepError: Error {
        let step: String
        let message: String
        let code: String?

        var report: String {
            var text = "Gagal pada tahap \"\(step)\": \(message)"
            if let code { text += " [\(code)]" }
            if message.localizedCaseInsensitiveContains("decode") {
                text += ". Format atau codec video ini tidak bisa dibaca macOS. Ubah ke MP4 (H.264 + AAC) lalu impor ulang."
            }
            return text
        }
    }

    private func mediaItem(for request: Request) async throws -> MediaItem {
        if let item = request.sourceItem { return item }
        let item = try await MediaImporter.probe(request.source)
        guard item.hasVideo else {
            throw AutoClipTranscriber.TranscribeError.failed("Auto Clip membutuhkan sumber video, bukan audio saja.")
        }
        return item
    }

    /// Proyek untuk satu output: setiap segmen menjadi klip berurutan di track video, sehingga bisa dibuka di editor.
    static func makeProject(item: MediaItem, plan: OutputPlan, title: String, orientation: ExportOrientation) -> Project {
        var project = Project()
        project.name = title
        var exportSettings = ExportSettings()
        exportSettings.orientation = orientation
        let size = exportSettings.size
        project.sequence = SequenceSettings(width: Int(size.width), height: Int(size.height), frameRate: 30)
        let media = project.registerMedia(item)

        guard let trackID = project.defaultTrackID(for: .video),
              let trackIndex = project.trackIndex(trackID) else { return project }

        var cursor = Ticks.zero
        for segment in plan.segments {
            let clip = Clip(
                mediaID: media.id,
                name: String(segment.text.prefix(40)),
                sourceStart: Ticks(seconds: segment.start),
                timelineStart: cursor,
                duration: Ticks(seconds: segment.duration)
            )
            project.tracks[trackIndex].clips.append(clip)
            cursor = cursor + clip.duration
        }
        return project
    }

    static func safeFileName(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = title.components(separatedBy: forbidden).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(60))
    }

    static var defaultFolder: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return movies.appendingPathComponent("Montase Auto Clip", isDirectory: true)
    }
}

extension JSONEncoder {
    /// Encoder untuk laporan JSON yang mudah dibaca manusia.
    static var autoClip: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
