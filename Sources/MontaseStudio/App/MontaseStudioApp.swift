import SwiftUI

@main
struct MontaseStudioApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            WorkspaceView(app: app)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1100, minHeight: 680)
                .fontDesign(.rounded)
        }
        .commands {
            EditorCommands(app: app)
        }
    }
}

/// Menu. Pintasan huruf tunggal (Space, S, M, ⌫, panah) ditangani di `WorkspaceView` agar tidak
/// bertabrakan dengan pengetikan di field teks.
struct EditorCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Proyek Baru") { app.newProject() }
                .keyboardShortcut("n")
            Button("Buka Proyek…") { app.openProject() }
                .keyboardShortcut("o")
            Divider()
            Button("Impor Media…") { app.presentImportPanel() }
                .keyboardShortcut("i")
        }

        CommandGroup(replacing: .saveItem) {
            Button("Simpan") { app.save() }
                .keyboardShortcut("s")
            Button("Simpan Sebagai…") { app.saveAs() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
        }

        CommandGroup(replacing: .undoRedo) {
            Button(app.store.undoLabel.map { "Urungkan \($0)" } ?? "Urungkan") { app.store.undo() }
                .keyboardShortcut("z")
                .disabled(!app.store.canUndo)
            Button("Ulangi") { app.store.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!app.store.canRedo)
        }

        CommandMenu("Timeline") {
            Button("Putar / Jeda") { app.playback.togglePlayback() }
            Button("Belah pada Playhead") { app.store.splitAtPlayhead() }
            Button("Duplikat Clip") { app.store.duplicateSelected() }
                .keyboardShortcut("d")
            Button("Hapus Clip") { app.store.deleteSelected(ripple: false) }
            Button("Hapus & Rapatkan") { app.store.deleteSelected(ripple: true) }
            Divider()
            Button("Tambah Teks") { app.store.addTitle() }
            Button("Tambah Marker") { app.store.addMarker() }
            Button("Tautkan Clip Sejajar") { app.store.linkSelected() }
            Button("Lepas Tautan") { app.store.unlinkSelected() }
            Button("Pisahkan Audio dari Video") { app.store.detachAudioSelected() }
            Divider()
            Button("Ekspor…") { app.show(.export) }
                .keyboardShortcut("e")
        }

        CommandMenu("Workspace") {
            ForEach(Array(Workspace.allCases.enumerated()), id: \.element.id) { index, workspace in
                Button(workspace.title) { app.show(workspace) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Command Palette…") { app.isPaletteOpen = true }
                .keyboardShortcut("k")
        }
    }
}
