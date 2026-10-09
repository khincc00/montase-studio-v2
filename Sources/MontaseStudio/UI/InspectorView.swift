import SwiftUI

/// Inspector mengikuti objek yang dipilih. Tanpa pilihan, menampilkan ringkasan proyek dan marker.
struct InspectorView: View {
    let app: AppState

    private var store: EditorStore { app.store }
    private var frameRate: Int { store.project.sequence.frameRate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("INSPECTOR").panelTitle()
                    Spacer()
                    if let clip = store.selectedClip {
                        Text(clip.isTitle ? "Teks" : (store.project.mediaItem(for: clip)?.hasVideo == true ? "Video" : "Audio"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                if let clip = store.selectedClip {
                    clipSections(clip)
                        .id(clip.id)
                } else {
                    projectSection
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    // MARK: - Clip

    @ViewBuilder
    private func clipSections(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CollapsibleSection(title: "Ringkasan", systemImage: "info.circle") {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(title: "Nama", value: clip.name)
                    HStack(alignment: .top, spacing: 12) {
                        InfoRow(title: "Posisi", value: clip.timelineStart.timecode(frameRate: frameRate))
                        InfoRow(title: "Durasi", value: clip.duration.timecode(frameRate: frameRate))
                    }
                    InfoRow(title: "Awal sumber", value: clip.sourceStart.timecode(frameRate: frameRate))
                }
            }

            if let style = clip.title {
                titleSection(clip, style: style)
            }

            CollapsibleSection(title: "Waktu & level", systemImage: "dial.medium") {
                VStack(alignment: .leading, spacing: 12) {
                    CommitSlider(title: "Kecepatan", range: 0.25...4, value: clip.speed, step: 0.05, defaultValue: 1,
                                 format: { String(format: "%.2f×", $0) }) { store.setSpeed(clip.id, $0) }
                    CommitSlider(title: "Volume", range: 0...2, value: clip.volume, defaultValue: 1,
                                 format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                        store.updateClip(clip.id, "Ubah Volume") { $0.volume = value }
                    }
                    CommitSlider(title: "Opasitas", range: 0...1, value: clip.opacity, defaultValue: 1,
                                 format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                        store.updateClip(clip.id, "Ubah Opasitas") { $0.opacity = value }
                    }
                    CommitSlider(title: "Fade masuk", range: 0...5, value: clip.fadeIn.seconds, defaultValue: 0,
                                 format: { String(format: "%.1f s", $0) }) { value in
                        store.updateClip(clip.id, "Fade Masuk") { $0.fadeIn = Ticks(seconds: value) }
                    }
                    CommitSlider(title: "Fade keluar", range: 0...5, value: clip.fadeOut.seconds, defaultValue: 0,
                                 format: { String(format: "%.1f s", $0) }) { value in
                        store.updateClip(clip.id, "Fade Keluar") { $0.fadeOut = Ticks(seconds: value) }
                    }
                }
            }

            CollapsibleSection(title: "Transformasi & crop", systemImage: "crop", initiallyExpanded: false) {
                transformSection(clip)
            }

            CollapsibleSection(title: "Tautan & aksi", systemImage: "link") {
                linkSection(clip, canDetachAudio: canDetachAudio(clip))
            }
        }
    }

    private func transformSection(_ clip: Clip) -> some View {
        let t = clip.transform
        let sequence = store.project.sequence
        func update(_ label: String = "Ubah Transformasi", _ change: @escaping (inout Transform) -> Void) {
            store.updateClip(clip.id, label) { change(&$0.transform) }
        }

        return VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Posisi & ukuran")
            CommitSlider(title: "Posisi X (px)", range: -Double(sequence.width)...Double(sequence.width), value: t.offsetX,
                         defaultValue: 0, format: { "\(Int($0.rounded()))" }) { value in update { $0.offsetX = value } }
            CommitSlider(title: "Posisi Y (px)", range: -Double(sequence.height)...Double(sequence.height), value: t.offsetY,
                         defaultValue: 0, format: { "\(Int($0.rounded()))" }) { value in update { $0.offsetY = value } }
            CommitSlider(title: "Skala", range: 0.1...3, value: t.scale, defaultValue: 1,
                         format: { String(format: "%.2f×", $0) }) { value in update { $0.scale = value } }
            CommitSlider(title: "Rotasi (°)", range: -180...180, value: t.rotation, defaultValue: 0,
                         format: { "\(Int($0.rounded()))°" }) { value in update { $0.rotation = value } }

            SectionTitle("Crop")
            CommitSlider(title: "Kiri", range: 0...0.45, value: t.cropLeft, defaultValue: 0,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropLeft = value } }
            CommitSlider(title: "Kanan", range: 0...0.45, value: t.cropRight, defaultValue: 0,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropRight = value } }
            CommitSlider(title: "Atas", range: 0...0.45, value: t.cropTop, defaultValue: 0,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropTop = value } }
            CommitSlider(title: "Bawah", range: 0...0.45, value: t.cropBottom, defaultValue: 0,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropBottom = value } }

            Button("Reset transformasi") { update("Reset Transformasi") { $0 = Transform() } }
                .buttonStyle(.pill)
                .hoverHelp("Kembalikan posisi, skala, rotasi, dan crop ke awal")
        }
    }

    private func titleSection(_ clip: Clip, style: TitleStyle) -> some View {
        CollapsibleSection(title: "Teks", systemImage: "textformat") {
            VStack(alignment: .leading, spacing: 12) {
                TitleTextField(text: style.text) { newText in
                    store.updateClip(clip.id, "Ubah Teks") { $0.title?.text = newText; $0.name = newText }
                }
                CommitSlider(title: "Ukuran", range: 24...240, value: style.fontSize, defaultValue: 96,
                             format: { "\(Int($0.rounded())) pt" }) { value in
                    store.updateClip(clip.id, "Ubah Ukuran Teks") { $0.title?.fontSize = value }
                }
                CommitSlider(title: "Posisi vertikal", range: 0...1, value: style.positionY, defaultValue: 0.85,
                             format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                    store.updateClip(clip.id, "Ubah Posisi Teks") { $0.title?.positionY = value }
                }
            }
        }
    }

    /// Clip video dengan media yang punya audio dan belum dipisah: bisa dipisah ke track audio.
    private func canDetachAudio(_ clip: Clip) -> Bool {
        guard !clip.isTitle, let item = store.project.mediaItem(for: clip), item.hasVideo, item.hasAudio,
              let location = store.project.location(of: clip.id) else { return false }
        return store.project.tracks[location.track].kind == .video
    }

    private func linkSection(_ clip: Clip, canDetachAudio: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button { store.linkSelected() } label: { Label("Tautkan", systemImage: "link") }
                    .buttonStyle(.pill)
                    .hoverHelp("Tautkan dengan clip sejajar agar bergerak bersama")
                Button { store.unlinkSelected() } label: { Label("Lepas", systemImage: "link.badge.minus") }
                    .buttonStyle(.pill)
                    .disabled(clip.linkID == nil)
            }
            if canDetachAudio {
                Button { store.detachAudioSelected() } label: {
                    Label("Pisahkan audio ke track audio", systemImage: "waveform.badge.minus")
                }
                .buttonStyle(.pill)
            }
            HStack(spacing: 8) {
                Button { store.duplicateSelected() } label: { Label("Duplikat", systemImage: "plus.square.on.square") }
                    .buttonStyle(.pill)
                Button(role: .destructive) { store.deleteSelected(ripple: false) } label: {
                    Label("Hapus", systemImage: "trash")
                }
                .buttonStyle(.pill)
            }
        }
    }

    // MARK: - Proyek

    private var projectSection: some View {
        let project = store.project
        let offline = project.media.filter { !FileManager.default.fileExists(atPath: $0.path) }

        return VStack(alignment: .leading, spacing: 10) {
            CollapsibleSection(title: "Proyek", systemImage: "rectangle.on.rectangle") {
                VStack(alignment: .leading, spacing: 10) {
                    InfoRow(title: "Nama", value: project.name)
                    HStack(alignment: .top, spacing: 12) {
                        InfoRow(title: "Sequence", value: "\(project.sequence.width) × \(project.sequence.height)")
                        InfoRow(title: "Frame rate", value: "\(project.sequence.frameRate) fps")
                    }
                    HStack(alignment: .top, spacing: 12) {
                        InfoRow(title: "Durasi", value: project.duration.timecode(frameRate: frameRate))
                        InfoRow(title: "Media", value: "\(project.media.count)")
                    }
                }
            }

            if !offline.isEmpty {
                CollapsibleSection(title: "Media tidak ditemukan", systemImage: "exclamationmark.triangle.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(offline.count) file hilang. Arahkan ke file barunya agar klip kembali normal.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        ForEach(offline) { item in
                            Button { app.presentRelinkPanel(for: item) } label: {
                                Label("Relink \(item.name)…", systemImage: "link")
                            }
                            .buttonStyle(.pill)
                        }
                    }
                }
            }

            CollapsibleSection(title: "Marker", systemImage: "flag") {
                VStack(alignment: .leading, spacing: 6) {
                    if project.markers.isEmpty {
                        Text("Tekan M untuk menambah marker di playhead.")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    ForEach(project.markers) { marker in
                        Button {
                            app.playback.seek(to: marker.time)
                        } label: {
                            HStack {
                                Image(systemName: "flag.fill").foregroundStyle(Theme.warning)
                                Text(marker.name)
                                Spacer()
                                Text(marker.time.timecode(frameRate: frameRate))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Theme.hover, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableStyle())
                        .hoverHelp("Lompat ke marker ini")
                    }
                }
            }

            Label("Pilih klip di timeline untuk mengubah propertinya.", systemImage: "hand.point.up.left")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 2)
        }
    }

}

/// Field teks judul. Perubahan dikirim saat Enter atau saat fokus berpindah.
private struct TitleTextField: View {
    let text: String
    let onCommit: (String) -> Void

    @State private var draft: String?

    var body: some View {
        TextField("Teks", text: Binding(get: { draft ?? text }, set: { draft = $0 }), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.callout)
            .lineLimit(1...4)
            .padding(8)
            .background(Theme.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.divider))
            .onSubmit(commit)
            .onChange(of: text) { _, _ in draft = nil }
    }

    private func commit() {
        guard let draft, draft != text else { return }
        onCommit(draft)
        self.draft = nil
    }
}
