import SwiftUI

/// Workspace Audio: fader per track, mute/solo, EQ tiga pita, dan meter yang dibaca dari gelombang sumber di playhead.
struct AudioPanel: View {
    let app: AppState

    private var store: EditorStore { app.store }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("AUDIO").panelTitle()
                ForEach(store.project.tracks.filter { $0.kind == .audio || $0.clips.contains { $0.mediaID != nil } }) { track in
                    trackStrip(track)
                }
                Text("Meter menampilkan puncak sumber di playhead. Equalizer memengaruhi preview dan export.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
    }

    private func trackStrip(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(track.name).font(.callout.weight(.semibold))
                Spacer()
                Button { store.toggleSolo(trackID: track.id) } label: {
                    Text("S").font(.caption.weight(.bold))
                        .frame(width: 20, height: 18)
                        .background(track.isSolo ? Theme.accent : Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                Button { store.toggleMute(trackID: track.id) } label: {
                    Image(systemName: track.isMuted ? "speaker.slash.fill" : "speaker.wave.2")
                        .foregroundStyle(track.isMuted ? Theme.warning : Theme.textPrimary)
                }
                .buttonStyle(.borderless)
            }

            meter(level: level(for: track))

            CommitSlider(title: "Fader", range: 0...2, value: track.volume,
                         format: { "\(Int(($0 * 100).rounded()))%" }) { value in
                store.updateTrack(track.id, "Ubah Fader") { $0.volume = value }
            }
            CommitSlider(title: "EQ Low (120 Hz)", range: -12...12, value: track.eq.low,
                         format: { String(format: "%+.1f dB", $0) }) { value in
                store.updateTrack(track.id, "Ubah EQ") { $0.eq.low = value }
            }
            CommitSlider(title: "EQ Mid (1 kHz)", range: -12...12, value: track.eq.mid,
                         format: { String(format: "%+.1f dB", $0) }) { value in
                store.updateTrack(track.id, "Ubah EQ") { $0.eq.mid = value }
            }
            CommitSlider(title: "EQ High (8 kHz)", range: -12...12, value: track.eq.high,
                         format: { String(format: "%+.1f dB", $0) }) { value in
                store.updateTrack(track.id, "Ubah EQ") { $0.eq.high = value }
            }
            if !track.eq.isFlat {
                Button("Reset EQ") { store.updateTrack(track.id, "Reset EQ") { $0.eq = EQSettings() } }
                    .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func meter(level: Double) -> some View {
        let db = level > 0 ? max(20 * log10(level), -60) : -60
        let fraction = (db + 60) / 60
        return VStack(alignment: .leading, spacing: 2) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceActive)
                    Capsule()
                        .fill(db > -6 ? Theme.warning : Theme.audioClip)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 8)
            Text(db <= -60 ? "−∞ dB" : String(format: "%.1f dB", db))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
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
