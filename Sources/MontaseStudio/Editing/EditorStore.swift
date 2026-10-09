import Foundation
import Observation

/// Menyimpan proyek yang sedang diedit. Setiap perubahan lewat `edit` menjadi satu langkah undo.
@MainActor
@Observable
final class EditorStore {
    struct Step {
        let label: String
        let project: Project
    }

    private(set) var project: Project
    /// Jumlah langkah undo yang disimpan. Langkah terlama dibuang saat batas terlampaui.
    static let undoLimit = 50

    private(set) var undoSteps: [Step] = []
    private(set) var redoSteps: [Step] = []
    private(set) var fileURL: URL?
    private(set) var hasUnsavedChanges: Bool
    private(set) var notice: String?

    var playhead: Ticks = .zero
    var selectedClipID: UUID?
    var pixelsPerSecond: Double = 40
    var snappingEnabled = true

    /// Dipanggil setelah setiap perubahan proyek; dipakai untuk autosave dan rebuild preview.
    @ObservationIgnored var didChange: (() -> Void)?

    init(project: Project = Project(), hasUnsavedChanges: Bool = false) {
        self.project = project
        self.hasUnsavedChanges = hasUnsavedChanges
    }

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }
    var undoLabel: String? { undoSteps.last?.label }
    var selectedClip: Clip? { selectedClipID.flatMap { project.clip(id: $0) } }

    // MARK: - Inti edit

    func edit(_ label: String, _ change: (inout Project) -> Void) {
        let before = project
        change(&project)
        guard project != before else { return }

        undoSteps.append(Step(label: label, project: before))
        if undoSteps.count > Self.undoLimit { undoSteps.removeFirst() }
        redoSteps.removeAll()
        finishChange()
    }

    func undo() {
        guard let step = undoSteps.popLast() else { return }
        redoSteps.append(Step(label: step.label, project: project))
        project = step.project
        finishChange()
    }

    func redo() {
        guard let step = redoSteps.popLast() else { return }
        undoSteps.append(Step(label: step.label, project: project))
        project = step.project
        finishChange()
    }

    private func finishChange() {
        hasUnsavedChanges = true
        if let id = selectedClipID, project.clip(id: id) == nil {
            selectedClipID = nil
        }
        didChange?()
    }

    // MARK: - Dokumen

    func replaceProject(_ newProject: Project, fileURL url: URL?) {
        project = newProject
        fileURL = url
        undoSteps.removeAll()
        redoSteps.removeAll()
        hasUnsavedChanges = false
        playhead = .zero
        selectedClipID = nil
        didChange?()
    }

    func markSaved(to url: URL) {
        fileURL = url
        hasUnsavedChanges = false
    }

    func notify(_ text: String) {
        notice = text
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.notice == text { self?.notice = nil }
        }
    }

    // MARK: - Media

    func registerMedia(_ item: MediaItem) {
        edit("Impor \(item.name)") { _ = $0.registerMedia(item) }
    }

    func relinkMedia(id: UUID, to item: MediaItem) {
        edit("Relink Media") { $0.relinkMedia(id: id, to: item) }
        notify("Media dihubungkan ulang.")
    }

    func setFolder(mediaID: UUID, folder: String) {
        edit("Pindah Folder") { $0.setMediaFolder(id: mediaID, folder: folder) }
    }

    /// Menambahkan media ke timeline. Tanpa `trackID`, memakai track default dan posisi di akhir track.
    @discardableResult
    func addToTimeline(mediaID: UUID, trackID: UUID? = nil, at start: Ticks? = nil) -> Bool {
        guard let item = project.mediaItem(id: mediaID),
              let track = trackID ?? project.defaultTrackID(for: item.kind) else {
            notify("Media tidak bisa ditambahkan ke timeline.")
            return false
        }
        let position = start ?? project.endOfTrack(track)

        var placed = false
        edit("Tambah \(item.name)") { placed = $0.addClip(mediaID: mediaID, toTrack: track, at: position) != nil }
        if !placed {
            notify("Media tidak cocok dengan track atau bertabrakan dengan clip lain.")
        }
        return placed
    }

    @discardableResult
    func addTitle(at start: Ticks? = nil) -> Bool {
        guard let track = project.topVideoTrackID() else { return false }
        let position = start ?? playhead
        var placed = false
        edit("Tambah Teks") { placed = $0.addTitle(TitleStyle(), toTrack: track, at: position) != nil }
        if !placed { notify("Teks tidak bisa ditempatkan di posisi itu.") }
        return placed
    }

    // MARK: - Operasi timeline

    @discardableResult
    func moveClip(_ clipID: UUID, toTrack trackID: UUID, at start: Ticks) -> Bool {
        var moved = false
        edit("Pindah Clip") { moved = $0.moveClip(id: clipID, toTrack: trackID, at: start) }
        return moved
    }

    func trimClip(_ clipID: UUID, edge: TrimEdge, to time: Ticks) {
        edit(edge == .leading ? "Trim Awal" : "Trim Akhir") { $0.trimClip(id: clipID, edge: edge, to: time) }
    }

    /// Membelah clip di playhead. Anggota grup tertaut ikut terbelah.
    func splitAtPlayhead() {
        let time = playhead
        let candidates = project.tracks
            .flatMap(\.clips)
            .filter { $0.timelineStart < time && time < $0.end }
            .filter { selectedClipID == nil || $0.id == selectedClipID }
        guard !candidates.isEmpty else {
            notify("Tidak ada clip di posisi playhead.")
            return
        }
        let targets = Set(candidates.flatMap { project.linkGroup(of: $0.id) })

        edit("Belah Clip") { project in
            for id in targets {
                project.split(clipID: id, at: time)
            }
        }
    }

    func deleteSelected(ripple: Bool) {
        guard let id = selectedClipID else { return }
        edit(ripple ? "Hapus & Rapatkan" : "Hapus Clip") { $0.deleteClips(ids: [id], ripple: ripple) }
        selectedClipID = nil
    }

    func duplicateSelected() {
        guard let id = selectedClipID else { return }
        var newID: UUID?
        edit("Duplikat Clip") { newID = $0.duplicateClip(id: id) }
        if let newID { selectedClipID = newID }
    }

    @discardableResult
    func setSpeed(_ clipID: UUID, _ speed: Double) -> Bool {
        var changed = false
        edit("Ubah Kecepatan") { changed = $0.setSpeed(clipID: clipID, speed: speed) }
        if !changed { notify("Kecepatan itu membuat clip bertabrakan dengan clip lain.") }
        return changed
    }

    func updateClip(_ clipID: UUID, _ label: String, _ change: (inout Clip) -> Void) {
        edit(label) { $0.updateClip(id: clipID, change) }
    }

    func updateTrack(_ trackID: UUID, _ label: String, _ change: (inout Track) -> Void) {
        edit(label) { $0.updateTrack(id: trackID, change) }
    }

    func toggleMute(trackID: UUID) {
        updateTrack(trackID, "Bisukan Track") { $0.isMuted.toggle() }
    }

    func toggleSolo(trackID: UUID) {
        updateTrack(trackID, "Solo Track") { $0.isSolo.toggle() }
    }

    func addTrack(kind: TrackKind) {
        edit("Tambah Track") { _ = $0.addTrack(kind: kind) }
    }

    func removeTrack(id: UUID) {
        var removed = false
        edit("Hapus Track") { removed = $0.removeTrack(id: id) }
        if !removed { notify("Track harus kosong dan tidak boleh menjadi satu-satunya track jenisnya.") }
    }

    /// Menautkan clip terpilih dengan clip lain yang sejajar di waktu dan jenisnya sama.
    func linkSelected() {
        guard let id = selectedClipID, let clip = project.clip(id: id) else { return }
        let partners = project.tracks.flatMap(\.clips).filter {
            $0.id != id && $0.timelineStart == clip.timelineStart && $0.mediaID == clip.mediaID
        }.map(\.id)
        guard !partners.isEmpty else {
            notify("Tidak ada clip sejajar untuk ditautkan.")
            return
        }
        edit("Tautkan Clip") { $0.link(ids: [id] + partners) }
    }

    func unlinkSelected() {
        guard let id = selectedClipID else { return }
        edit("Lepas Tautan") { $0.unlink(clipID: id) }
    }

    func detachAudioSelected() {
        guard let id = selectedClipID else { return }
        var done = false
        edit("Pisahkan Audio") { done = $0.detachAudio(clipID: id) }
        if !done { notify("Audio tidak bisa dipisahkan: tidak ada track audio kosong di posisi ini.") }
    }

    // MARK: - Marker

    func addMarker() {
        let time = playhead
        edit("Tambah Marker") { _ = $0.addMarker(at: time, name: "Marker") }
    }

    func removeMarker(id: UUID) {
        edit("Hapus Marker") { $0.removeMarker(id: id) }
    }

    func renameMarker(id: UUID, name: String) {
        edit("Ubah Marker") { $0.renameMarker(id: id, name: name) }
    }
}
