import AVFoundation
import XCTest
@testable import MontaseStudio

/// Uji perencana AutoClip dengan transkrip sintetis. Tidak membutuhkan media atau pengenalan suara.
final class AutoClipPlannerTests: XCTestCase {
    /// Membuat kata-kata dari kalimat. Setiap kalimat berdurasi `duration` detik, lalu jeda `gap` detik.
    private func words(_ sentences: [(text: String, duration: Double, gap: Double)]) -> [SpokenWord] {
        var result: [SpokenWord] = []
        var cursor = 0.0
        for sentence in sentences {
            let tokens = sentence.text.split(separator: " ").map(String.init)
            let step = sentence.duration / Double(max(tokens.count, 1))
            for token in tokens {
                result.append(SpokenWord(text: token, start: cursor, end: cursor + step))
                cursor += step
            }
            cursor += sentence.gap
        }
        return result
    }

    /// Transkrip contoh: jeda 1,5 detik membentuk batas segmen, jeda 2,5 detik membentuk batas topik.
    private var sampleWords: [SpokenWord] {
        words([
            ("Banyak pemula gagal karena 3 kesalahan ini.", 6, 0.2),
            ("Pertama, tidak riset produk yang sedang trending.", 8, 1.5),
            ("Kedua, asal sebar link tanpa cerita yang menarik.", 8, 0.2),
            ("Ketiga, tidak konsisten membuat konten setiap hari.", 9, 1.5),
            ("Intinya, riset dan konsistensi adalah kunci utama.", 7, 2.5),
            ("Sekarang kita bahas topik kedua tentang modal kecil.", 8, 0.2),
            ("Modal kecil juga bisa menghasilkan uang asal tepat sasaran.", 9, 1.5),
            ("Kamu bisa mulai dari produk murah dulu ya.", 7, 0.2),
            ("Jadi jangan takut mencoba dan terus belajar.", 6, 0.2),
        ])
    }

    func testSentencesBreakOnPunctuation() {
        let sentences = AutoClipPlanner.sentences(from: sampleWords)
        XCTAssertEqual(sentences.count, 9)
        XCTAssertTrue(sentences.allSatisfy { $0.text.last.map { ".?!".contains($0) } == true })
    }

    func testEverySegmentRespectsMinimumAndMaximumLength() {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        XCTAssertFalse(topics.isEmpty)
        for topic in topics {
            for segment in topic.segments {
                XCTAssertGreaterThanOrEqual(segment.duration, AutoClipRules.minClipSeconds, segment.id)
                XCTAssertLessThanOrEqual(segment.duration, AutoClipRules.maxClipSeconds, segment.id)
            }
        }
    }

    func testSegmentsStartAndEndOnWordBoundaries() {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        let boundaries = Set(sampleWords.flatMap { [$0.start, $0.end] }.map { Int(($0 * 1000).rounded()) })
        for topic in topics {
            for segment in topic.segments {
                XCTAssertTrue(boundaries.contains(Int((segment.start * 1000).rounded())), "awal \(segment.id) di tengah kata")
                XCTAssertTrue(boundaries.contains(Int((segment.end * 1000).rounded())), "akhir \(segment.id) di tengah kata")
                // Teks segmen harus berupa kata utuh dari transkrip.
                for token in segment.text.split(separator: " ") {
                    XCTAssertTrue(sampleWords.contains { $0.text == String(token) }, "kata terpotong: \(token)")
                }
            }
        }
    }

    func testLongPauseStartsNewTopic() {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        XCTAssertGreaterThanOrEqual(topics.count, 2)
        for pair in zip(topics, topics.dropFirst()) {
            XCTAssertGreaterThanOrEqual(pair.1.start - pair.0.end, 0)
        }
    }

    func testQuestionWithNumbersScoresHigherThanFiller() {
        let hook = AutoClipPlanner.score(text: "Tahukah kamu 3 kesalahan fatal ini?", duration: 20, isFirst: true, isLast: false)
        let filler = AutoClipPlanner.score(text: "Oke lanjut saja.", duration: 4, isFirst: false, isLast: false)
        XCTAssertGreaterThan(hook.score, filler.score)
        XCTAssertGreaterThanOrEqual(hook.score, AutoClipRules.idealHookScore)
        XCTAssertEqual(hook.kind, .hook)
    }

    func testClosingSentenceIsMarkedAsPenutup() {
        let closing = AutoClipPlanner.score(text: "Kesimpulannya, konsistensi itu kunci.", duration: 10, isFirst: false, isLast: true)
        XCTAssertEqual(closing.kind, .penutup)
    }

    func testOutputStartsWithHookAndStaysWithinMaximum() {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        let outputs = AutoClipPlanner.compose(topics: topics, count: 2)
        XCTAssertEqual(outputs.count, 2)
        for output in outputs {
            XCTAssertLessThanOrEqual(output.segments.count, AutoClipRules.maxClipsPerOutput)
            XCTAssertLessThanOrEqual(output.duration, AutoClipRules.outputMaxSeconds)
            XCTAssertEqual(output.segments.first?.topicID, output.topicID)
            // Setiap segmen hanya dipakai sekali di seluruh output.
        }
        let allIDs = outputs.flatMap { $0.segments.map(\.id) }
        XCTAssertEqual(Set(allIDs).count, allIDs.count)
    }

    func testRequestingMoreOutputsCreatesAnglesFromSameTopic() {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        let available = topics.reduce(0) { $0 + $1.segments.count }
        let outputs = AutoClipPlanner.compose(topics: topics, count: 6)
        XCTAssertLessThanOrEqual(outputs.count, available)
        XCTAssertGreaterThan(outputs.count, topics.count, "sudut tambahan dari topik yang sama harus dibuat")
    }

    func testLetterSequence() {
        XCTAssertEqual(AutoClipPlanner.letter(0), "A")
        XCTAssertEqual(AutoClipPlanner.letter(25), "Z")
        XCTAssertEqual(AutoClipPlanner.letter(26), "AA")
    }

    func testReportUsesSpecificationKeys() throws {
        let topics = AutoClipPlanner.analyze(words: sampleWords)
        let outputs = AutoClipPlanner.compose(topics: topics, count: 1)
        let report = AutoClipReport.make(topics: topics, outputs: outputs)
        let data = try JSONEncoder().encode(report)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNotNil(json["analisis_topik"])
        XCTAssertNotNil(json["video_final_siap_posting"])
        let topic = try XCTUnwrap((json["analisis_topik"] as? [[String: Any]])?.first)
        XCTAssertNotNil(topic["id_topik"])
        XCTAssertNotNil(topic["judul_topik"])
        let segment = try XCTUnwrap((topic["segments"] as? [[String: Any]])?.first)
        for key in ["id_segment", "start", "end", "durasi_detik", "teks", "viral_score", "alasan_score", "tipe"] {
            XCTAssertNotNil(segment[key], key)
        }
        let output = try XCTUnwrap((json["video_final_siap_posting"] as? [[String: Any]])?.first)
        for key in ["id_output", "id_topik_asal", "judul", "deskripsi", "poin_utama", "urutan_gabungan_segment",
                    "transkrip_final_gabungan", "estimasi_durasi_final_detik", "alasan_editorial"] {
            XCTAssertNotNil(output[key], key)
        }
        XCTAssertEqual(AutoClipReport.timecode(3725), "01:02:05")
    }
}

@MainActor
final class AutoClipProjectTests: XCTestCase {
    func testOutputBecomesContiguousProjectOfSegments() {
        let item = MediaItem(
            name: "Sumber", path: "/tmp/none-autoclip.mp4", duration: Ticks(seconds: 300),
            hasVideo: true, hasAudio: true, width: 1920, height: 1080
        )
        let segments = [
            CandidateSegment(id: "1-A", topicID: 1, start: 10, end: 24, text: "Hook pertama", score: 9, reason: "", kind: .hook),
            CandidateSegment(id: "1-B", topicID: 1, start: 60, end: 80, text: "Isi kedua", score: 6, reason: "", kind: .isi),
        ]
        let plan = OutputPlan(id: 1, topicID: 1, segments: segments)

        let project = AutoClipRunner.makeProject(item: item, plan: plan, title: "Judul", orientation: .portrait)

        XCTAssertEqual(project.sequence.width, 1080)
        XCTAssertEqual(project.sequence.height, 1920)
        let clips = project.tracks.flatMap(\.clips)
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].sourceStart.seconds, 10, accuracy: 0.001)
        XCTAssertEqual(clips[0].timelineStart, .zero)
        XCTAssertEqual(clips[1].timelineStart.seconds, 14, accuracy: 0.001, "klip kedua harus menempel di belakang klip pertama")
        XCTAssertEqual(clips[1].sourceStart.seconds, 60, accuracy: 0.001)
        XCTAssertEqual(project.duration.seconds, plan.duration, accuracy: 0.01)
    }

    func testSafeFileNameRemovesPathCharacters() {
        XCTAssertEqual(AutoClipRunner.safeFileName("Tips: cuan/affiliate?"), "Tips  cuan affiliate")
    }
}

/// Memastikan audio bisa disalin dari video sebelum dikenali. Membutuhkan ffmpeg; dilewati jika tidak ada.
final class AutoClipAudioExtractionTests: XCTestCase {
    func testExtractsAudioTrackFromVideo() async throws {
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipUnless(ffmpeg != nil, "ffmpeg tidak ditemukan")

        let video = FileManager.default.temporaryDirectory.appendingPathComponent("autoclip-src-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: video) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg!)
        process.arguments = ["-hide_banner", "-loglevel", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=30",
                             "-f", "lavfi", "-i", "sine=frequency=440", "-t", "4", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                             "-c:a", "aac", "-shortest", video.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        let audio = try await AutoClipTranscriber.extractAudio(from: video)
        defer { try? FileManager.default.removeItem(at: audio) }
        let asset = AVURLAsset(url: audio)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertFalse(audioTracks.isEmpty)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 4, accuracy: 0.3)
    }
}
