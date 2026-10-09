import AVFoundation
import Observation

enum PreviewQuality: String, CaseIterable, Identifiable {
    case full
    case half
    case quarter

    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return "Penuh"
        case .half: return "½"
        case .quarter: return "¼"
        }
    }
    var divisor: CGFloat {
        switch self {
        case .full: return 1
        case .half: return 2
        case .quarter: return 4
        }
    }
}

/// Mengelola AVPlayer untuk preview. Komposisi dibangun ulang dengan debounce saat proyek berubah,
/// dan posisi playhead dipertahankan.
@MainActor
@Observable
final class PlaybackController {
    let player = AVPlayer()
    private(set) var skippedClipCount = 0
    var quality: PreviewQuality = .half
    /// Menampilkan sumber tanpa efek (mode Sebelum).
    var showOriginal = false

    @ObservationIgnored private(set) var lastOutput: CompositionBuilder.Output?
    @ObservationIgnored var onFrameChanged: (() -> Void)?
    @ObservationIgnored private let store: EditorStore
    @ObservationIgnored private let proxies: ProxyManager
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?

    init(store: EditorStore, proxies: ProxyManager) {
        self.store = store
        self.proxies = proxies
        // Playhead mengikuti pemutaran. Seek dari UI lewat `seek(to:)`.
        _ = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.player.rate != 0 else { return }
                self.store.playhead = Ticks(seconds: time.seconds)
            }
        }
    }

    var isPlaying: Bool { player.rate != 0 }

    func togglePlayback() {
        if isPlaying {
            player.pause()
            onFrameChanged?()
            return
        }
        if store.project.duration > .zero, store.playhead >= store.project.duration {
            seek(to: .zero)
        }
        player.play()
    }

    func seek(to time: Ticks) {
        let clamped = min(max(time, .zero), store.project.duration)
        store.playhead = clamped
        player.seek(to: clamped.cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in self?.onFrameChanged?() }
        }
    }

    /// Melangkah satu frame ke depan atau belakang.
    func step(frames: Int) {
        let frame = Ticks(seconds: 1.0 / Double(max(store.project.sequence.frameRate, 1)))
        seek(to: store.playhead + Ticks(frame.units * Int64(frames)))
    }

    func scheduleRebuild(_ project: Project) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self else { return }
            await self.rebuild(with: project)
        }
    }

    func rebuild(with project: Project) async {
        let wasPlaying = isPlaying
        guard project.duration > .zero else {
            player.replaceCurrentItem(with: nil)
            skippedClipCount = 0
            lastOutput = nil
            return
        }

        // Peta proxy dihitung di sini agar builder tidak menyentuh state aktor utama.
        let useProxies = store.useProxies
        var proxyMap: [UUID: URL] = [:]
        if useProxies {
            for item in project.media {
                if let url = proxies.proxyURL(for: item) { proxyMap[item.id] = url }
            }
        }

        do {
            let options = CompositionBuilder.Options(
                renderSize: project.sequence.renderSize,
                frameRate: project.sequence.frameRate,
                proxyURL: { proxyMap[$0.id] },
                applyEffects: !showOriginal
            )
            let output = try await CompositionBuilder.build(project: project, options: options)
            guard !Task.isCancelled else { return }

            let item = AVPlayerItem(asset: output.composition)
            item.videoComposition = output.videoComposition
            item.audioMix = output.audioMix
            let divisor = quality.divisor
            let size = project.sequence.renderSize
            item.preferredMaximumResolution = divisor == 1 ? .zero : CGSize(width: size.width / divisor, height: size.height / divisor)

            player.replaceCurrentItem(with: item)
            lastOutput = output
            skippedClipCount = output.skippedClipCount
            seek(to: store.playhead)
            if wasPlaying { player.play() }
        } catch {
            store.notify("Preview gagal dibuat: \(error.localizedDescription)")
        }
    }
}
