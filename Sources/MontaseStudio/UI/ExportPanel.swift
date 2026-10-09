import AppKit
import SwiftUI

/// Workspace Export: preset resolusi, orientasi, codec, dan kualitas, dengan progres dan pembatalan.
struct ExportPanel: View {
    let app: AppState

    private var exporter: ExportController { app.exporter }
    private var duration: Ticks { app.store.project.duration }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            settings
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 440)
            summary
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
    }

    // MARK: - Pengaturan

    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ekspor Timeline")
                    .font(.title2.weight(.bold))
                    .padding(.bottom, 2)

                choice("Resolusi", icon: "rectangle.dashed", help: "Ukuran piksel video hasil ekspor") {
                    Picker("Resolusi", selection: binding(\.resolution)) {
                        ForEach(ExportResolution.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                choice("Orientasi", icon: "rectangle.portrait.rotate", help: "Bentuk layar: landscape, portrait, atau square") {
                    Picker("Orientasi", selection: binding(\.orientation)) {
                        ForEach(ExportOrientation.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                choice("Codec", icon: "cpu", help: "H.264 kompatibel luas; HEVC lebih kecil untuk kualitas setara") {
                    Picker("Codec", selection: binding(\.codec)) {
                        ForEach(ExportCodec.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                choice("Kualitas", icon: "dial.high", help: "Tinggi memakai bitrate lebih besar: file lebih berat, detail lebih terjaga") {
                    Picker("Kualitas", selection: binding(\.quality)) {
                        ForEach(ExportQuality.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Text("Sumber memakai file asli. Efek, transform, teks, dan EQ ikut diekspor.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .padding(.trailing, 4)
        }
    }

    private func choice<Content: View>(
        _ title: String,
        icon: String,
        help: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.callout.weight(.semibold))
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .hoverHelp(help, edge: .bottom)
    }

    // MARK: - Ringkasan

    private var summary: some View {
        let settings = exporter.settings
        let size = settings.size

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                AspectPreview(size: size)
                    .frame(width: 170, height: 170)
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(title: "Ukuran frame", value: "\(Int(size.width)) × \(Int(size.height))")
                    InfoRow(title: "Codec & bitrate", value: "\(settings.codec.title) · \(settings.bitrate / 1_000_000) Mbps")
                    InfoRow(title: "Durasi", value: duration.clockString)
                    InfoRow(title: "Perkiraan ukuran", value: "±\(Int(settings.estimatedMegabytes(duration: duration).rounded())) MB")
                }
            }
            .card(padding: 16)

            actionArea
                .card(padding: 16)

            if let error = exporter.lastError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Theme.danger)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: exporter.isRunning)
    }

    @ViewBuilder
    private var actionArea: some View {
        if exporter.isRunning {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Mengekspor…")
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("\(Int(exporter.progress * 100))%")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .contentTransition(.numericText())
                }
                ProgressView(value: exporter.progress)
                    .tint(Theme.accent)
                Button { exporter.cancel() } label: { Label("Batalkan", systemImage: "xmark") }
                    .buttonStyle(.pill)
            }
        } else {
            HStack(spacing: 12) {
                Button { app.startExport() } label: {
                    Label("Mulai Ekspor…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.prominentPill)
                .disabled(duration <= .zero)
                .hoverHelp("Pilih lokasi berkas lalu mulai ekspor", shortcut: "⌘E")

                if let url = exporter.lastOutputURL {
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                        Label("Tampilkan di Finder", systemImage: "folder")
                    }
                    .buttonStyle(.pill)
                }
                Spacer(minLength: 0)
                if duration <= .zero {
                    Text("Timeline kosong")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<ExportSettings, Value>) -> Binding<Value> {
        Binding(
            get: { exporter.settings[keyPath: keyPath] },
            set: { exporter.settings[keyPath: keyPath] = $0 }
        )
    }
}

/// Pratinjau rasio layar. Bentuknya berubah mengikuti orientasi yang dipilih.
private struct AspectPreview: View {
    let size: CGSize

    var body: some View {
        let ratio = size.width / max(size.height, 1)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.raised)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [Theme.videoClipTop, Theme.videoClip],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .aspectRatio(ratio, contentMode: .fit)
                .padding(14)
                .shadow(color: Theme.videoClip.opacity(0.4), radius: 10, y: 4)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: ratio)
        }
    }
}
