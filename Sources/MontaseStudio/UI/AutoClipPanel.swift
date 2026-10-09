import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Panel Auto Clip: memilih sumber video, lalu memotongnya otomatis menjadi video pendek siap posting.
/// Semua proses berjalan di Mac ini.
struct AutoClipPanel: View {
    let app: AppState

    @Environment(\.dismiss) private var dismiss

    @State private var selectedMediaID: UUID?
    @State private var externalURL: URL?
    @State private var count = 3
    @State private var orientation: ExportOrientation = .portrait
    @State private var localeIdentifier = "id-ID"
    @State private var folder = AutoClipRunner.defaultFolder

    private var runner: AutoClipRunner { app.autoClip }
    private var exporter: ExportController { app.exporter }

    private var videoItems: [MediaItem] {
        app.store.project.media.filter(\.hasVideo)
    }

    private var sourceURL: URL? {
        if let externalURL { return externalURL }
        return videoItems.first { $0.id == selectedMediaID }?.url
    }

    private var sourceItem: MediaItem? {
        guard externalURL == nil else { return nil }
        return videoItems.first { $0.id == selectedMediaID }
    }

    private var canStart: Bool { sourceURL != nil && !runner.stage.isBusy }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline(vertical: false)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sourceCard
                    settingsCard
                    rulesCard
                    progressArea
                    resultsArea
                }
                .padding(16)
            }
            Hairline(vertical: false)
            footer
        }
        .frame(width: 620, height: 680)
        .background(Theme.background)
        .foregroundStyle(Theme.textPrimary)
        .onAppear {
            if selectedMediaID == nil { selectedMediaID = videoItems.first?.id }
        }
    }

    // MARK: - Bagian

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.background)
                .frame(width: 34, height: 34)
                .background(
                    LinearGradient(colors: [Theme.accent, Theme.videoClipTop], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto Clip")
                    .font(.title3.weight(.bold))
                Text("Potong video panjang jadi beberapa video pendek. Diproses di Mac ini, tanpa mengirim data keluar.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            IconButton(systemImage: "xmark", help: "Tutup", size: 26) {
                if runner.stage.isBusy { return }
                dismiss()
            }
            .disabled(runner.stage.isBusy)
        }
        .padding(16)
        .background(Theme.panel)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Sumber video")
            if videoItems.isEmpty && externalURL == nil {
                Text("Belum ada video di Library. Impor video dulu, atau pilih berkas dari komputer.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Picker("Media", selection: Binding(
                    get: { externalURL == nil ? selectedMediaID : nil },
                    set: { id in
                        externalURL = nil
                        selectedMediaID = id
                    }
                )) {
                    ForEach(videoItems) { item in
                        Text("\(item.name) · \(item.duration.clockString)").tag(Optional(item.id))
                    }
                    if externalURL != nil {
                        Text(externalURL?.lastPathComponent ?? "").tag(Optional<UUID>.none)
                    }
                }
                .labelsHidden()
                .disabled(videoItems.isEmpty || runner.stage.isBusy)
            }
            HStack(spacing: 8) {
                Button { chooseSourceFile() } label: { Label("Pilih berkas lain…", systemImage: "folder") }
                    .buttonStyle(.pill)
                    .disabled(runner.stage.isBusy)
                if let url = externalURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
        }
        .card()
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Pengaturan")

            HStack {
                Text("Jumlah video")
                    .font(.callout)
                Spacer()
                HStack(spacing: 10) {
                    IconButton(systemImage: "minus", help: "Kurangi", size: 24) { count = max(1, count - 1) }
                        .disabled(count <= 1 || runner.stage.isBusy)
                    Text("\(count)")
                        .font(.title3.monospacedDigit().weight(.bold))
                        .frame(minWidth: 26)
                        .contentTransition(.numericText())
                    IconButton(systemImage: "plus", help: "Tambah", size: 24) { count = min(10, count + 1) }
                        .disabled(count >= 10 || runner.stage.isBusy)
                }
            }
            .hoverHelp("Berapa video pendek yang ingin dibuat dari sumber ini (1–10)")

            VStack(alignment: .leading, spacing: 6) {
                Text("Orientasi").font(.caption).foregroundStyle(Theme.textSecondary)
                Picker("Orientasi", selection: $orientation) {
                    ForEach(ExportOrientation.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(runner.stage.isBusy)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Bahasa ucapan").font(.caption).foregroundStyle(Theme.textSecondary)
                Picker("Bahasa", selection: $localeIdentifier) {
                    ForEach(AutoClipLanguage.all) { Text($0.name).tag($0.id) }
                }
                .labelsHidden()
                .disabled(runner.stage.isBusy)
                .hoverHelp("Bahasa yang diucapkan di video. Model offline harus sudah terpasang.")
            }

            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Ubah…") { chooseFolder() }
                    .buttonStyle(.pill)
                    .disabled(runner.stage.isBusy)
            }
        }
        .card()
    }

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Aturan pemotongan")
            ruleRow("timer", "Klip mentah 5 detik sampai 2 menit, tidak lebih pendek atau lebih panjang")
            ruleRow("target", "Video final ideal 30–90 detik, dari hook, isi, dan penutup (maksimal 5 klip)")
            ruleRow("sparkle", "Hook dipilih dari skor 8–10, lalu isi, dan penutup di akhir")
            ruleRow("text.alignleft", "Pemotongan selalu di akhir kalimat, tidak memotong di tengah kata")
        }
        .card()
    }

    private func ruleRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(Theme.accent)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var progressArea: some View {
        if runner.stage.isBusy {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(runner.stage.label)
                        .font(.callout.weight(.semibold))
                    Spacer()
                }
                if case .exporting = runner.stage {
                    ProgressView(value: exporter.progress)
                        .tint(Theme.accent)
                }
                Text("Proses ini bisa lama untuk video panjang. Kamu bisa membatalkan kapan saja.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .card()
        } else if case .failed(let message) = runner.stage {
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.callout)
                .foregroundStyle(Theme.danger)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        } else if case .cancelled = runner.stage {
            Label("Dibatalkan. Video yang sudah selesai tetap tersimpan.", systemImage: "stop.circle")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if let report = runner.report {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle("Hasil")
                    Spacer()
                    Text("\(report.analisisTopik.count) topik · \(runner.results.count) video")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                ForEach(runner.results) { result in
                    resultRow(result)
                }

                if let reportURL = runner.reportURL {
                    Button { NSWorkspace.shared.open(reportURL) } label: {
                        Label("Buka laporan JSON", systemImage: "doc.text")
                    }
                    .buttonStyle(.pill)
                    .hoverHelp("Analisis topik, skor, dan metadata setiap video")
                }
            }
            .card()
        }
    }

    private func resultRow(_ result: AutoClipRunner.Result) -> some View {
        let short = result.duration < AutoClipRules.outputMinSeconds
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(String(format: "%02d", result.id))
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(Theme.accent)
                Text(result.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                Text("\(Int(result.duration.rounded())) dtk")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(short ? Theme.warning.opacity(0.18) : Theme.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(short ? Theme.warning : Theme.accent)
                    .hoverHelp(short ? "Di bawah 30 detik. Aturan ideal 30–90 detik." : "Durasi video final")
            }
            HStack(spacing: 8) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([result.fileURL]) } label: {
                    Label("Tampilkan", systemImage: "folder")
                }
                .buttonStyle(.pill)
                Button { app.openInEditor(result.project) } label: {
                    Label("Buka di editor", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.pill)
                .hoverHelp("Buka sebagai proyek untuk diatur ulang sebelum diekspor")
            }
        }
        .padding(12)
        .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.divider))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if runner.stage.isBusy {
                Button(role: .cancel) { runner.cancel(exporter: exporter) } label: {
                    Label("Batalkan", systemImage: "xmark")
                }
                .buttonStyle(.pill)
            }
            Spacer()
            if !canStart && !runner.stage.isBusy {
                Text("Pilih sumber video dulu")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Button { start() } label: {
                Label(runner.stage.isBusy ? "Sedang memproses…" : "Mulai Auto Clip", systemImage: "wand.and.stars")
            }
            .buttonStyle(.prominentPill)
            .disabled(!canStart)
        }
        .padding(16)
        .background(Theme.panel)
    }

    // MARK: - Aksi

    private func start() {
        guard let sourceURL else { return }
        runner.start(
            AutoClipRunner.Request(
                source: sourceURL,
                sourceItem: sourceItem,
                count: count,
                orientation: orientation,
                localeIdentifier: localeIdentifier,
                folder: folder
            ),
            exporter: exporter
        )
    }

    private func chooseSourceFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audiovisualContent]
        panel.message = "Pilih video yang akan dipotong otomatis"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        externalURL = url
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = "Pilih folder untuk menyimpan video hasil"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder = url
    }
}
