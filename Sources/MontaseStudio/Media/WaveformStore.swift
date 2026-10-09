import AVFoundation
import Foundation
import Observation

/// Puncak amplitudo audio per 20 ms. Dipakai untuk gambar gelombang di timeline dan meter di panel Audio.
@MainActor
@Observable
final class WaveformStore {
    private(set) var peaks: [UUID: [Float]] = [:]
    @ObservationIgnored private var inFlight: Set<UUID> = []

    func request(_ item: MediaItem) {
        guard item.hasAudio, peaks[item.id] == nil, !inFlight.contains(item.id) else { return }
        inFlight.insert(item.id)

        let id = item.id
        let url = item.url
        Task { [weak self] in
            let values = await Waveform.compute(url: url)
            guard let self else { return }
            self.peaks[id] = values
            self.inFlight.remove(id)
        }
    }

    /// Peak pada posisi sumber tertentu (detik), atau nil jika belum dihitung.
    func peak(for mediaID: UUID, atSourceSeconds seconds: Double) -> Float? {
        guard let values = peaks[mediaID], !values.isEmpty else { return nil }
        let index = Int(seconds * Waveform.bucketsPerSecond)
        guard index >= 0, index < values.count else { return nil }
        return values[index]
    }
}

enum Waveform {
    static let bucketsPerSecond = 50.0

    static func compute(url: URL) async -> [Float] {
        await Task.detached(priority: .utility) { () -> [Float] in
            let asset = AVURLAsset(url: url)
            guard let track = (try? await asset.loadTracks(withMediaType: .audio))?.first,
                  let reader = try? AVAssetReader(asset: asset) else { return [] }

            let sampleRate = 16_000.0
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: sampleRate,
            ])
            reader.add(output)
            guard reader.startReading() else { return [] }

            let samplesPerBucket = Int(sampleRate / bucketsPerSecond)
            var peaks: [Float] = []
            var current: Float = 0
            var count = 0

            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                var length = 0
                var pointer: UnsafeMutablePointer<CChar>?
                CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
                guard let pointer else { continue }

                let floatCount = length / MemoryLayout<Float>.size
                pointer.withMemoryRebound(to: Float.self, capacity: floatCount) { floats in
                    for index in 0..<floatCount {
                        current = max(current, abs(floats[index]))
                        count += 1
                        if count == samplesPerBucket {
                            peaks.append(current)
                            current = 0
                            count = 0
                        }
                    }
                }
            }
            if count > 0 { peaks.append(current) }
            return peaks
        }.value
    }
}
