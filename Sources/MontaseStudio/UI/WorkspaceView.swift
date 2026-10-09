import SwiftUI

/// Layout workspace: Edit, Color, Audio, dan Export. Semuanya memakai proyek dan timeline yang sama.
struct WorkspaceView: View {
    @Bindable var app: AppState
    @FocusState private var focused: Bool
    /// Tinggi timeline bisa diatur dengan menyeret garis pemisah.
    @State private var timelineHeight: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            TopBar(app: app)
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
        .onKeyPress(.home) {
            app.playback.seek(to: .zero)
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
        .sheet(isPresented: $app.isAutoClipOpen) {
            AutoClipPanel(app: app)
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
                .transition(.opacity)
        case .edit, .color, .audio:
            VStack(spacing: 0) {
                workspaceTop
                    .frame(maxHeight: .infinity)
                VerticalResizeHandle(height: $timelineHeight, range: 180...720)
                TimelineView(app: app)
                    .frame(height: timelineHeight)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var workspaceTop: some View {
        switch app.workspace {
        case .edit:
            HStack(spacing: 0) {
                LibraryView(app: app)
                    .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
                Hairline(vertical: true)
                ViewerView(app: app)
                    .frame(minWidth: 360, maxWidth: .infinity)
                Hairline(vertical: true)
                InspectorView(app: app)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
            }
        case .color:
            HStack(spacing: 0) {
                ViewerView(app: app)
                    .frame(minWidth: 360, maxWidth: .infinity)
                Hairline(vertical: true)
                ColorPanel(app: app)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            }
        case .audio:
            HStack(spacing: 0) {
                ViewerView(app: app)
                    .frame(minWidth: 360, maxWidth: .infinity)
                Hairline(vertical: true)
                AudioPanel(app: app)
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            }
        case .export:
            EmptyView()
        }
    }
}

/// Garis tipis pemisah panel.
struct Hairline: View {
    var vertical: Bool

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - Bilah atas

private struct TopBar: View {
    @Bindable var app: AppState

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "film.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 26, height: 26)
                    .background(
                        LinearGradient(colors: [Theme.accent, Theme.videoClipTop], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .hoverHelp("Montase Studio")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Montase Studio")
                        .font(.caption.weight(.bold))
                    Text(app.store.project.name)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 160, alignment: .leading)
            }

            Spacer(minLength: 12)

            WorkspaceTabs(selection: $app.workspace)

            Spacer(minLength: 12)

            HStack(spacing: 4) {
                IconButton(systemImage: "arrow.uturn.backward", help: "Urungkan", shortcut: "⌘Z",
                           isDisabled: !app.store.canUndo) { app.store.undo() }
                IconButton(systemImage: "arrow.uturn.forward", help: "Ulangi", shortcut: "⇧⌘Z",
                           isDisabled: !app.store.canRedo) { app.store.redo() }
                IconButton(systemImage: "wand.and.stars", help: "Auto Clip: potong video panjang jadi klip pendek") {
                    app.isAutoClipOpen = true
                }
                IconButton(systemImage: "command", help: "Command palette", shortcut: "⌘K") {
                    app.isPaletteOpen = true
                }
            }

            Button { app.show(.export) } label: {
                Label("Ekspor", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.prominentPill)
            .disabled(app.store.project.duration <= .zero)
            .hoverHelp("Buka workspace ekspor", shortcut: "⌘E")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Hairline(vertical: false) }
    }
}

/// Pemilih workspace berbentuk kapsul. Latar terpilih bergeser dengan animasi.
private struct WorkspaceTabs: View {
    @Binding var selection: Workspace
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Workspace.allCases.enumerated()), id: \.element.id) { index, tab in
                let selected = selection == tab
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.symbol)
                        .font(.callout.weight(.medium))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
                        .background {
                            if selected {
                                Capsule(style: .continuous)
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .hoverHelp("Workspace \(tab.title)", shortcut: "⌘\(index + 1)")
            }
        }
        .padding(3)
        .background(Theme.raised, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Theme.divider))
    }
}

// MARK: - Bilah status

private struct StatusBar: View {
    let app: AppState

    private var store: EditorStore { app.store }

    private var hint: String {
        switch app.workspace {
        case .edit: return "Space putar · S belah · ⌫ hapus · ⌘D duplikat · seret tepi klip untuk memotong"
        case .color: return "Pilih klip video di timeline untuk mengatur warnanya · Sebelum/Sesudah untuk membandingkan"
        case .audio: return "Geser fader untuk mengatur level · klik dua kali nama pengaturan untuk mengembalikannya"
        case .export: return "Pilih resolusi, orientasi, dan kualitas, lalu tekan Mulai Ekspor"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(store.hasUnsavedChanges ? Theme.warning : Theme.accent)
                    .frame(width: 7, height: 7)
                Text(store.hasUnsavedChanges ? "Belum disimpan" : "Tersimpan")
            }
            Text("\(store.project.clipCount) klip")
            Text(store.project.duration.clockString).monospacedDigit()

            if let notice = store.notice {
                Text(notice)
                    .foregroundStyle(Theme.warning)
                    .lineLimit(1)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 12)

            if app.exporter.isRunning {
                ProgressView(value: app.exporter.progress)
                    .tint(Theme.accent)
                    .frame(width: 120)
                Text("Ekspor \(Int(app.exporter.progress * 100))%")
                    .monospacedDigit()
            } else {
                Text(hint)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Theme.panel)
        .overlay(alignment: .top) { Hairline(vertical: false) }
        .animation(.easeOut(duration: 0.2), value: store.notice)
    }
}
