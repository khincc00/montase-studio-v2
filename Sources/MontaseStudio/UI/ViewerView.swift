import AVFoundation
import AVKit
import SwiftUI

struct ViewerView: View {
    let app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black
                PlayerSurface(player: app.playback.player)
                if app.store.project.clipCount == 0 {
                    Text("Tambahkan media ke timeline untuk melihat preview")
                        .foregroundStyle(Theme.textSecondary)
                }
                if app.playback.showOriginal {
                    Text("SEBELUM")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.warning, in: Capsule())
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(10)
                }
            }
            TransportBar(app: app)
        }
    }
}

private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

/// Dibuat terpisah agar pembaruan playhead 30 Hz hanya me-render bagian ini.
private struct TransportBar: View {
    let app: AppState

    private var quality: Binding<PreviewQuality> {
        Binding(
            get: { app.playback.quality },
            set: { app.playback.quality = $0; app.refreshPreview() }
        )
    }

    var body: some View {
        let project = app.store.project
        HStack(spacing: 12) {
            Button { app.playback.togglePlayback() } label: {
                Image(systemName: app.playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help("Putar / Jeda (Space)")

            Text("\(app.store.playhead.timecode(frameRate: project.sequence.frameRate)) / \(project.duration.timecode(frameRate: project.sequence.frameRate))")
                .font(.callout.monospacedDigit())

            Spacer()

            Toggle("Proxy", isOn: Binding(
                get: { app.store.useProxies },
                set: { app.store.useProxies = $0; app.refreshPreview() }
            ))
            .toggleStyle(.checkbox)
            .help("Pakai proxy untuk preview bila sudah siap")

            Picker("Kualitas", selection: quality) {
                ForEach(PreviewQuality.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 130)
            .help("Kualitas preview")

            if app.playback.skippedClipCount > 0 {
                Label("\(app.playback.skippedClipCount) dilewati", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
            }

            Text("\(project.sequence.width)×\(project.sequence.height) · \(project.sequence.frameRate) fps")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel)
    }
}
