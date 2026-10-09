import CoreGraphics
import Foundation

enum TrackKind: String, Codable, Equatable {
    case video
    case audio
}

enum TrimEdge: Equatable {
    case leading
    case trailing
}

struct SequenceSettings: Codable, Equatable {
    var width = 1920
    var height = 1080
    var frameRate = 30

    var renderSize: CGSize { CGSize(width: width, height: height) }
    var frameDuration: Ticks { Ticks(Ticks.perSecond / Int64(frameRate)) }
}

/// Transformasi visual per clip. Posisi dalam piksel sequence; rotasi positif searah jarum jam; crop dalam fraksi 0...0.45.
struct Transform: Codable, Equatable {
    var offsetX = 0.0
    var offsetY = 0.0
    var scale = 1.0
    var rotation = 0.0
    var cropLeft = 0.0
    var cropRight = 0.0
    var cropTop = 0.0
    var cropBottom = 0.0
}

/// Koreksi warna per clip. Dievaluasi di compositor sehingga preview dan export memakai definisi yang sama.
struct ColorGrade: Codable, Equatable {
    var exposure = 0.0        // EV, -3...3
    var contrast = 1.0        // 0.5...1.5
    var saturation = 1.0      // 0...2
    var temperature = 6500.0  // Kelvin, 2000...10000
    var tint = 0.0            // -150...150
    var highlights = 0.0      // -1...1
    var shadows = 0.0         // -1...1
    var lutPath: String?
    var lutIntensity = 1.0
}

/// Equalizer dasar tiga pita, dalam dB (-12...12).
struct EQSettings: Codable, Equatable {
    var low = 0.0
    var mid = 0.0
    var high = 0.0

    var isFlat: Bool { low == 0 && mid == 0 && high == 0 }
}

struct TitleStyle: Codable, Equatable {
    var text = "Judul"
    var fontName = "HelveticaNeue-Bold"
    var fontSize = 96.0
    var colorHex: UInt32 = 0xFFFFFF
    /// Posisi vertikal pusat teks, dari atas (0) ke bawah (1).
    var positionY = 0.85
}

/// Berkas media yang terdaftar di Library. Hanya menyimpan referensi ke file asli, tidak menyalinnya.
struct MediaItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var duration: Ticks
    var hasVideo: Bool
    var hasAudio: Bool
    var width: Int
    var height: Int
    var folder = ""

    var url: URL { URL(fileURLWithPath: path) }
    var kind: TrackKind { hasVideo ? .video : .audio }
    var isLarge: Bool { hasVideo && max(width, height) >= 3000 }
}

/// Potongan di timeline: media, atau teks (title) jika `title` terisi.
/// Durasi timeline = durasi sumber / speed.
struct Clip: Codable, Identifiable, Equatable {
    var id = UUID()
    var mediaID: UUID?
    var title: TitleStyle?
    var name: String
    var sourceStart: Ticks = .zero
    var timelineStart: Ticks
    var duration: Ticks
    var speed = 1.0
    var volume = 1.0
    var opacity = 1.0
    var fadeIn: Ticks = .zero
    var fadeOut: Ticks = .zero
    var transform = Transform()
    var grade = ColorGrade()
    var linkID: UUID?

    var end: Ticks { timelineStart + duration }
    var sourceDuration: Ticks { duration.scaled(by: speed) }
    var isTitle: Bool { title != nil }
}

struct Track: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: TrackKind
    var name: String
    var isMuted = false
    var isSolo = false
    var volume = 1.0
    var eq = EQSettings()
    var clips: [Clip] = []
}

struct Marker: Codable, Identifiable, Equatable {
    var id = UUID()
    var time: Ticks
    var name: String
}

/// Model proyek. Tidak bergantung pada UI; operasi edit adalah metode mutating
/// sehingga mudah diuji dan dibungkus undo/redo oleh `EditorStore`.
struct Project: Codable, Equatable {
    static let currentSchemaVersion = 2

    var schemaVersion = Project.currentSchemaVersion
    var name = "Proyek Tanpa Judul"
    var sequence = SequenceSettings()
    var media: [MediaItem] = []
    /// Urutan tampilan dari atas: V2, V1, A1, A2.
    var tracks: [Track] = Project.makeDefaultTracks()
    var markers: [Marker] = []

    static func makeDefaultTracks() -> [Track] {
        [
            Track(kind: .video, name: "V2"),
            Track(kind: .video, name: "V1"),
            Track(kind: .audio, name: "A1"),
            Track(kind: .audio, name: "A2"),
        ]
    }

    // MARK: - Pencarian

    var duration: Ticks { tracks.flatMap(\.clips).map(\.end).max() ?? .zero }
    var clipCount: Int { tracks.reduce(0) { $0 + $1.clips.count } }
    var minimumClipDuration: Ticks { sequence.frameDuration }

    func mediaItem(id: UUID) -> MediaItem? {
        media.first { $0.id == id }
    }

    func mediaItem(for clip: Clip) -> MediaItem? {
        clip.mediaID.flatMap { mediaItem(id: $0) }
    }

    func trackIndex(_ id: UUID) -> Int? {
        tracks.firstIndex { $0.id == id }
    }

    func clip(id: UUID) -> Clip? {
        location(of: id).map { tracks[$0.track].clips[$0.index] }
    }

    func location(of clipID: UUID) -> (track: Int, index: Int)? {
        for (trackIndex, track) in tracks.enumerated() {
            if let index = track.clips.firstIndex(where: { $0.id == clipID }) {
                return (trackIndex, index)
            }
        }
        return nil
    }

    /// Track default: video ke V1 (track video paling bawah), audio ke A1.
    func defaultTrackID(for kind: TrackKind) -> UUID? {
        switch kind {
        case .video: return tracks.last { $0.kind == .video }?.id
        case .audio: return tracks.first { $0.kind == .audio }?.id
        }
    }

    /// Track video paling atas (V2), tempat teks ditaruh agar tampil di depan.
    func topVideoTrackID() -> UUID? {
        tracks.first { $0.kind == .video }?.id
    }

    func endOfTrack(_ trackID: UUID) -> Ticks {
        guard let index = trackIndex(trackID) else { return .zero }
        return tracks[index].clips.map(\.end).max() ?? .zero
    }

    func isFree(trackIndex index: Int, start: Ticks, duration: Ticks, excluding ids: Set<UUID> = []) -> Bool {
        let end = start + duration
        return tracks[index].clips.allSatisfy { ids.contains($0.id) || $0.end <= start || $0.timelineStart >= end }
    }

    /// Semua clip yang tertaut dengan clip ini, termasuk dirinya sendiri.
    func linkGroup(of clipID: UUID) -> [UUID] {
        guard let clip = clip(id: clipID), let link = clip.linkID else { return [clipID] }
        return tracks.flatMap(\.clips).filter { $0.linkID == link }.map(\.id)
    }

    /// Batas valid untuk sisi clip. Mengembalikan posisi yang sudah dijepit ke rentang yang diizinkan.
    func clampedEdge(clipID: UUID, edge: TrimEdge, to proposed: Ticks, minimumDuration: Ticks) -> Ticks? {
        guard let loc = location(of: clipID) else { return nil }
        let track = tracks[loc.track]
        let clip = track.clips[loc.index]
        let item = mediaItem(for: clip)

        switch edge {
        case .leading:
            var lower = max(.zero, previousEnd(in: track, before: clip.timelineStart, excluding: clip.id))
            if item != nil {
                // Tidak boleh melewati awal media.
                lower = max(lower, clip.timelineStart - clip.sourceStart.scaled(by: 1 / clip.speed))
            }
            let upper = clip.end - minimumDuration
            return min(max(proposed, lower), max(lower, upper))

        case .trailing:
            var upper = nextStart(in: track, after: clip.end, excluding: clip.id) ?? .infinite
            if let item {
                // Tidak boleh melewati akhir media.
                let remaining = (item.duration - clip.sourceStart).scaled(by: 1 / clip.speed)
                upper = min(upper, clip.timelineStart + remaining)
            }
            let lower = clip.timelineStart + minimumDuration
            return min(max(proposed, lower), max(lower, upper))
        }
    }

    private func previousEnd(in track: Track, before start: Ticks, excluding id: UUID) -> Ticks {
        track.clips.filter { $0.id != id && $0.end <= start }.map(\.end).max() ?? .zero
    }

    private func nextStart(in track: Track, after end: Ticks, excluding id: UUID) -> Ticks? {
        track.clips.filter { $0.id != id && $0.timelineStart >= end }.map(\.timelineStart).min()
    }

    // MARK: - Media

    /// Mendaftarkan media ke Library. File yang sama tidak didaftarkan dua kali.
    @discardableResult
    mutating func registerMedia(_ item: MediaItem) -> MediaItem {
        if let existing = media.first(where: { $0.path == item.path }) {
            return existing
        }
        media.append(item)
        return item
    }

    /// Mengarahkan media yang hilang ke file baru; id dan folder dipertahankan agar clip tetap terhubung.
    mutating func relinkMedia(id: UUID, to item: MediaItem) {
        guard let index = media.firstIndex(where: { $0.id == id }) else { return }
        media[index].path = item.path
        media[index].duration = item.duration
        media[index].hasVideo = item.hasVideo
        media[index].hasAudio = item.hasAudio
        media[index].width = item.width
        media[index].height = item.height
    }

    mutating func setMediaFolder(id: UUID, folder: String) {
        guard let index = media.firstIndex(where: { $0.id == id }) else { return }
        media[index].folder = folder
    }

    // MARK: - Penempatan

    /// Menempatkan media di timeline. Gagal jika jenisnya tidak cocok atau posisinya bertabrakan.
    @discardableResult
    mutating func addClip(mediaID: UUID, toTrack trackID: UUID, at start: Ticks) -> UUID? {
        guard let item = mediaItem(id: mediaID),
              let index = trackIndex(trackID),
              tracks[index].kind == item.kind,
              start >= .zero,
              isFree(trackIndex: index, start: start, duration: item.duration) else { return nil }

        let clip = Clip(
            mediaID: mediaID,
            name: item.name,
            timelineStart: start,
            duration: item.duration
        )
        insert(clip, intoTrack: index)
        return clip.id
    }

    /// Menambahkan clip teks. Hanya untuk track video.
    @discardableResult
    mutating func addTitle(_ style: TitleStyle, toTrack trackID: UUID, at start: Ticks, duration: Ticks = Ticks(seconds: 3)) -> UUID? {
        guard let index = trackIndex(trackID),
              tracks[index].kind == .video,
              start >= .zero,
              isFree(trackIndex: index, start: start, duration: duration) else { return nil }

        let clip = Clip(title: style, name: style.text, timelineStart: start, duration: duration)
        insert(clip, intoTrack: index)
        return clip.id
    }

    // MARK: - Edit clip

    /// Membelah clip pada posisi timeline. Mengembalikan id bagian kanan.
    @discardableResult
    mutating func split(clipID: UUID, at time: Ticks) -> UUID? {
        guard let loc = location(of: clipID) else { return nil }
        let clip = tracks[loc.track].clips[loc.index]
        guard time > clip.timelineStart, time < clip.end else { return nil }

        let leftDuration = time - clip.timelineStart
        var right = clip
        right.id = UUID()
        right.timelineStart = time
        right.sourceStart = clip.sourceStart + leftDuration.scaled(by: clip.speed)
        right.duration = clip.duration - leftDuration
        right.fadeIn = .zero

        tracks[loc.track].clips[loc.index].duration = leftDuration
        tracks[loc.track].clips[loc.index].fadeOut = .zero
        insert(right, intoTrack: loc.track)
        return right.id
    }

    mutating func trimClip(id: UUID, edge: TrimEdge, to proposed: Ticks) {
        guard let target = clampedEdge(clipID: id, edge: edge, to: proposed, minimumDuration: minimumClipDuration),
              let loc = location(of: id) else { return }

        var clip = tracks[loc.track].clips[loc.index]
        switch edge {
        case .leading:
            let delta = target - clip.timelineStart
            clip.timelineStart = target
            clip.sourceStart = clip.sourceStart + delta.scaled(by: clip.speed)
            clip.duration = clip.duration - delta
        case .trailing:
            clip.duration = target - clip.timelineStart
        }
        clampFades(&clip)
        tracks[loc.track].clips[loc.index] = clip
    }

    /// Menghapus clip beserta grup tautannya. Dengan `ripple`, clip sesudahnya digeser agar tidak ada celah.
    mutating func deleteClips(ids: [UUID], ripple: Bool) {
        var trial = self
        var removed: [(track: Int, clip: Clip)] = []
        for id in Set(ids.flatMap { linkGroup(of: $0) }) {
            guard let loc = trial.location(of: id) else { continue }
            removed.append((loc.track, trial.tracks[loc.track].clips.remove(at: loc.index)))
        }

        if ripple {
            for item in removed.sorted(by: { $0.clip.timelineStart > $1.clip.timelineStart }) {
                for index in trial.tracks[item.track].clips.indices
                where trial.tracks[item.track].clips[index].timelineStart >= item.clip.end {
                    trial.tracks[item.track].clips[index].timelineStart = trial.tracks[item.track].clips[index].timelineStart - item.clip.duration
                }
            }
        }
        self = trial
    }

    /// Memindahkan clip beserta grup tautannya. Clip yang dipindah menjadi track tujuan; anggota lain tetap di track-nya.
    @discardableResult
    mutating func moveClip(id: UUID, toTrack trackID: UUID, at start: Ticks) -> Bool {
        guard let from = location(of: id),
              let to = trackIndex(trackID),
              tracks[to].kind == tracks[from.track].kind else { return false }

        let delta = max(start, .zero) - tracks[from.track].clips[from.index].timelineStart
        var trial = self
        var moved: [(id: UUID, clip: Clip, track: Int)] = []
        for memberID in linkGroup(of: id) {
            guard let loc = trial.location(of: memberID) else { continue }
            moved.append((memberID, trial.tracks[loc.track].clips.remove(at: loc.index), loc.track))
        }

        for item in moved {
            var clip = item.clip
            clip.timelineStart = item.clip.timelineStart + delta
            let targetTrack = item.id == id ? to : item.track
            guard clip.timelineStart >= .zero,
                  trial.isFree(trackIndex: targetTrack, start: clip.timelineStart, duration: clip.duration) else { return false }
            trial.insert(clip, intoTrack: targetTrack)
        }
        self = trial
        return true
    }

    /// Menggandakan clip tepat setelahnya; jika ruang itu terisi, ditempatkan di akhir track.
    @discardableResult
    mutating func duplicateClip(id: UUID) -> UUID? {
        guard let loc = location(of: id) else { return nil }
        var copy = tracks[loc.track].clips[loc.index]
        copy.id = UUID()
        copy.linkID = nil

        var start = copy.end
        if !isFree(trackIndex: loc.track, start: start, duration: copy.duration) {
            start = endOfTrack(tracks[loc.track].id)
        }
        copy.timelineStart = start
        insert(copy, intoTrack: loc.track)
        return copy.id
    }

    /// Mengubah speed dan durasi timeline. Gagal jika durasi baru bertabrakan.
    @discardableResult
    mutating func setSpeed(clipID: UUID, speed newSpeed: Double) -> Bool {
        guard let loc = location(of: clipID) else { return false }
        var clip = tracks[loc.track].clips[loc.index]
        let speed = min(max(newSpeed, 0.25), 4)
        let newDuration = clip.sourceDuration.scaled(by: 1 / speed)
        guard isFree(trackIndex: loc.track, start: clip.timelineStart, duration: newDuration, excluding: [clip.id]) else {
            return false
        }
        clip.speed = speed
        clip.duration = newDuration
        clampFades(&clip)
        tracks[loc.track].clips[loc.index] = clip
        return true
    }

    /// Mengubah properti clip. Fade selalu dijepit ke durasi clip.
    mutating func updateClip(id: UUID, _ change: (inout Clip) -> Void) {
        guard let loc = location(of: id) else { return }
        var clip = tracks[loc.track].clips[loc.index]
        change(&clip)
        clip.volume = min(max(clip.volume, 0), 2)
        clip.opacity = min(max(clip.opacity, 0), 1)
        clampFades(&clip)
        tracks[loc.track].clips[loc.index] = clip
    }

    private func clampFades(_ clip: inout Clip) {
        clip.fadeIn = min(max(clip.fadeIn, .zero), clip.duration)
        clip.fadeOut = min(max(clip.fadeOut, .zero), clip.duration)
    }

    /// Menautkan clip-clip terpilih menjadi satu grup.
    mutating func link(ids: [UUID]) {
        guard ids.count >= 2 else { return }
        let group = UUID()
        for id in ids {
            guard let loc = location(of: id) else { continue }
            tracks[loc.track].clips[loc.index].linkID = group
        }
    }

    mutating func unlink(clipID: UUID) {
        for id in linkGroup(of: clipID) {
            guard let loc = location(of: id) else { continue }
            tracks[loc.track].clips[loc.index].linkID = nil
        }
    }

    /// Memisahkan audio dari clip video ke track audio pertama, lalu menautkan keduanya.
    @discardableResult
    mutating func detachAudio(clipID: UUID) -> Bool {
        guard let loc = location(of: clipID),
              let item = mediaItem(for: tracks[loc.track].clips[loc.index]),
              item.hasVideo, item.hasAudio,
              let audioIndex = tracks.firstIndex(where: { $0.kind == .audio }) else { return false }

        let source = tracks[loc.track].clips[loc.index]
        guard isFree(trackIndex: audioIndex, start: source.timelineStart, duration: source.duration) else { return false }

        let group = source.linkID ?? UUID()
        var audioClip = Clip(
            mediaID: item.id,
            name: source.name,
            sourceStart: source.sourceStart,
            timelineStart: source.timelineStart,
            duration: source.duration
        )
        audioClip.speed = source.speed
        audioClip.volume = source.volume
        audioClip.linkID = group

        tracks[loc.track].clips[loc.index].volume = 0
        tracks[loc.track].clips[loc.index].linkID = group
        insert(audioClip, intoTrack: audioIndex)
        return true
    }

    // MARK: - Track

    mutating func updateTrack(id: UUID, _ change: (inout Track) -> Void) {
        guard let index = trackIndex(id) else { return }
        change(&tracks[index])
        tracks[index].volume = min(max(tracks[index].volume, 0), 2)
    }

    @discardableResult
    mutating func addTrack(kind: TrackKind) -> UUID {
        let track = Track(kind: kind, name: "")
        if kind == .video {
            tracks.insert(track, at: 0)
        } else {
            tracks.append(track)
        }
        renumberTracks()
        return track.id
    }

    /// Menghapus track kosong. Setidaknya satu track video dan satu track audio harus tetap ada.
    @discardableResult
    mutating func removeTrack(id: UUID) -> Bool {
        guard let index = trackIndex(id), tracks[index].clips.isEmpty else { return false }
        let kind = tracks[index].kind
        guard tracks.filter({ $0.kind == kind }).count > 1 else { return false }
        tracks.remove(at: index)
        renumberTracks()
        return true
    }

    /// Penomoran V dari bawah dan A dari atas, mengikuti konvensi NLE.
    private mutating func renumberTracks() {
        var videoNumber = tracks.filter { $0.kind == .video }.count
        var audioNumber = 0
        for index in tracks.indices {
            if tracks[index].kind == .video {
                tracks[index].name = "V\(videoNumber)"
                videoNumber -= 1
            } else {
                audioNumber += 1
                tracks[index].name = "A\(audioNumber)"
            }
        }
    }

    // MARK: - Marker

    @discardableResult
    mutating func addMarker(at time: Ticks, name: String) -> UUID {
        let marker = Marker(time: max(time, .zero), name: name)
        markers.append(marker)
        markers.sort { $0.time < $1.time }
        return marker.id
    }

    mutating func removeMarker(id: UUID) {
        markers.removeAll { $0.id == id }
    }

    mutating func renameMarker(id: UUID, name: String) {
        guard let index = markers.firstIndex(where: { $0.id == id }) else { return }
        markers[index].name = name
    }

    private mutating func insert(_ clip: Clip, intoTrack index: Int) {
        tracks[index].clips.append(clip)
        tracks[index].clips.sort { $0.timelineStart < $1.timelineStart }
    }
}

// MARK: - Migrasi berkas v1

/// Field yang ditambahkan setelah schema 1 diberi nilai default saat membaca berkas lama.
extension Clip {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        mediaID = try c.decodeIfPresent(UUID.self, forKey: .mediaID)
        title = try c.decodeIfPresent(TitleStyle.self, forKey: .title)
        name = try c.decode(String.self, forKey: .name)
        sourceStart = try c.decodeIfPresent(Ticks.self, forKey: .sourceStart) ?? .zero
        timelineStart = try c.decode(Ticks.self, forKey: .timelineStart)
        duration = try c.decode(Ticks.self, forKey: .duration)
        speed = try c.decodeIfPresent(Double.self, forKey: .speed) ?? 1
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        fadeIn = try c.decodeIfPresent(Ticks.self, forKey: .fadeIn) ?? .zero
        fadeOut = try c.decodeIfPresent(Ticks.self, forKey: .fadeOut) ?? .zero
        transform = try c.decodeIfPresent(Transform.self, forKey: .transform) ?? Transform()
        grade = try c.decodeIfPresent(ColorGrade.self, forKey: .grade) ?? ColorGrade()
        linkID = try c.decodeIfPresent(UUID.self, forKey: .linkID)
    }
}

extension Track {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        kind = try c.decode(TrackKind.self, forKey: .kind)
        name = try c.decode(String.self, forKey: .name)
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isSolo = try c.decodeIfPresent(Bool.self, forKey: .isSolo) ?? false
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        eq = try c.decodeIfPresent(EQSettings.self, forKey: .eq) ?? EQSettings()
        clips = try c.decodeIfPresent([Clip].self, forKey: .clips) ?? []
    }
}

extension MediaItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decode(String.self, forKey: .name)
        path = try c.decode(String.self, forKey: .path)
        duration = try c.decode(Ticks.self, forKey: .duration)
        hasVideo = try c.decode(Bool.self, forKey: .hasVideo)
        hasAudio = try c.decode(Bool.self, forKey: .hasAudio)
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
    }
}

extension Project {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Proyek Tanpa Judul"
        sequence = try c.decodeIfPresent(SequenceSettings.self, forKey: .sequence) ?? SequenceSettings()
        media = try c.decodeIfPresent([MediaItem].self, forKey: .media) ?? []
        tracks = try c.decodeIfPresent([Track].self, forKey: .tracks) ?? Project.makeDefaultTracks()
        markers = try c.decodeIfPresent([Marker].self, forKey: .markers) ?? []
    }
}
