import SwiftUI

/// Inspector mengikuti objek yang dipilih. Tanpa pilihan, menampilkan ringkasan proyek dan marker.
struct InspectorView: View {
    let app: AppState

    private var store: EditorStore { app.store }
    private var frameRate: Int { store.project.sequence.frameRate }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("INSPECTOR").panelTitle()
                if let clip = store.selectedClip {
                    clipSection(clip)
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

    private func clipSection(_ clip: Clip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(title: "Nama", value: clip.name)
            InfoRow(title: "Posisi", value: clip.timelineStart.timecode(frameRate: frameRate))
            InfoRow(title: "Durasi", value: clip.duration.timecode(frameRate: frameRate))
            InfoRow(title: "Awal sumber", value: clip.sourceStart.timecode(frameRate: frameRate))

            if let style = clip.title {
                titleSection(clip, style: style)
            }

            SectionTitle("Waktu & level")
            CommitSlider(title: "Kecepatan", range: 0.25...4, value: clip.speed, step: 0.05,
                         format: { String(format: "%.2f×", $0) }) { store.setSpeed(clip.id, $0) }
            CommitSlider(title: "Volume", range: 0...2, value: clip.volume,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                store.updateClip(clip.id, "Ubah Volume") { $0.volume = value }
            }
            CommitSlider(title: "Opasitas", range: 0...1, value: clip.opacity,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                store.updateClip(clip.id, "Ubah Opasitas") { $0.opacity = value }
            }
            CommitSlider(title: "Fade masuk / dissolve (detik)", range: 0...5, value: clip.fadeIn.seconds,
                         format: { String(format: "%.1f s", $0) }) { value in
                store.updateClip(clip.id, "Fade Masuk") { $0.fadeIn = Ticks(seconds: value) }
            }
            CommitSlider(title: "Fade keluar (detik)", range: 0...5, value: clip.fadeOut.seconds,
                         format: { String(format: "%.1f s", $0) }) { value in
                store.updateClip(clip.id, "Fade Keluar") { $0.fadeOut = Ticks(seconds: value) }
            }

            transformSection(clip)
            linkSection(clip, canDetachAudio: canDetachAudio(clip))

            HStack {
                Button("Duplikat") { store.duplicateSelected() }
                Button("Hapus", role: .destructive) { store.deleteSelected(ripple: false) }
            }
        }
    }

    private func transformSection(_ clip: Clip) -> some View {
        let t = clip.transform
        let sequence = store.project.sequence
        func update(_ label: String = "Ubah Transformasi", _ change: @escaping (inout Transform) -> Void) {
            store.updateClip(clip.id, label) { change(&$0.transform) }
        }

        return VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Transformasi")
            CommitSlider(title: "Posisi X (px)", range: -Double(sequence.width)...Double(sequence.width), value: t.offsetX,
                         format: { "\(Int($0.rounded()))" }) { value in update { $0.offsetX = value } }
            CommitSlider(title: "Posisi Y (px)", range: -Double(sequence.height)...Double(sequence.height), value: t.offsetY,
                         format: { "\(Int($0.rounded()))" }) { value in update { $0.offsetY = value } }
            CommitSlider(title: "Skala", range: 0.1...3, value: t.scale,
                         format: { String(format: "%.2f×", $0) }) { value in update { $0.scale = value } }
            CommitSlider(title: "Rotasi (°)", range: -180...180, value: t.rotation,
                         format: { "\(Int($0.rounded()))°" }) { value in update { $0.rotation = value } }

            SectionTitle("Crop")
            CommitSlider(title: "Kiri", range: 0...0.45, value: t.cropLeft,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropLeft = value } }
            CommitSlider(title: "Kanan", range: 0...0.45, value: t.cropRight,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropRight = value } }
            CommitSlider(title: "Atas", range: 0...0.45, value: t.cropTop,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropTop = value } }
            CommitSlider(title: "Bawah", range: 0...0.45, value: t.cropBottom,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in update { $0.cropBottom = value } }

            Button("Reset Transformasi") { update("Reset Transformasi") { $0 = Transform() } }
                .buttonStyle(.borderless)
        }
    }

    private func titleSection(_ clip: Clip, style: TitleStyle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Teks")
            TitleTextField(text: style.text) { newText in
                store.updateClip(clip.id, "Ubah Teks") { $0.title?.text = newText; $0.name = newText }
            }
            CommitSlider(title: "Ukuran", range: 24...240, value: style.fontSize,
                         format: { "\(Int($0.rounded())) pt" }) { value in
                store.updateClip(clip.id, "Ubah Ukuran Teks") { $0.title?.fontSize = value }
            }
            CommitSlider(title: "Posisi vertikal", range: 0...1, value: style.positionY,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                store.updateClip(clip.id, "Ubah Posisi Teks") { $0.title?.positionY = value }
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
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Tautan & audio")
            HStack {
                Button("Tautkan") { store.linkSelected() }
                Button("Lepas") { store.unlinkSelected() }
                    .disabled(clip.linkID == nil)
            }
            if canDetachAudio {
                Button("Pisahkan Audio ke Track Audio") { store.detachAudioSelected() }
            }
        }
    }

    // MARK: - Proyek

    private var projectSection: some View {
        let project = store.project
        let offline = project.media.filter { !FileManager.default.fileExists(atPath: $0.path) }

        return VStack(alignment: .leading, spacing: 12) {
            InfoRow(title: "Proyek", value: project.name)
            InfoRow(title: "Sequence", value: "\(project.sequence.width) × \(project.sequence.height)")
            InfoRow(title: "Frame rate", value: "\(project.sequence.frameRate) fps")
            InfoRow(title: "Durasi", value: project.duration.timecode(frameRate: frameRate))
            InfoRow(title: "Media di Library", value: "\(project.media.count)")

            if !offline.isEmpty {
                Label("\(offline.count) media tidak ditemukan", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                ForEach(offline) { item in
                    Button("Relink \(item.name)…") { app.presentRelinkPanel(for: item) }
                        .buttonStyle(.borderless)
                }
            }

            SectionTitle("Marker")
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
                    }
                }
                .buttonStyle(.borderless)
            }

            Text("Pilih clip di timeline untuk mengubah propertinya.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
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
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .onSubmit(commit)
            .onChange(of: text) { _, _ in draft = nil }
    }

    private func commit() {
        guard let draft, draft != text else { return }
        onCommit(draft)
        self.draft = nil
    }
}
