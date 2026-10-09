import Foundation

/// Aturan pemotongan. Nilainya dari spesifikasi AutoCut Engine dan tidak bisa diubah dari UI.
enum AutoClipRules {
    /// Klip mentah tidak boleh lebih pendek dari ini.
    static let minClipSeconds = 5.0
    /// Klip mentah tidak boleh lebih panjang dari ini.
    static let maxClipSeconds = 120.0
    /// Durasi video final yang diinginkan.
    static let outputMinSeconds = 30.0
    static let outputMaxSeconds = 90.0
    /// Hook, isi, dan penutup. Satu video final maksimal lima klip.
    static let maxClipsPerOutput = 5
    static let maxIsiPerOutput = 3
    /// Jeda di atas nilai ini memisahkan kalimat.
    static let sentenceGapSeconds = 0.8
    /// Jeda di atas nilai ini memisahkan topik.
    static let topicGapSeconds = 2.0
    /// Topik tidak dibiarkan lebih panjang dari ini sebelum dipecah.
    static let maxTopicSeconds = 240.0
    /// Jeda yang cukup panjang untuk dijadikan batas segmen, asalkan segmen sudah minimal.
    static let segmentGapSeconds = 1.2
    /// Skor minimal untuk hook yang ideal.
    static let idealHookScore = 8
}

/// Satu kata hasil pengenalan suara dengan waktunya (detik dari awal media).
struct SpokenWord: Equatable {
    let text: String
    let start: Double
    let end: Double
}

/// Kalimat utuh. Pemotongan selalu terjadi di batas kalimat, sehingga tidak memotong di tengah kata.
struct Sentence: Equatable {
    var text: String
    var start: Double
    var end: Double
    /// Jeda sesudah kalimat ini, dari audio (sunyi) atau dari celah antarkata, mana yang lebih panjang.
    var pauseAfter: Double = 0
    var duration: Double { end - start }
}

enum SegmentKind: String, Codable {
    case hook
    case isi
    case penutup
}

/// Segmen kandidat: potongan kalimat yang sudah dinilai.
struct CandidateSegment: Equatable {
    /// Format "topik-huruf", misalnya "1-A".
    let id: String
    let topicID: Int
    let start: Double
    let end: Double
    let text: String
    let score: Int
    let reason: String
    let kind: SegmentKind

    var duration: Double { end - start }
}

struct Topic: Equatable {
    let id: Int
    let title: String
    let start: Double
    let end: Double
    let segments: [CandidateSegment]

    var bestScore: Int { segments.map(\.score).max() ?? 0 }
}

/// Satu video final: gabungan segmen dengan urutan hook, isi, penutup.
struct OutputPlan: Equatable {
    let id: Int
    let topicID: Int
    /// Segmen dalam urutan tampil (hook dulu, lalu isi menurut waktu, lalu penutup).
    let segments: [CandidateSegment]

    var duration: Double { segments.reduce(0) { $0 + $1.duration } }
}

/// Perencana lokal: membagi transkrip menjadi topik, memecahnya menjadi segmen, memberi skor, dan menyusun output.
/// Semua proses berjalan di perangkat tanpa layanan eksternal. Skor berasal dari aturan heuristik, bukan model bahasa.
enum AutoClipPlanner {
    /// Membagi kata menjadi kalimat. Batas diambil dari tanda baca, jeda antarkata, atau sunyi di audio.
    static func sentences(from words: [SpokenWord], silences: [SilenceInterval] = []) -> [Sentence] {
        var result: [Sentence] = []
        var current: [SpokenWord] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = current.map(\.text).joined(separator: " ")
            result.append(Sentence(text: text, start: first.start, end: last.end))
            current = []
        }

        for word in words {
            if let last = current.last {
                let pause = max(word.start - last.end, silenceTotal(from: last.end, to: word.start, silences))
                if pause >= AutoClipRules.sentenceGapSeconds / 2 && (pause >= AutoClipRules.sentenceGapSeconds || silenceMatters(last.end, word.start, silences)) {
                    flush()
                }
            }
            current.append(word)
            if endsSentence(word.text) {
                flush()
            }
        }
        flush()

        // Kalimat yang lebih panjang dari batas klip dipecah di batas kata, tetap tanpa memotong kata.
        var sentences = result.flatMap { split($0, words: words) }
        for index in sentences.indices {
            let end = sentences[index].end
            let next = index + 1 < sentences.count ? sentences[index + 1].start : end
            sentences[index].pauseAfter = max(next - end, silenceTotal(from: end, to: next, silences))
        }
        return sentences
    }

    /// Total durasi sunyi yang berada di antara dua waktu.
    static func silenceTotal(from start: Double, to end: Double, _ silences: [SilenceInterval]) -> Double {
        guard end > start else { return 0 }
        return silences.reduce(0) { total, silence in
            let overlap = min(silence.end, end) - max(silence.start, start)
            return overlap > 0 ? total + overlap : total
        }
    }

    private static func silenceMatters(_ start: Double, _ end: Double, _ silences: [SilenceInterval]) -> Bool {
        silenceTotal(from: start, to: end, silences) >= AutoClipRules.sentenceGapSeconds / 2
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!".contains(last)
    }

    /// Memecah kalimat terlalu panjang menjadi bagian-bagian kira-kira sepanjang batas maksimum.
    private static func split(_ sentence: Sentence, words: [SpokenWord]) -> [Sentence] {
        guard sentence.duration > AutoClipRules.maxClipSeconds else { return [sentence] }
        let inside = words.filter { $0.start >= sentence.start && $0.end <= sentence.end }
        var pieces: [Sentence] = []
        var chunk: [SpokenWord] = []
        for word in inside {
            if let first = chunk.first, word.end - first.start > AutoClipRules.maxClipSeconds {
                pieces.append(make(chunk))
                chunk = []
            }
            chunk.append(word)
        }
        if !chunk.isEmpty { pieces.append(make(chunk)) }
        return pieces.isEmpty ? [sentence] : pieces
    }

    private static func make(_ words: [SpokenWord]) -> Sentence {
        Sentence(
            text: words.map(\.text).joined(separator: " "),
            start: words.first?.start ?? 0,
            end: words.last?.end ?? 0
        )
    }

    /// Topik dimulai saat ada jeda panjang atau topik sudah terlalu panjang.
    static func topicGroups(_ sentences: [Sentence]) -> [[Sentence]] {
        var groups: [[Sentence]] = []
        var current: [Sentence] = []
        for sentence in sentences {
            if let last = current.last {
                let gap = last.pauseAfter
                let length = sentence.end - (current.first?.start ?? sentence.start)
                if gap >= AutoClipRules.topicGapSeconds || length > AutoClipRules.maxTopicSeconds {
                    groups.append(current)
                    current = []
                }
            }
            current.append(sentence)
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    /// Mengelompokkan kalimat dalam satu topik menjadi segmen 5–120 detik.
    static func segments(in sentences: [Sentence]) -> [(start: Double, end: Double, text: String)] {
        var groups: [[Sentence]] = []
        var current: [Sentence] = []

        for sentence in sentences {
            if let last = current.last {
                let gap = last.pauseAfter
                let spanIfAdded = sentence.end - (current.first?.start ?? sentence.start)
                let currentLength = last.end - (current.first?.start ?? last.end)
                let scene = gap >= AutoClipRules.segmentGapSeconds && currentLength >= AutoClipRules.minClipSeconds
                if spanIfAdded > AutoClipRules.maxClipSeconds || scene {
                    groups.append(current)
                    current = []
                }
            }
            current.append(sentence)
        }
        if !current.isEmpty { groups.append(current) }

        // Segmen di bawah 5 detik digabung ke segmen sebelumnya bila muat; jika tidak, ke yang sesudahnya.
        var merged: [[Sentence]] = []
        for group in groups {
            let length = (group.last?.end ?? 0) - (group.first?.start ?? 0)
            if length < AutoClipRules.minClipSeconds, let previous = merged.last {
                let combined = (group.last?.end ?? 0) - (previous.first?.start ?? 0)
                if combined <= AutoClipRules.maxClipSeconds {
                    merged[merged.count - 1] += group
                    continue
                }
            }
            merged.append(group)
        }

        return merged.compactMap { group in
            guard let first = group.first, let last = group.last else { return nil }
            let length = last.end - first.start
            guard length >= AutoClipRules.minClipSeconds, length <= AutoClipRules.maxClipSeconds else { return nil }
            return (first.start, last.end, group.map(\.text).joined(separator: " "))
        }
    }

    // MARK: - Skor

    private static let hookWords = [
        "ternyata", "rahasia", "salah", "kesalahan", "jangan", "fakta", "tahukah", "kenapa", "mengapa",
        "bagaimana", "gagal", "untung", "cuan", "trik", "cara", "penting", "bahaya", "mengejutkan", "tidak pernah",
    ]
    private static let closingWords = [
        "kesimpulan", "intinya", "jadi", "makanya", "semoga", "follow", "subscribe", "like", "komentar", "terima kasih",
    ]

    /// Memberi skor 1–10 dan tipe segmen. `isFirst` dan `isLast` menandai posisi dalam topik.
    static func score(text: String, duration: Double, isFirst: Bool, isLast: Bool) -> (score: Int, reason: String, kind: SegmentKind) {
        let lower = text.lowercased()
        var score = 4
        var reasons: [String] = []

        if text.contains("?") {
            score += 2
            reasons.append("ada pertanyaan")
        }
        let hits = hookWords.filter { lower.contains($0) }
        if !hits.isEmpty {
            score += min(2, hits.count)
            reasons.append("kata pemicu perhatian")
        }
        if text.rangeOfCharacter(from: .decimalDigits) != nil {
            score += 1
            reasons.append("ada angka")
        }
        if (15...60).contains(duration) {
            score += 1
            reasons.append("durasi ideal")
        }
        if duration < 8 {
            score -= 1
            reasons.append("singkat")
        }
        if isFirst {
            score += 1
            reasons.append("pembuka topik")
        }
        let score10 = min(max(score, 1), 10)

        let isClosing = closingWords.contains { lower.contains($0) }
        let kind: SegmentKind
        if isClosing && (isLast || score10 < AutoClipRules.idealHookScore) {
            kind = .penutup
        } else if score10 >= AutoClipRules.idealHookScore && (isFirst || !hits.isEmpty || text.contains("?")) {
            kind = .hook
        } else {
            kind = .isi
        }
        if reasons.isEmpty { reasons.append("penjelasan lanjutan") }
        return (score10, reasons.joined(separator: ", "), kind)
    }

    // MARK: - Pipeline

    /// Menjalankan seluruh tahap: kalimat → topik → segmen → skor.
    /// `damaged` berisi rentang audio yang tidak bisa dibaca; kata di dalamnya dibuang agar tidak dipakai di klip.
    static func analyze(words input: [SpokenWord], silences: [SilenceInterval] = [], damaged: [ClosedRange<Double>] = []) -> [Topic] {
        let words = damaged.isEmpty ? input : input.filter { word in
            !damaged.contains { $0.overlaps(word.start...max(word.end, word.start)) }
        }
        let groups = topicGroups(sentences(from: words, silences: silences))
        var topics: [Topic] = []

        for group in groups {
            let raw = segments(in: group)
            guard !raw.isEmpty, let first = group.first, let last = group.last else { continue }
            let topicID = topics.count + 1
            let candidates = raw.enumerated().map { position, piece -> CandidateSegment in
                let evaluation = score(
                    text: piece.text,
                    duration: piece.end - piece.start,
                    isFirst: position == 0,
                    isLast: position == raw.count - 1
                )
                return CandidateSegment(
                    id: "\(topicID)-\(letter(position))",
                    topicID: topicID,
                    start: piece.start,
                    end: piece.end,
                    text: piece.text,
                    score: evaluation.score,
                    reason: evaluation.reason,
                    kind: evaluation.kind
                )
            }
            topics.append(Topic(
                id: topicID,
                title: title(from: candidates.first?.text ?? first.text),
                start: first.start,
                end: last.end,
                segments: candidates
            ))
        }
        return topics
    }

    /// Menyusun video final. Tahap pertama memberi satu output per topik, dimulai dari skor tertinggi.
    /// Jika masih kurang dari yang diminta, topik terpanjang dipecah menjadi beberapa sudut (angle) dengan segmen berbeda.
    static func compose(topics: [Topic], count: Int) -> [OutputPlan] {
        guard count > 0 else { return [] }
        let eligible = topics.filter { !$0.segments.isEmpty }
        let byScore = eligible.sorted { $0.bestScore == $1.bestScore ? $0.id < $1.id : $0.bestScore > $1.bestScore }

        var quotas: [Int: Int] = [:]
        var assigned = 0
        for topic in byScore where assigned < count {
            quotas[topic.id] = 1
            assigned += 1
        }

        let byLength = byScore
            .filter { quotas[$0.id] != nil }
            .sorted { totalDuration($0) > totalDuration($1) }
        var progressed = true
        while assigned < count && progressed {
            progressed = false
            for topic in byLength where assigned < count {
                let current = quotas[topic.id] ?? 0
                // Satu sudut butuh minimal satu segmen; sudut tambahan tidak boleh melebihi jumlah segmen.
                guard current < topic.segments.count else { continue }
                quotas[topic.id] = current + 1
                assigned += 1
                progressed = true
            }
        }

        var plans: [OutputPlan] = []
        for topic in byScore {
            let angles = quotas[topic.id] ?? 0
            guard angles > 0 else { continue }
            // Segmen dibagi rata ke setiap sudut menurut peringkat skor, sehingga tiap sudut punya kandidat hook sendiri.
            var groups = Array(repeating: [CandidateSegment](), count: angles)
            for (rank, segment) in topic.segments.sorted(by: { $0.score == $1.score ? $0.start < $1.start : $0.score > $1.score }).enumerated() {
                groups[rank % angles].append(segment)
            }
            for group in groups {
                if let plan = buildOutput(id: 0, topicID: topic.id, pool: group) {
                    plans.append(plan)
                }
            }
        }

        return plans.prefix(count).enumerated().map { index, plan in
            OutputPlan(id: index + 1, topicID: plan.topicID, segments: plan.segments)
        }
    }

    private static func totalDuration(_ topic: Topic) -> Double {
        topic.segments.reduce(0) { $0 + $1.duration }
    }

    /// Memilih hook, isi, dan penutup dari kumpulan segmen. Mengembalikan nil jika hasilnya terlalu pendek.
    static func buildOutput(id: Int, topicID: Int, pool: [CandidateSegment]) -> OutputPlan? {
        let ranked = pool.sorted { $0.score == $1.score ? $0.start < $1.start : $0.score > $1.score }
        guard let hook = ranked.first(where: { $0.kind == .hook }) ?? ranked.first else { return nil }

        var chosen: [CandidateSegment] = [hook]
        var total = hook.duration

        let closing = ranked.first { $0.kind == .penutup && $0.id != hook.id }
        let reserve = closing?.duration ?? 0

        for candidate in ranked where candidate.id != hook.id && candidate.id != closing?.id {
            let isiCount = chosen.count - 1
            guard isiCount < AutoClipRules.maxIsiPerOutput, chosen.count + (closing == nil ? 0 : 1) < AutoClipRules.maxClipsPerOutput else { break }
            guard total + candidate.duration + reserve <= AutoClipRules.outputMaxSeconds else { continue }
            chosen.append(candidate)
            total += candidate.duration
        }

        if let closing, total + closing.duration <= AutoClipRules.outputMaxSeconds {
            chosen.append(closing)
            total += closing.duration
        }

        // Video di bawah 30 detik ditandai di UI sebagai terlalu pendek, tetapi tetap dibuat selama memenuhi klip minimum.
        guard total >= AutoClipRules.minClipSeconds else { return nil }

        let hookFirst = chosen.first!
        let rest = Array(chosen.dropFirst())
        let middle = rest.filter { $0.kind != .penutup }.sorted { $0.start < $1.start }
        let tail = rest.filter { $0.kind == .penutup }.sorted { $0.start < $1.start }
        return OutputPlan(id: id, topicID: topicID, segments: [hookFirst] + middle + tail)
    }

    static func letter(_ index: Int) -> String {
        var value = index
        var result = ""
        repeat {
            result = String(Character(UnicodeScalar(UInt8(65 + value % 26)))) + result
            value = value / 26 - 1
        } while value >= 0
        return result
    }

    static func title(from text: String) -> String {
        let words = text.split(separator: " ").prefix(8).map(String.init)
        let joined = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".?!,;: "))
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
