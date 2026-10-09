import SwiftUI

/// Workspace Audio: fader per track, mute/solo, EQ tiga pita, dan meter yang dibaca dari gelombang sumber di playhead.
struct AudioPanel: View {
    let app: AppState

    private var store: EditorStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("AUDIO").panelTitle()
                    Spacer()
                    Text("Playhead \(store.playhead.timecode(frameRate: store.project.sequence.frameRate))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(store.project.tracks.filter { $0.kind == .audio || $0.clips.contains { $0.mediaID != nil } }) { track in
                    trackStrip(track)
                }
                Text("Meter menampilkan puncak sumber di playhead. Equalizer memengaruhi preview dan export.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private func trackStrip(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(track.name)
                    .font(.callout.weight(.bold))
                Spacer()
                Button { store.toggleSolo(trackID: track.id) } label: {
                    Text("S")
                        .font(.caption.weight(.heavy))
                        .frame(width: 24, height: 22)
                        .foregroundStyle(track.isSolo ? Theme.background : Theme.textSecondary)
                        .background(track.isSolo ? Theme.accent : Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .hoverHelp("Solo: hanya track ini yang terdengar")
                Button { store.toggleMute(trackID: track.id) } label: {
                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 24, height: 22)
                        .foregroundStyle(track.isMuted ? Theme.background : Theme.textPrimary)
                        .background(track.isMuted ? Theme.warning : Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PressableStyle())
                .hoverHelp(track.isMuted ? "Aktifkan track" : "Bisukan track")
            }

            meter(level: level(for: track))

            CommitSlider(title: "Fader", range: 0...2, value: track.volume, defaultValue: 1,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                store.updateTrack(track.id, "Ubah Fader") { $0.volume = value }
            }

            CollapsibleSection(title: "Equalizer", systemImage: "slider.vertical.3", initiallyExpanded: false) {
                VStack(alignment: .leading, spacing: 12) {
                    CommitSlider(title: "Low · 120 Hz", range: -12...12, value: track.eq.low, defaultValue: 0,
                                 format: { String(format: "%+.1f dB", $0) }) { value in
                        store.updateTrack(track.id, "Ubah EQ") { $0.eq.low = value }
                    }
                    CommitSlider(title: "Mid · 1 kHz", range: -12...12, value: track.eq.mid, defaultValue: 0,
                                 format: { String(format: "%+.1f dB", $0) }) { value in
                        store.updateTrack(track.id, "Ubah EQ") { $0.eq.mid = value }
                    }
                    CommitSlider(title: "High · 8 kHz", range: -12...12, value: track.eq.high, defaultValue: 0,
                                 format: { String(format: "%+.1f dB", $0) }) { value in
                        store.updateTrack(track.id, "Ubah EQ") { $0.eq.high = value }
                    }
                    if !track.eq.isFlat {
                        Button { store.updateTrack(track.id, "Reset EQ") { $0.eq = EQSettings() } } label: {
                            Label("Reset EQ", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.pill)
                    }
                }
            }
        }
        .card()
    }

    /// Meter dengan gradasi hijau-kuning-merah, seperti meter studio.
    private func meter(level: Double) -> some View {
        let db = level > 0 ? max(20 * log10(level), -60) : -60
        let fraction = (db + 60) / 60
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.background)
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Theme.audioClipTop, Theme.accent, Theme.warning, Theme.danger],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .frame(width: max(proxy.size.width * fraction, 0))
                        .animation(.linear(duration: 0.05), value: fraction)
                }
            }
            .frame(height: 8)
            HStack {
                Text("Level")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text(db <= -60 ? "−∞ dB" : String(format: "%.1f dB", db))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(db > -6 ? Theme.warning : Theme.textSecondary)
            }
        }
    }

    /// Puncak linear track di playhead: peak sumber × volume clip × fader track.
    private func level(for track: Track) -> Double {
        guard !track.isMuted else { return 0 }
        let time = store.playhead
        var peak: Float = 0
        for clip in track.clips where clip.timelineStart <= time && time < clip.end {
            guard let mediaID = clip.mediaID else { continue }
            let sourceSeconds = clip.sourceStart.seconds + (time - clip.timelineStart).seconds * clip.speed
            if let value = app.waveforms.peak(for: mediaID, atSourceSeconds: sourceSeconds) {
                peak = max(peak, value * Float(clip.volume))
            }
        }
        return Double(peak) * track.volume
    }
}
