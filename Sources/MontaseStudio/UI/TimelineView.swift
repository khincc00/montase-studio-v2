import AppKit
import SwiftUI

/// Timeline multitrack dengan scroll vertikal dan horizontal. Header track tetap di kiri saat digulir horizontal.
struct TimelineView: View {
    let app: AppState

    @State private var drag: ClipDrag?

    private enum Metrics {
        static let rulerHeight: CGFloat = 28
        static let headerWidth: CGFloat = 116
        static let videoRowHeight: CGFloat = 56
        static let audioRowHeight: CGFloat = 44
        static let clipInset: CGFloat = 4
        static let snapDistance: CGFloat = 8
        static let handleWidth: CGFloat = 8
    }

    /// Gerakan yang sedang dilakukan pengguna pada satu clip.
    private struct ClipDrag {
        enum Mode: Equatable {
            case move
            case trimLeading
            case trimTrailing
        }

        let clipID: UUID
        let mode: Mode
        var translation: CGSize
    }

    /// Posisi clip setelah gerakan diterapkan (snap dan batas sudah dihitung).
    private struct Resolved {
        var start: Ticks
        var duration: Ticks
        var row: Int
        var guide: Ticks?
    }

    private var store: EditorStore { app.store }
    private var project: Project { store.project }
    private var pps: CGFloat { CGFloat(store.pixelsPerSecond) }
    private var contentWidth: CGFloat { max(CGFloat(project.duration.seconds + 60) * pps, 1200) }
    private var canvasHeight: CGFloat { rowTop(project.tracks.count) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    headerColumn
                    Divider()
                    ScrollView(.horizontal) {
                        canvas
                    }
                }
            }
        }
        .background(Theme.panel)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            toolButton("arrow.uturn.backward", "Urungkan (⌘Z)", disabled: !store.canUndo) { store.undo() }
            toolButton("arrow.uturn.forward", "Ulangi (⇧⌘Z)", disabled: !store.canRedo) { store.redo() }
            Divider().frame(height: 16)
            toolButton("scissors", "Belah pada playhead (S)") { store.splitAtPlayhead() }
            toolButton("trash", "Hapus clip (⌫)") { store.deleteSelected(ripple: false) }
            toolButton("rectangle.compress.vertical", "Hapus & rapatkan (⇧⌫)") {
                store.deleteSelected(ripple: true)
            }
            toolButton("plus.square.on.square", "Duplikat clip (⌘D)") { store.duplicateSelected() }
            Divider().frame(height: 16)
            toolButton("link", "Tautkan clip sejajar") { store.linkSelected() }
            toolButton("link.badge.plus", "Pisahkan audio dari video") { store.detachAudioSelected() }
            toolButton("link.badge.minus", "Lepas tautan") { store.unlinkSelected() }
            toolButton("textformat", "Tambah teks di playhead") { store.addTitle() }
            toolButton("flag", "Tambah marker di playhead (M)") { store.addMarker() }
            Divider().frame(height: 16)
            toolButton("magnet", store.snappingEnabled ? "Snap aktif" : "Snap nonaktif") {
                store.snappingEnabled.toggle()
            }
            .foregroundStyle(store.snappingEnabled ? Theme.accent : Theme.textSecondary)

            Spacer()

            Image(systemName: "minus.magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            Slider(value: Binding(
                get: { store.pixelsPerSecond },
                set: { store.pixelsPerSecond = $0 }
            ), in: 10...200)
            .frame(width: 140)
            Image(systemName: "plus.magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func toolButton(
        _ systemImage: String,
        _ help: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .buttonStyle(.borderless)
        .help(help)
        .disabled(disabled)
    }

    // MARK: - Header dan canvas

    private var headerColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { store.addTrack(kind: .video) } label: { Label("Video", systemImage: "plus") }
                    .help("Tambah track video di atas")
                Button { store.addTrack(kind: .audio) } label: { Label("Audio", systemImage: "plus") }
                    .help("Tambah track audio di bawah")
            }
            .buttonStyle(.borderless)
            .font(.caption2)
            .frame(height: Metrics.rulerHeight)

            ForEach(project.tracks) { track in
                TrackHeaderView(app: app, track: track)
                    .frame(height: rowHeight(track))
            }
            Spacer(minLength: 0)
        }
        .frame(width: Metrics.headerWidth)
        .background(Theme.panel)
    }

    private var canvas: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                Rectangle()
                    .fill(index.isMultiple(of: 2) ? Theme.background.opacity(0.6) : Theme.panel)
                    .frame(width: contentWidth, height: rowHeight(track))
                    .offset(y: rowTop(index))
            }

            ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                ForEach(track.clips) { clip in
                    clipView(clip, row: index)
                }
            }

            ruler

            ForEach(project.markers) { marker in
                markerView(marker)
            }

            if let guide = activeGuide {
                Rectangle()
                    .fill(Theme.accent)
                    .frame(width: 1, height: canvasHeight)
                    .offset(x: CGFloat(guide.seconds) * pps)
                    .allowsHitTesting(false)
            }

            PlayheadView(app: app, height: canvasHeight, pixelsPerSecond: pps)
        }
        .frame(width: contentWidth, height: canvasHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { store.selectedClipID = nil }
        .dropDestination(for: String.self) { items, location in
            handleDrop(items, at: location)
        }
    }

    private var ruler: some View {
        let step = rulerStep
        let labelCount = Int(contentWidth / (CGFloat(step) * pps)) + 1

        return ZStack(alignment: .topLeading) {
            Rectangle().fill(Theme.background)
            ForEach(0..<labelCount, id: \.self) { index in
                let time = Double(index) * step
                Text(Ticks(seconds: time).clockString)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .offset(x: CGFloat(time) * pps + 4, y: 7)
            }
        }
        .frame(width: contentWidth, height: Metrics.rulerHeight, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    app.playback.seek(to: Ticks(seconds: Double(max(value.location.x, 0) / pps)))
                }
        )
    }

    private var rulerStep: Double {
        let candidates: [Double] = [1, 2, 5, 10, 30, 60, 300]
        return candidates.first { $0 * Double(pps) >= 70 } ?? 300
    }

    private func markerView(_ marker: Marker) -> some View {
        Image(systemName: "arrowtriangle.down.fill")
            .font(.system(size: 9))
            .foregroundStyle(Theme.warning)
            .frame(width: 12, height: 12)
            .offset(x: CGFloat(marker.time.seconds) * pps - 6, y: Metrics.rulerHeight - 13)
            .help(marker.name)
            .onTapGesture { app.playback.seek(to: marker.time) }
            .contextMenu {
                Button("Ubah Nama…") {
                    Prompt.text(title: "Nama marker", initial: marker.name) { name in
                        store.renameMarker(id: marker.id, name: name)
                    }
                }
                Button("Hapus Marker", role: .destructive) { store.removeMarker(id: marker.id) }
            }
    }

    private func clipView(_ clip: Clip, row: Int) -> some View {
        let shown = displayed(clip, row: row)
        let targetTrack = project.tracks[shown.row]
        let height = rowHeight(targetTrack) - Metrics.clipInset * 2
        let width = max(CGFloat(shown.duration.seconds) * pps, 4)
        let media = project.mediaItem(for: clip)

        return TimelineClipView(
            clip: clip,
            kind: targetTrack.kind,
            isSelected: store.selectedClipID == clip.id,
            peaks: media.flatMap { app.waveforms.peaks[$0.id] }
        )
        .frame(width: width, height: height)
        .overlay(alignment: .leading) { trimHandle(clip, mode: .trimLeading) }
        .overlay(alignment: .trailing) { trimHandle(clip, mode: .trimTrailing) }
        .contentShape(Rectangle())
        .onTapGesture { store.selectedClipID = clip.id }
        .gesture(dragGesture(clip, mode: .move))
        .opacity(drag?.clipID == clip.id ? 0.8 : 1)
        .offset(x: CGFloat(shown.start.seconds) * pps, y: rowTop(shown.row) + Metrics.clipInset)
        .contextMenu {
            Button("Duplikat (⌘D)") { store.duplicateSelected() }
            Button("Belah pada playhead (S)") { store.splitAtPlayhead() }
            Divider()
            Button("Hapus (⌫)", role: .destructive) { store.deleteSelected(ripple: false) }
            Button("Hapus & rapatkan (⇧⌫)", role: .destructive) { store.deleteSelected(ripple: true) }
        }
    }

    private func trimHandle(_ clip: Clip, mode: ClipDrag.Mode) -> some View {
        Color.clear
            .frame(width: Metrics.handleWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(dragGesture(clip, mode: mode))
    }

    // MARK: - Geometri

    private func rowHeight(_ track: Track) -> CGFloat {
        track.kind == .video ? Metrics.videoRowHeight : Metrics.audioRowHeight
    }

    private func rowTop(_ index: Int) -> CGFloat {
        project.tracks.prefix(index).reduce(Metrics.rulerHeight) { $0 + rowHeight($1) }
    }

    private func rowIndex(atY y: CGFloat) -> Int? {
        project.tracks.indices.first { index in
            let top = rowTop(index)
            return y >= top && y < top + rowHeight(project.tracks[index])
        }
    }

    // MARK: - Gerakan

    private func dragGesture(_ clip: Clip, mode: ClipDrag.Mode) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                drag = ClipDrag(clipID: clip.id, mode: mode, translation: value.translation)
            }
            .onEnded { value in
                commit(ClipDrag(clipID: clip.id, mode: mode, translation: value.translation))
                drag = nil
            }
    }

    private func commit(_ gesture: ClipDrag) {
        guard let resolved = resolve(gesture) else { return }
        switch gesture.mode {
        case .move:
            let trackID = project.tracks[resolved.row].id
            if !store.moveClip(gesture.clipID, toTrack: trackID, at: resolved.start) {
                store.notify("Tidak bisa dipindah: bertabrakan dengan clip lain.")
            }
        case .trimLeading:
            store.trimClip(gesture.clipID, edge: .leading, to: resolved.start)
        case .trimTrailing:
            store.trimClip(gesture.clipID, edge: .trailing, to: resolved.start + resolved.duration)
        }
    }

    private var activeGuide: Ticks? {
        guard let drag else { return nil }
        return resolve(drag)?.guide
    }

    /// Clip yang tampil: clip utama dari gerakan aktif, anggota grup tertaut ikut bergeser sejumlah sama.
    private func displayed(_ clip: Clip, row: Int) -> Resolved {
        let fallback = Resolved(start: clip.timelineStart, duration: clip.duration, row: row, guide: nil)
        guard let drag, let primaryResolved = resolve(drag) else { return fallback }

        if drag.clipID == clip.id {
            return primaryResolved
        }
        guard drag.mode == .move,
              let primary = project.clip(id: drag.clipID),
              primary.linkID != nil, clip.linkID == primary.linkID else { return fallback }

        let delta = primaryResolved.start - primary.timelineStart
        return Resolved(start: clip.timelineStart + delta, duration: clip.duration, row: row, guide: nil)
    }

    private func resolve(_ gesture: ClipDrag) -> Resolved? {
        guard let location = project.location(of: gesture.clipID) else { return nil }
        let clip = project.tracks[location.track].clips[location.index]
        let delta = Ticks(seconds: Double(gesture.translation.width / pps))
        var result = Resolved(start: clip.timelineStart, duration: clip.duration, row: location.track, guide: nil)

        switch gesture.mode {
        case .move:
            let (start, guide) = snappedStart(clip.timelineStart + delta, duration: clip.duration, excluding: clip.id)
            result.start = max(start, .zero)
            result.guide = guide
            result.row = targetRow(from: location.track, dy: gesture.translation.height)

        case .trimLeading:
            let (edge, guide) = snappedEdge(clip.timelineStart + delta, excluding: clip.id)
            let start = project.clampedEdge(
                clipID: clip.id,
                edge: .leading,
                to: edge,
                minimumDuration: project.minimumClipDuration
            ) ?? clip.timelineStart
            result.start = start
            result.duration = clip.end - start
            result.guide = guide

        case .trimTrailing:
            let (edge, guide) = snappedEdge(clip.end + delta, excluding: clip.id)
            let end = project.clampedEdge(
                clipID: clip.id,
                edge: .trailing,
                to: edge,
                minimumDuration: project.minimumClipDuration
            ) ?? clip.end
            result.duration = end - clip.timelineStart
            result.guide = guide
        }
        return result
    }

    /// Track tujuan hanya berubah jika jenisnya sama (video ke video, audio ke audio).
    private func targetRow(from row: Int, dy: CGFloat) -> Int {
        let center = rowTop(row) + rowHeight(project.tracks[row]) / 2 + dy
        guard let candidate = rowIndex(atY: center),
              project.tracks[candidate].kind == project.tracks[row].kind else { return row }
        return candidate
    }

    // MARK: - Snapping

    private func snappedStart(_ start: Ticks, duration: Ticks, excluding id: UUID) -> (Ticks, Ticks?) {
        guard store.snappingEnabled else { return (start, nil) }
        let targets = snapTargets(excluding: id)
        if let hit = nearest(start, in: targets) { return (hit, hit) }
        if let hit = nearest(start + duration, in: targets) { return (hit - duration, hit) }
        return (start, nil)
    }

    private func snappedEdge(_ edge: Ticks, excluding id: UUID) -> (Ticks, Ticks?) {
        guard store.snappingEnabled, let hit = nearest(edge, in: snapTargets(excluding: id)) else {
            return (edge, nil)
        }
        return (hit, hit)
    }

    /// Target snap: playhead, marker, dan tepi semua clip selain yang digerakkan.
    private func snapTargets(excluding id: UUID) -> [Ticks] {
        var targets = [store.playhead]
        targets += project.markers.map(\.time)
        for track in project.tracks {
            for clip in track.clips where clip.id != id {
                targets.append(clip.timelineStart)
                targets.append(clip.end)
            }
        }
        return targets
    }

    private func nearest(_ time: Ticks, in targets: [Ticks]) -> Ticks? {
        let limit = Int64(Metrics.snapDistance / pps * CGFloat(Ticks.perSecond))
        guard let best = targets.min(by: { abs($0.units - time.units) < abs($1.units - time.units) }),
              abs(best.units - time.units) <= limit else { return nil }
        return best
    }

    // MARK: - Drop dari Library

    private func handleDrop(_ items: [String], at point: CGPoint) -> Bool {
        guard let text = items.first, let mediaID = UUID(uuidString: text) else { return false }
        guard let index = rowIndex(atY: point.y) else {
            store.notify("Jatuhkan media ke dalam track.")
            return false
        }
        let start = Ticks(seconds: Double(max(point.x, 0) / pps))
        return store.addToTimeline(mediaID: mediaID, trackID: project.tracks[index].id, at: start)
    }
}

/// Dibuat terpisah agar hanya bagian ini yang di-render ulang saat playhead bergerak.
private struct PlayheadView: View {
    let app: AppState
    let height: CGFloat
    let pixelsPerSecond: CGFloat

    var body: some View {
        Rectangle()
            .fill(Theme.warning)
            .frame(width: 2, height: height)
            .offset(x: CGFloat(app.store.playhead.seconds) * pixelsPerSecond - 1)
            .allowsHitTesting(false)
    }
}

private struct TrackHeaderView: View {
    let app: AppState
    let track: Track

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: track.kind == .video ? "film" : "waveform")
                .foregroundStyle(Theme.textSecondary)
            Text(track.name)
                .font(.caption.weight(.semibold))
            Spacer(minLength: 0)
            Button { app.store.toggleSolo(trackID: track.id) } label: {
                Text("S")
                    .font(.caption2.weight(.bold))
                    .frame(width: 16, height: 16)
                    .background(track.isSolo ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 3))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(track.isSolo ? Theme.background : Theme.textSecondary)
            .help("Solo track")

            Button { app.store.toggleMute(trackID: track.id) } label: {
                Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(track.isMuted ? Theme.warning : Theme.textSecondary)
            .help(track.isMuted ? "Aktifkan track" : "Bisukan track")
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(Theme.panel)
        .contextMenu {
            Button("Tambah Track Video") { app.store.addTrack(kind: .video) }
            Button("Tambah Track Audio") { app.store.addTrack(kind: .audio) }
            Divider()
            Button("Hapus Track", role: .destructive) { app.store.removeTrack(id: track.id) }
                .disabled(!track.clips.isEmpty)
        }
    }
}

private struct TimelineClipView: View {
    let clip: Clip
    let kind: TrackKind
    let isSelected: Bool
    let peaks: [Float]?

    private var fill: Color {
        if clip.isTitle { return Color(hex: 0x6B4FA0) }
        return kind == .video ? Theme.videoClip : Theme.audioClip
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .overlay {
                if kind == .audio, let peaks {
                    WaveformShape(peaks: peaks, sourceStart: clip.sourceStart.seconds, sourceDuration: clip.sourceDuration.seconds)
                        .padding(.vertical, 6)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .overlay(alignment: .leading) {
                HStack(spacing: 4) {
                    if clip.linkID != nil {
                        Image(systemName: "link").font(.caption2)
                    }
                    if clip.isTitle {
                        Image(systemName: "textformat").font(.caption2)
                    }
                    Text(clip.name).lineLimit(1)
                    if abs(clip.speed - 1) > 0.001 {
                        Text(String(format: "%.2g×", clip.speed))
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 3)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 3))
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, 8)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Theme.accent : .clear, lineWidth: 2)
            }
    }
}

/// Gambar gelombang dari peak yang sudah dihitung, dipetakan ke rentang sumber clip.
private struct WaveformShape: View {
    let peaks: [Float]
    let sourceStart: Double
    let sourceDuration: Double

    var body: some View {
        Canvas { context, size in
            let perSecond = Waveform.bucketsPerSecond
            let first = Int(sourceStart * perSecond)
            let last = min(peaks.count, Int((sourceStart + sourceDuration) * perSecond))
            guard last > first, size.width > 0 else { return }

            let columns = max(Int(size.width / 2), 1)
            var path = Path()
            for column in 0..<columns {
                let index = min(first + (last - first) * column / columns, peaks.count - 1)
                let height = max(1, CGFloat(peaks[index]) * size.height)
                let x = CGFloat(column) * 2 + 1
                path.move(to: CGPoint(x: x, y: size.height / 2 - height / 2))
                path.addLine(to: CGPoint(x: x, y: size.height / 2 + height / 2))
            }
            context.stroke(path, with: .color(Theme.textPrimary.opacity(0.55)), lineWidth: 1)
        }
    }
}
