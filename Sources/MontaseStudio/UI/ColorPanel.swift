import AppKit
import SwiftUI

/// Workspace Color: koreksi warna per clip, LUT .cube, dan scope histogram.
struct ColorPanel: View {
    @Bindable var app: AppState

    private var store: EditorStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("COLOR").panelTitle()

                Toggle("Scope histogram", isOn: Binding(
                    get: { app.scopes.isEnabled },
                    set: { app.scopes.isEnabled = $0 }
                ))
                .toggleStyle(.switch)
                if app.scopes.isEnabled {
                    scope
                }

                Toggle("Tampilkan sumber (Sebelum)", isOn: Binding(
                    get: { app.playback.showOriginal },
                    set: { value in
                        app.playback.showOriginal = value
                        app.refreshPreview()
                    }
                ))
                .toggleStyle(.switch)

                if let clip = store.selectedClip, !clip.isTitle {
                    grade(clip)
                        .id(clip.id)
                } else {
                    Text("Pilih clip video di timeline untuk mengatur warnanya.")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
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
                context.fill(Path(rect), with: .color(Theme.accent.opacity(0.85)))
            }
        }
        .frame(height: 90)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
            SectionTitle("Tonal")
            CommitSlider(title: "Exposure (EV)", range: -3...3, value: g.exposure,
                         format: { String(format: "%+.2f", $0) }) { value in set { $0.exposure = value } }
            CommitSlider(title: "Kontras", range: 0.5...1.5, value: g.contrast,
                         format: { String(format: "%.2f", $0) }) { value in set { $0.contrast = value } }
            CommitSlider(title: "Highlights", range: -1...1, value: g.highlights,
                         format: { String(format: "%+.2f", $0) }) { value in set { $0.highlights = value } }
            CommitSlider(title: "Shadows", range: -1...1, value: g.shadows,
                         format: { String(format: "%+.2f", $0) }) { value in set { $0.shadows = value } }

            SectionTitle("Warna")
            CommitSlider(title: "Saturasi", range: 0...2, value: g.saturation,
                         format: { String(format: "%.2f", $0) }) { value in set { $0.saturation = value } }
            CommitSlider(title: "Suhu (K)", range: 2000...10000, value: g.temperature, step: 50,
                         format: { "\(Int($0.rounded())) K" }) { value in set { $0.temperature = value } }
            CommitSlider(title: "Tint", range: -150...150, value: g.tint,
                         format: { "\(Int($0.rounded()))" }) { value in set { $0.tint = value } }

            SectionTitle("LUT")
            Text(g.lutPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Belum ada LUT")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            CommitSlider(title: "Intensitas LUT", range: 0...1, value: g.lutIntensity,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in set { $0.lutIntensity = value } }
            HStack {
                Button("Impor LUT (.cube)…") { importLUT(for: clip) }
                Button("Hapus LUT") { set("Hapus LUT") { $0.lutPath = nil } }
                    .disabled(g.lutPath == nil)
            }
            Button("Reset Warna") { set("Reset Warna") { $0 = ColorGrade() } }
                .buttonStyle(.borderless)
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
