import AppKit
import SwiftUI

/// Workspace Export: preset resolusi, orientasi, dan codec, dengan progres dan pembatalan.
struct ExportPanel: View {
    let app: AppState

    private var exporter: ExportController { app.exporter }
    private var duration: Ticks { app.store.project.duration }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            settings
                .frame(width: 420)
            Divider()
            summary
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ekspor Timeline").font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Resolusi")
                Picker("Resolusi", selection: binding(\.resolution)) {
                    ForEach(ExportResolution.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Orientasi")
                Picker("Orientasi", selection: binding(\.orientation)) {
                    ForEach(ExportOrientation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Codec")
                Picker("Codec", selection: binding(\.codec)) {
                    ForEach(ExportCodec.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionTitle("Kualitas")
                Picker("Kualitas", selection: binding(\.quality)) {
                    ForEach(ExportQuality.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Text("Sumber: file asli (bukan proxy). Efek, transform, teks, dan EQ ikut diekspor.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.trailing, 16)
    }

    private var summary: some View {
        let settings = exporter.settings
        let size = settings.size

        return VStack(alignment: .leading, spacing: 14) {
            InfoRow(title: "Ukuran frame", value: "\(Int(size.width)) × \(Int(size.height))")
            InfoRow(title: "Codec & bitrate", value: "\(settings.codec.title) · \(settings.bitrate / 1_000_000) Mbps")
            InfoRow(title: "Durasi", value: duration.clockString)
            InfoRow(title: "Perkiraan ukuran", value: "±\(Int(settings.estimatedMegabytes(duration: duration).rounded())) MB")

            if exporter.isRunning {
                ProgressView(value: exporter.progress)
                Text("Mengekspor… \(Int(exporter.progress * 100))%")
                    .font(.caption.monospacedDigit())
                Button("Batalkan", role: .cancel) { exporter.cancel() }
            } else {
                HStack {
                    Button {
                        app.startExport()
                    } label: {
                        Label("Mulai Ekspor…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(duration <= .zero)

                    if let url = exporter.lastOutputURL {
                        Button("Tampilkan di Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    }
                }
            }

            if let error = exporter.lastError {
                Label(error, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(Theme.warning)
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
