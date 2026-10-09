import Foundation

/// Mode pemeriksaan: `--autoclip-check <berkas> --autoclip-out <hasil.txt>`.
/// Menjalankan jalur produksi lengkap (salin audio, transkripsi on-device, perencanaan) lalu menulis hasilnya ke berkas.
/// Dijalankan lewat `open` agar aplikasi sendiri yang meminta izin pengenalan suara, bukan terminal.
@MainActor
enum AutoClipSelfCheck {
    static func run(path: String, outputPath: String) {
        Task { @MainActor in
            var lines: [String] = []
            do {
                try await AutoClipTranscriber.requestAuthorization()
                let audio = try await AutoClipTranscriber.extractAudio(from: URL(fileURLWithPath: path))
                defer { try? FileManager.default.removeItem(at: audio) }

                let words = try await AutoClipTranscriber.transcribe(audioURL: audio, localeIdentifier: "id-ID")
                lines.append("KATA: \(words.count)")
                lines.append("TRANSKRIP: " + words.map(\.text).joined(separator: " "))
                lines.append("KATA BERWAKTU:")
                for word in words {
                    lines.append(String(format: "  %6.2f-%6.2f %@", word.start, word.end, word.text))
                }
                // Jeda antarkata, untuk menyetel batas kalimat dan topik.
                let gaps = zip(words, words.dropFirst()).map { ($1.start - $0.end, $0.text, $1.text) }
                lines.append("JEDA >0,3 dtk:")
                for gap in gaps where gap.0 > 0.3 {
                    lines.append(String(format: "  %.2f dtk: %@ | %@", gap.0, gap.1, gap.2))
                }

                let silences = try AutoClipSilence.detect(in: audio)
                lines.append("SUNYI >0,4 dtk: \(silences.count)")
                for silence in silences {
                    lines.append(String(format: "  %.2f - %.2f dtk (%.2f)", silence.start, silence.end, silence.end - silence.start))
                }
                let topics = AutoClipPlanner.analyze(words: words, silences: silences)
                lines.append("TOPIK: \(topics.count)")
                for topic in topics {
                    for segment in topic.segments {
                        lines.append(String(format: "SEGMEN %@ %.1f dtk skor %d (%@): %@",
                                            segment.id, segment.duration, segment.score, segment.kind.rawValue, segment.text))
                    }
                }
                lines.append("HASIL: OK")
            } catch {
                lines.append("GAGAL: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
            try? lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
            exit(lines.last == "HASIL: OK" ? 0 : 1)
        }
    }
}

extension AutoClipSelfCheck {
    /// Menjalankan seluruh proses Auto Clip seperti dari panel, termasuk ekspor, lalu menulis tahap dan hasilnya.
    /// Dipakai: `--autoclip-run <berkas> --autoclip-out <hasil.txt> --autoclip-count <n>`.
    static func runFull(path: String, outputPath: String, count: Int) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("autoclip-run-\(UUID().uuidString)")
        let runner = AutoClipRunner()
        let exporter = ExportController()
        runner.start(
            AutoClipRunner.Request(
                source: URL(fileURLWithPath: path),
                sourceItem: nil,
                count: count,
                orientation: .portrait,
                localeIdentifier: "id-ID",
                folder: folder
            ),
            exporter: exporter
        )
        Task { @MainActor in
            var lastStage = ""
            while runner.stage.isBusy {
                try? await Task.sleep(for: .seconds(1))
                if runner.stage.label != lastStage {
                    lastStage = runner.stage.label
                    print("TAHAP: \(lastStage)")
                }
            }
            var lines = ["TAHAP AKHIR: \(runner.stage.label)", "FOLDER: \(folder.path)"]
            if let error = exporter.lastError { lines.append("ERROR EKSPOR: \(error)") }
            for result in runner.results {
                lines.append(String(format: "VIDEO %02d: %.1f dtk — %@", result.id, result.duration, result.fileURL.lastPathComponent))
            }
            try? lines.joined(separator: "\n").write(toFile: outputPath, atomically: true, encoding: .utf8)
            exit(runner.stage == .finished ? 0 : 1)
        }
    }
}
