import AppKit
import Dispatch
import Observation
import UniformTypeIdentifiers

enum Workspace: String, CaseIterable, Identifiable {
    case edit
    case color
    case audio
    case export

    var id: String { rawValue }
    var title: String {
        switch self {
        case .edit: return "Edit"
        case .color: return "Color"
        case .audio: return "Audio"
        case .export: return "Export"
        }
    }
    var symbol: String {
        switch self {
        case .edit: return "scissors"
        case .color: return "paintpalette"
        case .audio: return "waveform"
        case .export: return "square.and.arrow.up"
        }
    }
}

/// Aksi yang muncul di command palette.
struct PaletteCommand: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: String
    let action: () -> Void
}

/// Titik pusat state aplikasi. Editor, playback, dan export dibagi ke seluruh UI dan menu.
@MainActor
@Observable
final class AppState {
    let store: EditorStore
    let waveforms = WaveformStore()
    let scopes = ScopeStore()
    let playback: PlaybackController
    let exporter = ExportController()

    var workspace: Workspace = .edit
    var isPaletteOpen = false
    var alertMessage: String?

    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var autosaveFailed = false
    @ObservationIgnored private var pressureSource: DispatchSourceMemoryPressure?
    private static let projectType = UTType(filenameExtension: ProjectStorage.fileExtension) ?? .json

    init() {
        var recovered: Project?
        var recoveryFailed = false
        if FileManager.default.fileExists(atPath: ProjectStorage.recoveryURL.path) {
            do {
                recovered = try ProjectStorage.read(from: ProjectStorage.recoveryURL)
            } catch {
                recoveryFailed = true
            }
        }
        let store = EditorStore(project: recovered ?? Project(), hasUnsavedChanges: recovered != nil)
        self.store = store
        self.playback = PlaybackController(store: store)

        store.didChange = { [weak self] in self?.projectDidChange() }
        playback.onFrameChanged = { [weak self] in self?.refreshScope() }
        startMemoryPressureMonitor()

        if recoveryFailed {
            alertMessage = "Pemulihan gagal: berkas autosave rusak dan tidak bisa dibuka. Proyek kosong dimuat; berkas pemulihan tetap tersimpan di Application Support."
        }

        Task { [weak self] in
            self?.ensureMediaWork()
            self?.refreshPreview()
        }
    }

    private func projectDidChange() {
        ensureMediaWork()
        refreshPreview()
        scheduleAutosave()
    }

    func refreshPreview() {
        playback.scheduleRebuild(store.project)
    }

    private func refreshScope() {
        scopes.refresh(output: playback.lastOutput, at: store.playhead)
    }

    /// Gelombang untuk setiap media. Idempotent, jadi aman dipanggil setiap perubahan.
    private func ensureMediaWork() {
        for item in store.project.media {
            waveforms.request(item)
        }
    }

    /// Tekanan memori menurunkan kualitas preview. Kualitas kembali normal saat tekanan berakhir.
    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                guard let self, let source = self.pressureSource else { return }
                let critical = source.data.contains(.critical)
                if self.playback.quality != .quarter {
                    self.playback.quality = critical ? .quarter : .half
                    self.store.notify("Tekanan memori: kualitas preview diturunkan.")
                }
            }
        }
        source.resume()
        pressureSource = source
    }

    // MARK: - Dokumen

    func newProject() {
        guard confirmUnsavedChanges() else { return }
        store.replaceProject(Project(), fileURL: nil)
        discardRecovery()
    }

    func openProject() {
        guard confirmUnsavedChanges() else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.load(url) }
        }
    }

    func save() {
        if let url = store.fileURL {
            write(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.projectType]
        panel.nameFieldStringValue = "\(store.project.name).\(ProjectStorage.fileExtension)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.write(to: url) }
        }
    }

    private func load(_ url: URL) {
        do {
            let project = try ProjectStorage.read(from: url)
            store.replaceProject(project, fileURL: url)
            discardRecovery()
            ensureMediaWork()
            refreshPreview()
        } catch {
            alertMessage = "Gagal membuka proyek: \(error.localizedDescription)"
        }
    }

    private func write(to url: URL) {
        do {
            try ProjectStorage.write(store.project, to: url)
            store.markSaved(to: url)
            autosaveTask?.cancel()
            try? FileManager.default.removeItem(at: ProjectStorage.recoveryURL)
            store.notify("Proyek disimpan.")
        } catch {
            alertMessage = "Gagal menyimpan proyek: \(error.localizedDescription)"
        }
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        let snapshot = store.project
        autosaveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                try ProjectStorage.write(snapshot, to: ProjectStorage.recoveryURL)
                autosaveFailed = false
            } catch {
                // Peringatan hanya sekali per kegagalan, agar tidak muncul setiap perubahan.
                guard !autosaveFailed else { return }
                autosaveFailed = true
                alertMessage = "Autosave gagal: \(error.localizedDescription). Perubahan terbaru belum terlindungi; simpan proyek secara manual (⌘S)."
            }
        }
    }

    /// Membatalkan autosave yang tertunda dan menghapus pemulihan. Dipakai saat proyek diganti, agar
    /// proyek kosong atau proyek yang baru dibuka tidak meninggalkan pemulihan palsu saat aplikasi dibuka lagi.
    private func discardRecovery() {
        autosaveTask?.cancel()
        autosaveFailed = false
        try? FileManager.default.removeItem(at: ProjectStorage.recoveryURL)
    }

    /// Menanyakan sebelum perubahan yang belum disimpan dibuang. Mengembalikan false jika pengguna membatalkan.
    private func confirmUnsavedChanges() -> Bool {
        guard store.hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "Simpan perubahan proyek?"
        alert.informativeText = "Perubahan yang belum disimpan akan hilang."
        alert.addButton(withTitle: "Simpan")
        alert.addButton(withTitle: "Jangan Simpan")
        alert.addButton(withTitle: "Batal")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            // Jika proyek belum punya file, Simpan membuka panel secara asinkron; aksi perlu diulang setelahnya.
            save()
            return !store.hasUnsavedChanges
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - Media

    func presentImportPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audiovisualContent]
        panel.begin { [weak self] response in
            guard response == .OK else { return }
            let urls = panel.urls
            Task { @MainActor in await self?.importMedia(urls: urls) }
        }
    }

    func importMedia(urls: [URL]) async {
        for url in urls {
            do {
                let item = try await MediaImporter.probe(url)
                store.registerMedia(item)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    /// Membuka panel untuk mengarahkan media yang hilang ke file baru.
    func presentRelinkPanel(for item: MediaItem) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audiovisualContent]
        panel.message = "Pilih file pengganti untuk \(item.name)"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                do {
                    let probed = try await MediaImporter.probe(url)
                    self.store.relinkMedia(id: item.id, to: probed)
                    self.ensureMediaWork()
                    self.refreshPreview()
                } catch {
                    self.alertMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: - Workspace, export, dan palette

    func show(_ workspace: Workspace) {
        self.workspace = workspace
    }

    func startExport() {
        let project = store.project
        guard project.duration > .zero else {
            store.notify("Timeline kosong; tidak ada yang bisa diekspor.")
            return
        }
        let suffix = exporter.settings.fileSuffix

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "\(project.name)\(suffix).mp4"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                await self.exporter.export(project, to: url)
                if let error = self.exporter.lastError {
                    self.alertMessage = error
                } else {
                    self.store.notify("Ekspor selesai: \(url.lastPathComponent)")
                }
            }
        }
    }

    var paletteCommands: [PaletteCommand] {
        [
            PaletteCommand(title: "Proyek Baru", shortcut: "⌘N") { self.newProject() },
            PaletteCommand(title: "Buka Proyek", shortcut: "⌘O") { self.openProject() },
            PaletteCommand(title: "Simpan", shortcut: "⌘S") { self.save() },
            PaletteCommand(title: "Simpan Sebagai", shortcut: "⇧⌘S") { self.saveAs() },
            PaletteCommand(title: "Impor Media", shortcut: "⌘I") { self.presentImportPanel() },
            PaletteCommand(title: "Urungkan", shortcut: "⌘Z") { self.store.undo() },
            PaletteCommand(title: "Ulangi", shortcut: "⇧⌘Z") { self.store.redo() },
            PaletteCommand(title: "Putar / Jeda", shortcut: "Space") { self.playback.togglePlayback() },
            PaletteCommand(title: "Belah pada Playhead", shortcut: "S") { self.store.splitAtPlayhead() },
            PaletteCommand(title: "Duplikat Clip", shortcut: "⌘D") { self.store.duplicateSelected() },
            PaletteCommand(title: "Hapus Clip", shortcut: "⌫") { self.store.deleteSelected(ripple: false) },
            PaletteCommand(title: "Hapus & Rapatkan", shortcut: "⇧⌫") { self.store.deleteSelected(ripple: true) },
            PaletteCommand(title: "Tambah Teks di Playhead", shortcut: "") { self.store.addTitle() },
            PaletteCommand(title: "Tambah Marker di Playhead", shortcut: "M") { self.store.addMarker() },
            PaletteCommand(title: "Tautkan Clip Sejajar", shortcut: "") { self.store.linkSelected() },
            PaletteCommand(title: "Lepas Tautan", shortcut: "") { self.store.unlinkSelected() },
            PaletteCommand(title: "Pisahkan Audio dari Video", shortcut: "") { self.store.detachAudioSelected() },
            PaletteCommand(title: "Tambah Track Video", shortcut: "") { self.store.addTrack(kind: .video) },
            PaletteCommand(title: "Tambah Track Audio", shortcut: "") { self.store.addTrack(kind: .audio) },
            PaletteCommand(title: "Aktifkan / Matikan Snap", shortcut: "") { self.store.snappingEnabled.toggle() },
            PaletteCommand(title: "Tampilkan Sebelum / Sesudah", shortcut: "") { self.playback.showOriginal.toggle(); self.refreshPreview() },
            PaletteCommand(title: "Workspace Edit", shortcut: "⌘1") { self.show(.edit) },
            PaletteCommand(title: "Workspace Color", shortcut: "⌘2") { self.show(.color) },
            PaletteCommand(title: "Workspace Audio", shortcut: "⌘3") { self.show(.audio) },
            PaletteCommand(title: "Workspace Export", shortcut: "⌘4") { self.show(.export) },
            PaletteCommand(title: "Ekspor…", shortcut: "⌘E") { self.show(.export) },
        ]
    }
}
