import AppKit
import SwiftUI

/// Workspace Color: koreksi warna per clip, LUT .cube, dan scope histogram.
struct ColorPanel: View {
    @Bindable var app: AppState

    private var store: EditorStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("COLOR").panelTitle()
                    Spacer()
                    if let clip = store.selectedClip, !clip.isTitle {
                        Text(clip.name)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: Binding(
                        get: { app.scopes.isEnabled },
                        set: { app.scopes.isEnabled = $0 }
                    )) {
                        Label("Scope histogram", systemImage: "chart.bar.fill")
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .hoverHelp("Tampilkan histogram luminansi frame di playhead")

                    if app.scopes.isEnabled {
                        scope
                    }

                    Toggle(isOn: Binding(
                        get: { app.playback.showOriginal },
                        set: { value in
                            app.playback.showOriginal = value
                            app.refreshPreview()
                        }
                    )) {
                        Label("Bandingkan dengan sumber", systemImage: "rectangle.lefthalf.inset.filled")
                    }
                    .toggleStyle(.switch)
                    .tint(Theme.accent)
                    .hoverHelp("Tampilkan sumber tanpa koreksi untuk dibandingkan")
                }
                .card()

                if let clip = store.selectedClip, !clip.isTitle {
                    grade(clip)
                        .id(clip.id)
                } else {
                    EmptyStateView(
                        systemImage: "paintpalette",
                        title: "Pilih klip video",
                        message: "Klik klip video di timeline untuk mengatur warnanya."
                    )
                    .frame(height: 220)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private var scope: some View {
        Canvas { context, size in
            let bins = app.scopes.bins
            guard !bins.isEmpty else { return }
            let width = size.width / CGFloat(bins.count)
            for (index, value) in bins.enumerated() {
                let height = CGFloat(value) * size.height
                let rect = CGRect(x: CGFloat(index) * width, y: size.height - height, width: width, height: height)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.9), Theme.accent.opacity(0.3)]),
                    startPoint: CGPoint(x: 0, y: 0),
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }
        }
        .frame(height: 96)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if app.scopes.bins.isEmpty {
                Text("Diam atau seek untuk memperbarui scope")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private func grade(_ clip: Clip) -> some View {
        let g = clip.grade
        func set(_ label: String = "Koreksi Warna", _ change: @escaping (inout ColorGrade) -> Void) {
            store.updateClip(clip.id, label) { change(&$0.grade) }
        }

        return VStack(alignment: .leading, spacing: 10) {
            CollapsibleSection(title: "Tonal", systemImage: "circle.lefthalf.filled") {
                VStack(alignment: .leading, spacing: 12) {
                    CommitSlider(title: "Exposure (EV)", range: -3...3, value: g.exposure, defaultValue: 0,
                                 format: { String(format: "%+.2f", $0) }) { value in set { $0.exposure = value } }
                    CommitSlider(title: "Kontras", range: 0.5...1.5, value: g.contrast, defaultValue: 1,
                                 format: { String(format: "%.2f", $0) }) { value in set { $0.contrast = value } }
                    CommitSlider(title: "Highlights", range: -1...1, value: g.highlights, defaultValue: 0,
                                 format: { String(format: "%+.2f", $0) }) { value in set { $0.highlights = value } }
                    CommitSlider(title: "Shadows", range: -1...1, value: g.shadows, defaultValue: 0,
                                 format: { String(format: "%+.2f", $0) }) { value in set { $0.shadows = value } }
                }
            }

            CollapsibleSection(title: "Warna", systemImage: "eyedropper.halffull") {
                VStack(alignment: .leading, spacing: 12) {
                    CommitSlider(title: "Saturasi", range: 0...2, value: g.saturation, defaultValue: 1,
                                 format: { String(format: "%.2f", $0) }) { value in set { $0.saturation = value } }
                    CommitSlider(title: "Suhu (K)", range: 2000...10000, value: g.temperature, step: 50, defaultValue: 6500,
                                 format: { "\(Int($0.rounded())) K" }) { value in set { $0.temperature = value } }
                    CommitSlider(title: "Tint", range: -150...150, value: g.tint, defaultValue: 0,
                                 format: { "\(Int($0.rounded()))" }) { value in set { $0.tint = value } }
                }
            }

            CollapsibleSection(title: "LUT", systemImage: "cube") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: g.lutPath == nil ? "cube.transparent" : "cube.fill")
                            .foregroundStyle(g.lutPath == nil ? Theme.textTertiary : Theme.accent)
                        Text(g.lutPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Belum ada LUT")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    CommitSlider(title: "Intensitas LUT", range: 0...1, value: g.lutIntensity, defaultValue: 1,
                                 format: { "\(Int(($0 * 100).rounded()))%" }) { value in set { $0.lutIntensity = value } }
                    HStack(spacing: 8) {
                        Button { importLUT(for: clip) } label: { Label("Impor LUT", systemImage: "square.and.arrow.down") }
                            .buttonStyle(.pill)
                            .hoverHelp("Pilih berkas LUT 3D .cube")
                        Button { set("Hapus LUT") { $0.lutPath = nil } } label: { Label("Hapus", systemImage: "trash") }
                            .buttonStyle(.pill)
                            .disabled(g.lutPath == nil)
                    }
                }
            }

            Button { set("Reset Warna") { $0 = ColorGrade() } } label: {
                Label("Reset semua warna", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.pill)
            .frame(maxWidth: .infinity)
            .hoverHelp("Kembalikan seluruh koreksi warna klip ini")
        }
    }

    private func importLUT(for clip: Clip) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.message = "Pilih berkas LUT 3D (.cube)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        guard let text = try? String(contentsOf: url, encoding: .utf8), LUTLoader.parseCube(text) != nil else {
            app.alertMessage = "LUT tidak valid. Hanya LUT 3D .cube yang didukung."
            return
        }
        store.updateClip(clip.id, "Impor LUT") { $0.grade.lutPath = url.path }
    }
}
