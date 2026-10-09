import Foundation

/// Laporan JSON sesuai format AutoCut Engine. Kunci dan urutan mengikuti spesifikasi.
struct AutoClipReport: Codable, Equatable {
    struct TopicEntry: Codable, Equatable {
        let idTopik: Int
        let judulTopik: String
        let startTopik: String
        let endTopik: String
        let segments: [SegmentEntry]

        enum CodingKeys: String, CodingKey {
            case idTopik = "id_topik"
            case judulTopik = "judul_topik"
            case startTopik = "start_topik"
            case endTopik = "end_topik"
            case segments
        }
    }

    struct SegmentEntry: Codable, Equatable {
        let idSegment: String
        let start: String
        let end: String
        let durasiDetik: Int
        let teks: String
        let viralScore: Int
        let alasanScore: String
        let tipe: String

        enum CodingKeys: String, CodingKey {
            case idSegment = "id_segment"
            case start, end
            case durasiDetik = "durasi_detik"
            case teks
            case viralScore = "viral_score"
            case alasanScore = "alasan_score"
            case tipe
        }
    }

    struct OutputEntry: Codable, Equatable {
        let idOutput: Int
        let idTopikAsal: Int
        let judul: String
        let deskripsi: String
        let poinUtama: [String]
        let urutanGabunganSegment: [String]
        let transkripFinalGabungan: String
        let estimasiDurasiFinalDetik: Int
        let alasanEditorial: String

        enum CodingKeys: String, CodingKey {
            case idOutput = "id_output"
            case idTopikAsal = "id_topik_asal"
            case judul, deskripsi
            case poinUtama = "poin_utama"
            case urutanGabunganSegment = "urutan_gabungan_segment"
            case transkripFinalGabungan = "transkrip_final_gabungan"
            case estimasiDurasiFinalDetik = "estimasi_durasi_final_detik"
            case alasanEditorial = "alasan_editorial"
        }
    }

    let analisisTopik: [TopicEntry]
    let videoFinalSiapPosting: [OutputEntry]

    enum CodingKeys: String, CodingKey {
        case analisisTopik = "analisis_topik"
        case videoFinalSiapPosting = "video_final_siap_posting"
    }

    /// Mengubah hasil perencanaan menjadi laporan JSON.
    static func make(topics: [Topic], outputs: [OutputPlan]) -> AutoClipReport {
        let topicEntries = topics.map { topic in
            TopicEntry(
                idTopik: topic.id,
                judulTopik: topic.title,
                startTopik: timecode(topic.start),
                endTopik: timecode(topic.end),
                segments: topic.segments.map { segment in
                    SegmentEntry(
                        idSegment: segment.id,
                        start: timecode(segment.start),
                        end: timecode(segment.end),
                        durasiDetik: Int(segment.duration.rounded()),
                        teks: segment.text,
                        viralScore: segment.score,
                        alasanScore: segment.reason,
                        tipe: segment.kind.rawValue
                    )
                }
            )
        }

        let outputEntries = outputs.map { plan -> OutputEntry in
            let transcript = plan.segments.map(\.text).joined(separator: " ")
            let hook = plan.segments.first
            let order = plan.segments.map(\.id)
            return OutputEntry(
                idOutput: plan.id,
                idTopikAsal: plan.topicID,
                judul: headline(for: transcript),
                deskripsi: description(for: transcript),
                poinUtama: keyPoints(for: plan.segments),
                urutanGabunganSegment: order,
                transkripFinalGabungan: transcript,
                estimasiDurasiFinalDetik: Int(plan.duration.rounded()),
                alasanEditorial: editorialReason(for: plan.segments, hook: hook)
            )
        }

        return AutoClipReport(analisisTopik: topicEntries, videoFinalSiapPosting: outputEntries)
    }

    static func timecode(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    // MARK: - Metadata

    static func headline(for transcript: String) -> String {
        AutoClipPlanner.title(from: transcript)
    }

    /// Ringkasan pendek plus tiga tagar dari kata yang paling sering muncul.
    static func description(for transcript: String) -> String {
        let summary = transcript.prefix(160).trimmingCharacters(in: .whitespaces)
        let tags = keywords(in: transcript, limit: 3).map { "#\($0)" }
        return ([summary] + [tags.joined(separator: " ")]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func keyPoints(for segments: [CandidateSegment]) -> [String] {
        let points = segments.prefix(3).map { segment -> String in
            let words = segment.text.split(separator: " ").prefix(12).joined(separator: " ")
            return words + (segment.text.split(separator: " ").count > 12 ? "…" : "")
        }
        return points.isEmpty ? ["-"] : points
    }

    static func editorialReason(for segments: [CandidateSegment], hook: CandidateSegment?) -> String {
        let middle = segments.dropFirst().filter { $0.kind != .penutup }.map(\.id)
        let closing = segments.last.flatMap { $0.kind == .penutup ? $0.id : nil }
        var parts: [String] = []
        if let hook {
            parts.append("Dibuka dengan hook (\(hook.id), skor \(hook.score))")
        }
        if !middle.isEmpty {
            parts.append("isi \(middle.joined(separator: ", "))")
        }
        if let closing {
            parts.append("ditutup dengan penutup (\(closing))")
        }
        return parts.joined(separator: ", ")
    }

    private static let stopwords: Set<String> = [
        "yang", "dengan", "untuk", "dari", "dan", "atau", "dalam", "akan", "bisa", "tidak", "saya", "kita", "kamu",
        "mereka", "ini", "itu", "sudah", "juga", "karena", "agar", "ada", "jadi", "kalau", "lebih", "banyak", "the",
    ]

    static func keywords(in text: String, limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let word = String(raw)
            guard word.count >= 5, !stopwords.contains(word) else { continue }
            counts[word, default: 0] += 1
        }
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(limit)
            .map(\.key)
    }
}
