import AVFoundation
import AVKit
import SwiftUI

struct ViewerView: View {
    let app: AppState

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.background
                // Layar video dengan bingkai tipis agar batas kanvas jelas di atas latar gelap.
                ZStack {
                    Color.black
                    PlayerSurface(player: app.playback.player)
                    if app.store.project.clipCount == 0 {
                        EmptyStateView(
                            systemImage: "play.rectangle",
                            title: "Belum ada gambar",
                            message: "Tambahkan media ke timeline untuk melihat preview di sini.",
                            actionTitle: "Impor Media…",
                            action: { app.presentImportPanel() }
                        )
                    }
                    if app.playback.showOriginal {
                        Text("SEBELUM")
                            .font(.caption2.weight(.bold))
                            .tracking(0.8)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.warning, in: Capsule())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.divider))
                .padding(14)
            }
            .animation(.easeOut(duration: 0.2), value: app.playback.showOriginal)
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
        let frameRate = project.sequence.frameRate
        HStack(spacing: 10) {
            IconButton(systemImage: "backward.end.fill", help: "Ke awal", shortcut: "Home") {
                app.playback.seek(to: .zero)
            }
            IconButton(systemImage: "backward.frame.fill", help: "Frame sebelumnya", shortcut: "←") {
                app.playback.step(frames: -1)
            }

            Button { app.playback.togglePlayback() } label: {
                Image(systemName: app.playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Theme.background)
                    .frame(width: 36, height: 36)
                    .background(Theme.accent, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(PressableStyle())
            .hoverHelp(app.playback.isPlaying ? "Jeda" : "Putar", shortcut: "Space")

            IconButton(systemImage: "forward.frame.fill", help: "Frame berikutnya", shortcut: "→") {
                app.playback.step(frames: 1)
            }

            // Kapsul waktu: posisi playhead dan durasi total.
            HStack(spacing: 6) {
                Text(app.store.playhead.timecode(frameRate: frameRate))
                    .foregroundStyle(Theme.textPrimary)
                Text("/")
                    .foregroundStyle(Theme.textTertiary)
                Text(project.duration.timecode(frameRate: frameRate))
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.callout.monospacedDigit().weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().stroke(Theme.divider))

            Spacer(minLength: 8)

            if app.playback.skippedClipCount > 0 {
                Label("\(app.playback.skippedClipCount) dilewati", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.warning)
                    .hoverHelp("Klip dengan file hilang tidak ditampilkan. Gunakan Relink di Library.")
            }

            Text("\(project.sequence.width)×\(project.sequence.height) · \(frameRate) fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .hoverHelp("Ukuran dan frame rate sequence")

            Picker("Kualitas", selection: quality) {
                ForEach(PreviewQuality.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 130)
            .hoverHelp("Kualitas preview: makin kecil makin ringan saat diputar")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.panel)
        .overlay(alignment: .top) { Hairline(vertical: false) }
    }
}
