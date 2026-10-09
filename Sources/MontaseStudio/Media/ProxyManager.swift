import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// Membuat proxy 960 px (sisi terpanjang) untuk preview. Antrean berjalan satu per satu,
/// dapat dijeda oleh tekanan memori, dan proxy selalu dibuat dari file asli.
@MainActor
@Observable
final class ProxyManager {
    enum Status: Equatable {
        case none
        case queued
        case generating(Double)
        case ready
        case failed(String)
    }

    static let maxLongSide: CGFloat = 960

    private(set) var statuses: [UUID: Status] = [:]
    private(set) var isPaused = false

    @ObservationIgnored var onReadyChange: (() -> Void)?
    @ObservationIgnored private var queue: [MediaItem] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var activeSession: Transcoder.Session?

    static let directory: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent("Montase Studio/Proxies", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func url(for mediaID: UUID) -> URL {
        directory.appendingPathComponent("\(mediaID.uuidString).mp4")
    }

    func status(for item: MediaItem) -> Status {
        if let known = statuses[item.id] { return known }
        return FileManager.default.fileExists(atPath: Self.url(for: item.id).path) ? .ready : .none
    }

    func proxyURL(for item: MediaItem) -> URL? {
        status(for: item) == .ready ? Self.url(for: item.id) : nil
    }

    /// Menjadwalkan proxy untuk media video yang belum punya proxy. Media yang gagal tidak dicoba ulang
    /// otomatis (setiap edit memanggil ini); coba lagi hanya lewat `retryFailed` dari permintaan pengguna.
    func request(_ items: [MediaItem], retryFailed: Bool = false) {
        for item in items where item.hasVideo && !queue.contains(where: { $0.id == item.id }) {
            switch status(for: item) {
            case .none:
                statuses[item.id] = .queued
                queue.append(item)
            case .failed where retryFailed:
                statuses[item.id] = .queued
                queue.append(item)
            default:
                continue
            }
        }
        kick()
    }

    func pause() {
        isPaused = true
        worker?.cancel()
        activeSession?.cancel()
    }

    func resume() {
        isPaused = false
        kick()
    }

    private func kick() {
        guard worker == nil, !isPaused, let next = queue.first else { return }
        worker = Task { [weak self] in
            await self?.process(next)
        }
    }

    private func process(_ item: MediaItem) async {
        statuses[item.id] = .generating(0)
        let target = Self.url(for: item.id)
        let partial = Self.directory.appendingPathComponent("\(item.id.uuidString).part.mp4")

        do {
            let size = Self.proxySize(for: item)
            let frameRate = 30
            var project = Project()
            project.sequence = SequenceSettings(width: Int(size.width), height: Int(size.height), frameRate: frameRate)
            project.registerMedia(item)
            guard let track = project.defaultTrackID(for: .video) else { throw ProxyError.noVideoTrack }
            project.addClip(mediaID: item.id, toTrack: track, at: .zero)

            let output = try await CompositionBuilder.build(
                project: project,
                options: .init(renderSize: size, frameRate: frameRate)
            )
            let session = try Transcoder.makeSession(
                output,
                settings: .init(size: size, codec: .h264, bitrate: 4_000_000, frameRate: frameRate),
                to: partial,
                totalSeconds: item.duration.seconds
            )
            activeSession = session
            try await session.run { [weak self] value in
                Task { @MainActor in self?.statuses[item.id] = .generating(value) }
            }
            activeSession = nil

            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: partial, to: target)
            statuses[item.id] = .ready
            dequeue(item)
        } catch {
            activeSession = nil
            try? FileManager.default.removeItem(at: partial)
            if Task.isCancelled {
                // Dijeda: tetap di antrean untuk dilanjutkan nanti.
                statuses[item.id] = .queued
            } else {
                statuses[item.id] = .failed(error.localizedDescription)
                dequeue(item)
            }
        }

        worker = nil
        onReadyChange?()
        kick()
    }

    private func dequeue(_ item: MediaItem) {
        if queue.first?.id == item.id { queue.removeFirst() }
    }

    /// Ukuran proxy: sisi terpanjang maksimal 960 px, mempertahankan orientasi, dengan dimensi genap.
    static func proxySize(for item: MediaItem) -> CGSize {
        let width = CGFloat(max(item.width, 2))
        let height = CGFloat(max(item.height, 2))
        let scale = min(1, maxLongSide / max(width, height))
        return CGSize(width: evenize(width * scale), height: evenize(height * scale))
    }

    private static func evenize(_ value: CGFloat) -> CGFloat {
        max(2, (value / 2).rounded() * 2)
    }

    enum ProxyError: LocalizedError {
        case noVideoTrack

        var errorDescription: String? { "Media tidak memiliki track video." }
    }
}
