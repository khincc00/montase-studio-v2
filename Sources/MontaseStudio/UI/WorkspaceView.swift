import SwiftUI

/// Layout workspace: Edit, Color, Audio, dan Export. Semuanya memakai proyek dan timeline yang sama.
struct WorkspaceView: View {
    @Bindable var app: AppState
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar(app: app)
            Divider()
            content
            StatusBar(app: app)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // Pintasan huruf tunggal. Field teks yang sedang fokus menerima tombol ini lebih dulu.
        .onKeyPress(.space) {
            app.playback.togglePlayback()
            return .handled
        }
        .onKeyPress(KeyEquivalent("s")) {
            app.store.splitAtPlayhead()
            return .handled
        }
        .onKeyPress(KeyEquivalent("m")) {
            app.store.addMarker()
            return .handled
        }
        .onKeyPress(.delete) {
            app.store.deleteSelected(ripple: false)
            return .handled
        }
        .onKeyPress(.leftArrow) {
            app.playback.step(frames: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            app.playback.step(frames: 1)
            return .handled
        }
        .sheet(isPresented: $app.isPaletteOpen) {
            CommandPalette(app: app)
        }
        .alert("Terjadi kesalahan", isPresented: Binding(
            get: { app.alertMessage != nil },
            set: { if !$0 { app.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.workspace {
        case .export:
            ExportPanel(app: app)
        case .edit, .color, .audio:
            VStack(spacing: 0) {
                workspaceTop
                    .frame(maxHeight: .infinity)
                Divider()
                TimelineView(app: app)
                    .frame(height: 300)
            }
        }
    }

    @ViewBuilder
    private var workspaceTop: some View {
        switch app.workspace {
        case .edit:
            HStack(spacing: 0) {
                LibraryView(app: app)
                    .frame(width: 260)
                Divider()
                ViewerView(app: app)
                    .frame(maxWidth: .infinity)
                Divider()
                InspectorView(app: app)
                    .frame(width: 280)
            }
        case .color:
            HStack(spacing: 0) {
                ViewerView(app: app)
                    .frame(maxWidth: .infinity)
                Divider()
                ColorPanel(app: app)
                    .frame(width: 340)
            }
        case .audio:
            HStack(spacing: 0) {
                ViewerView(app: app)
                    .frame(maxWidth: .infinity)
                Divider()
                AudioPanel(app: app)
                    .frame(width: 340)
            }
        case .export:
            EmptyView()
        }
    }
}

private struct TopBar: View {
    @Bindable var app: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "film.stack")
                .foregroundStyle(Theme.accent)
            Text("Montase Studio")
                .font(.headline)
            Text(app.store.project.name)
                .foregroundStyle(Theme.textSecondary)

            Spacer()

            Picker("Workspace", selection: $app.workspace) {
                ForEach(Workspace.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)

            Spacer()

            Button { app.store.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .help("Urungkan (⌘Z)")
                .disabled(!app.store.canUndo)
            Button { app.store.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                .help("Ulangi (⇧⌘Z)")
                .disabled(!app.store.canRedo)
            Button { app.isPaletteOpen = true } label: { Image(systemName: "command") }
                .help("Command palette (⌘K)")
            Button { app.show(.export) } label: { Label("Ekspor", systemImage: "square.and.arrow.up") }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(app.store.project.duration <= .zero)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }
}

private struct StatusBar: View {
    let app: AppState

    private var store: EditorStore { app.store }

    var body: some View {
        HStack(spacing: 14) {
            Label(
                store.hasUnsavedChanges ? "Belum disimpan" : "Tersimpan",
                systemImage: store.hasUnsavedChanges ? "circle.fill" : "checkmark.circle"
            )
            Text("Klip \(store.project.clipCount)")
            Text("Durasi \(store.project.duration.clockString)")

            if let notice = store.notice {
                Text(notice)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
            }

            Spacer()

            if app.exporter.isRunning {
                ProgressView(value: app.exporter.progress)
                    .frame(width: 120)
                Text("Ekspor \(Int(app.exporter.progress * 100))%")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }
}
