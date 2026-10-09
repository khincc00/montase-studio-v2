import AppKit
import SwiftUI

/// Timeline multitrack dengan scroll vertikal dan horizontal. Header track tetap di kiri saat digulir horizontal.
struct TimelineView: View {
    let app: AppState

    @State private var drag: ClipDrag?

    private enum Metrics {
        static let rulerHeight: CGFloat = 30
        static let headerWidth: CGFloat = 124
        static let videoRowHeight: CGFloat = 60
        static let audioRowHeight: CGFloat = 50
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
            Hairline(vertical: false)
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    headerColumn
                    Hairline(vertical: true)
                    ScrollView(.horizontal) {
                        canvas
                    }
                }
            }
        }
        .background(Theme.panel)
        .overlay {
            // Petunjuk saat timeline masih kosong; tidak menghalangi klik atau seret.
            if project.clipCount == 0 {
                Label("Seret media dari Library ke sini, atau tekan ⌘I", systemImage: "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(Theme.raised, in: Capsule())
                    .overlay(Capsule().stroke(Theme.divider))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Toolbar

    /// Bilah alat: aksi edit di kiri (bisa digulir saat layar sempit), kontrol zoom tetap di kanan.
    private var toolbar: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    IconButton(systemImage: "arrow.uturn.backward", help: "Urungkan", shortcut: "⌘Z",
                               isDisabled: !store.canUndo) { store.undo() }
                    IconButton(systemImage: "arrow.uturn.forward", help: "Ulangi", shortcut: "⇧⌘Z",
                               isDisabled: !store.canRedo) { store.redo() }
                    toolDivider
                    IconButton(systemImage: "scissors", help: "Belah pada playhead", shortcut: "S") { store.splitAtPlayhead() }
                    IconButton(systemImage: "trash", help: "Hapus clip", shortcut: "⌫") { store.deleteSelected(ripple: false) }
                    IconButton(systemImage: "rectangle.compress.vertical", help: "Hapus dan rapatkan", shortcut: "⇧⌫") {
                        store.deleteSelected(ripple: true)
                    }
                    IconButton(systemImage: "plus.square.on.square", help: "Duplikat clip", shortcut: "⌘D") { store.duplicateSelected() }
                    toolDivider
                    IconButton(systemImage: "link", help: "Tautkan clip sejajar") { store.linkSelected() }
                    IconButton(systemImage: "link.badge.plus", help: "Pisahkan audio dari video") { store.detachAudioSelected() }
                    IconButton(systemImage: "link.badge.minus", help: "Lepas tautan") { store.unlinkSelected() }
                    toolDivider
                    IconButton(systemImage: "textformat", help: "Tambah teks di playhead") { store.addTitle() }
                    IconButton(systemImage: "flag", help: "Tambah marker di playhead", shortcut: "M") { store.addMarker() }
                    IconButton(
                        systemImage: "magnet",
                        help: store.snappingEnabled ? "Snap aktif, klik untuk mematikan" : "Snap mati, klik untuk menyalakan",
                        isOn: store.snappingEnabled
                    ) { store.snappingEnabled.toggle() }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 4) {
                IconButton(systemImage: "minus.magnifyingglass", help: "Perkecil timeline", size: 24) { zoom(by: -20) }
                Slider(value: Binding(
                    get: { store.pixelsPerSecond },
                    set: { store.pixelsPerSecond = $0 }
                ), in: 10...200)
                .controlSize(.small)
                .tint(Theme.accent)
                .frame(width: 110)
                .hoverHelp("Zoom timeline")
                IconButton(systemImage: "plus.magnifyingglass", help: "Perbesar timeline", size: 24) { zoom(by: 20) }
            }
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.panel)
    }

    private var toolDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 4)
    }

    private func zoom(by delta: Double) {
        withAnimation(.easeOut(duration: 0.15)) {
            store.pixelsPerSecond = min(max(store.pixelsPerSecond + delta, 10), 200)
        }
    }

    // MARK: - Header dan canvas

    private var headerColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button { store.addTrack(kind: .video) } label: { Label("Video", systemImage: "plus") }
                    .hoverHelp("Tambah track video di atas")
                Button { store.addTrack(kind: .audio) } label: { Label("Audio", systemImage: "plus") }
                    .hoverHelp("Tambah track audio di bawah")
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
            .hoverHelp(marker.name)
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

    private var tint: Color { track.kind == .video ? Theme.videoClipTop : Theme.audioClipTop }

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(tint)
                .frame(width: 3)
                .padding(.vertical, 8)
            Image(systemName: track.kind == .video ? "film" : "waveform")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(track.name)
                .font(.caption.weight(.bold))
            Spacer(minLength: 0)
            TrackToggle(title: "S", isOn: track.isSolo, onColor: Theme.accent, help: "Solo track") {
                app.store.toggleSolo(trackID: track.id)
            }
            TrackToggle(title: "M", isOn: track.isMuted, onColor: Theme.warning, help: "Bisukan track") {
                app.store.toggleMute(trackID: track.id)
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
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

/// Tombol kecil S/M di header track. Saat aktif, warnanya berubah agar status terlihat sekilas.
private struct TrackToggle: View {
    let title: String
    let isOn: Bool
    let onColor: Color
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.heavy))
                .frame(width: 18, height: 18)
                .foregroundStyle(isOn ? Theme.background : Theme.textSecondary)
                .background(isOn ? onColor : Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .hoverHelp(help)
    }
}

private struct TimelineClipView: View {
    let clip: Clip
    let kind: TrackKind
    let isSelected: Bool
    let peaks: [Float]?

    @State private var hovering = false

    private var colors: (top: Color, bottom: Color) {
        if clip.isTitle { return (Theme.titleClipTop, Theme.titleClip) }
        return kind == .video ? (Theme.videoClipTop, Theme.videoClip) : (Theme.audioClipTop, Theme.audioClip)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let colors = colors
        shape
            .fill(LinearGradient(colors: [colors.top, colors.bottom], startPoint: .top, endPoint: .bottom))
            .overlay {
                if kind == .audio, let peaks {
                    WaveformShape(peaks: peaks, sourceStart: clip.sourceStart.seconds, sourceDuration: clip.sourceDuration.seconds)
                        .padding(.vertical, 6)
                        .clipShape(shape)
                }
            }
            .overlay {
                // Sorotan tipis di atas, memberi kesan permukaan yang timbul.
                shape.stroke(
                    LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
            }
            .overlay {
                if hovering {
                    shape.fill(Color.white.opacity(0.08))
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
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                .padding(.leading, 9)
            }
            .overlay {
                shape.stroke(isSelected ? Theme.accent : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
            .shadow(color: isSelected ? Theme.accent.opacity(0.45) : .clear, radius: 6)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.15), value: isSelected)
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
