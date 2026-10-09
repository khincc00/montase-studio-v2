import AVFoundation
import CoreGraphics
import Foundation

/// Mengubah proyek menjadi komposisi AVFoundation dengan compositor kustom.
/// Dipakai bersama oleh preview dan export. Sumbernya selalu file asli.
enum CompositionBuilder {
    struct Options {
        var renderSize: CGSize
        var frameRate: Int = 30
        /// False menampilkan sumber tanpa transform, warna, fade, dan opacity (mode Sebelum).
        var applyEffects = true
    }

    struct Output {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition?
        let audioMix: AVMutableAudioMix?
        /// Clip yang dilewati karena file hilang atau gagal dibaca.
        let skippedClipCount: Int
    }

    enum BuildError: Error {
        case trackCreationFailed
    }

    private struct PendingLayer {
        let trackIndex: Int
        let layer: EffectLayer
    }

    static func build(project: Project, options: Options) async throws -> Output {
        let composition = AVMutableComposition()
        var assets: [URL: AVURLAsset] = [:]
        var videoTracks: [Int: AVMutableCompositionTrack] = [:]
        var pending: [PendingLayer] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var skipped = 0
        var sourceColorInfo: ColorInfo?
        let soloActive = project.tracks.contains { $0.isSolo }

        for (trackIndex, track) in project.tracks.enumerated() {
            let audible = !track.isMuted && (!soloActive || track.isSolo)

            for clip in track.clips {
                do {
                    if let style = clip.title {
                        let image = TitleRenderer.image(for: style, canvas: options.renderSize)
                        pending.append(PendingLayer(
                            trackIndex: trackIndex,
                            layer: makeLayer(clip, source: .title(image), effects: options.applyEffects)
                        ))
                        continue
                    }

                    guard let item = project.mediaItem(for: clip) else {
                        skipped += 1
                        continue
                    }
                    let url = item.url
                    guard FileManager.default.fileExists(atPath: url.path) else {
                        skipped += 1
                        continue
                    }
                    let asset = assets[url] ?? AVURLAsset(url: url)
                    assets[url] = asset

                    let sourceRange = CMTimeRange(start: clip.sourceStart.cmTime, duration: clip.sourceDuration.cmTime)
                    let insertAt = clip.timelineStart.cmTime
                    let timelineDuration = clip.duration.cmTime
                    let stretch = abs(clip.speed - 1) > 0.0001
                    let stretchRange = CMTimeRange(start: insertAt, duration: clip.sourceDuration.cmTime)

                    if track.kind == .video, let sourceVideo = try await asset.loadTracks(withMediaType: .video).first {
                        if videoTracks[trackIndex] == nil {
                            videoTracks[trackIndex] = composition.addMutableTrack(
                                withMediaType: .video,
                                preferredTrackID: kCMPersistentTrackID_Invalid
                            )
                        }
                        guard let compTrack = videoTracks[trackIndex] else { throw BuildError.trackCreationFailed }

                        try compTrack.insertTimeRange(sourceRange, of: sourceVideo, at: insertAt)
                        if stretch {
                            compTrack.scaleTimeRange(stretchRange, toDuration: timelineDuration)
                        }

                        if sourceColorInfo == nil {
                            sourceColorInfo = await ColorInfo.read(from: sourceVideo)
                        }
                        let placement = try await makePlacement(
                            for: sourceVideo,
                            transform: options.applyEffects ? clip.transform : Transform()
                        )
                        pending.append(PendingLayer(
                            trackIndex: trackIndex,
                            layer: makeLayer(clip, source: .track(compTrack.trackID, placement), effects: options.applyEffects)
                        ))
                    }

                    // Audio setiap clip memakai track komposisi sendiri agar volume dan EQ-nya independen.
                    if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
                       let audioTrack = composition.addMutableTrack(
                           withMediaType: .audio,
                           preferredTrackID: kCMPersistentTrackID_Invalid
                       ) {
                        try audioTrack.insertTimeRange(sourceRange, of: sourceAudio, at: insertAt)
                        if stretch {
                            audioTrack.scaleTimeRange(stretchRange, toDuration: timelineDuration)
                        }

                        let params = AVMutableAudioMixInputParameters(track: audioTrack)
                        let level = Float(audible ? clip.volume * track.volume : 0)
                        let fadeIn = options.applyEffects ? clip.fadeIn : .zero
                        let fadeOut = options.applyEffects ? clip.fadeOut : .zero
                        applyVolume(params, level: level, fadeIn: fadeIn, fadeOut: fadeOut, start: insertAt, duration: timelineDuration)
                        if options.applyEffects, !track.eq.isFlat {
                            params.audioTapProcessor = AudioEQ.makeTap(for: track.eq)
                        }
                        audioParameters.append(params)
                    }
                } catch {
                    skipped += 1
                }
            }
        }

        let duration = project.duration

        // Klip teks tidak punya track komposisi, dan media bisa berakhir lebih awal. Filler berdurasi penuh
        // menjaga durasi komposisi sama dengan proyek, sehingga teks di ujung timeline tidak terpotong saat ekspor.
        var fillerID: CMPersistentTrackID?
        if duration > .zero {
            fillerID = try await addDurationFiller(
                to: composition,
                assets: Array(assets.values),
                duration: duration,
                renderSize: options.renderSize
            )
        }

        var videoComposition: AVMutableVideoComposition?
        if duration > .zero, !pending.isEmpty || fillerID != nil {
            videoComposition = makeVideoComposition(pending: pending, duration: duration, options: options, fillerID: fillerID, sourceColorInfo: sourceColorInfo)
        }

        let audioMix: AVMutableAudioMix? = audioParameters.isEmpty ? nil : {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParameters
            return mix
        }()

        return Output(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix,
            skippedClipCount: skipped
        )
    }

    /// Track video yang tidak dirujuk lapisan mana pun, hanya untuk menyamakan durasi komposisi dengan proyek.
    private static func addDurationFiller(
        to composition: AVMutableComposition,
        assets: [AVURLAsset],
        duration: Ticks,
        renderSize: CGSize
    ) async throws -> CMPersistentTrackID? {
        // Timeline tanpa media video (hanya teks) memakai klip hitam sebagai sumber filler.
        let sources = assets.isEmpty ? [AVURLAsset(url: try await BlankClip.url(size: renderSize))] : assets
        for asset in sources {
            guard let source = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let sourceDuration = try await asset.load(.duration)
            guard sourceDuration.seconds > 0,
                  let filler = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                return nil
            }

            let total = duration.cmTime
            var position = CMTime.zero
            while position < total {
                let length = CMTimeMinimum(sourceDuration, total - position)
                try filler.insertTimeRange(CMTimeRange(start: .zero, duration: length), of: source, at: position)
                position = position + length
            }
            return filler.trackID
        }
        return nil
    }

    // MARK: - Video

    /// Membagi timeline pada setiap batas lapisan. Lapisan bawah (indeks track besar) dikomposit lebih dulu.
    private static func makeVideoComposition(
        pending: [PendingLayer],
        duration: Ticks,
        options: Options,
        fillerID: CMPersistentTrackID?,
        sourceColorInfo: ColorInfo?
    ) -> AVMutableVideoComposition {
        var boundaries = Set<Ticks>([.zero, duration])
        for item in pending {
            boundaries.insert(item.layer.start)
            boundaries.insert(item.layer.end)
        }
        let sorted = boundaries.sorted()

        var instructions: [EffectInstruction] = []
        for (start, end) in zip(sorted, sorted.dropFirst()) where end > start {
            let active = pending
                .filter { $0.layer.start <= start && start < $0.layer.end }
                .sorted { $0.trackIndex > $1.trackIndex }
                .map(\.layer)
            instructions.append(EffectInstruction(
                timeRange: CMTimeRange(start: start.cmTime, end: end.cmTime),
                layers: active,
                canvasSize: options.renderSize,
                extraTrackIDs: fillerID.map { [$0] } ?? []
            ))
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = EffectCompositor.self
        videoComposition.renderSize = options.renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(options.frameRate))
        // Warna komposisi harus sama dengan tag sumber; tanpa ini pemutar menafsirkan ulang nada tengah.
        let color = sourceColorInfo ?? ColorInfo.hd
        videoComposition.colorPrimaries = color.primaries
        videoComposition.colorTransferFunction = color.transfer
        videoComposition.colorYCbCrMatrix = color.matrix
        videoComposition.instructions = instructions
        return videoComposition
    }

    private static func makeLayer(_ clip: Clip, source: EffectLayer.Source, effects: Bool) -> EffectLayer {
        EffectLayer(
            source: source,
            grade: effects ? clip.grade : ColorGrade(),
            opacity: effects ? clip.opacity : 1,
            start: clip.timelineStart,
            end: clip.end,
            fadeIn: effects ? clip.fadeIn : .zero,
            fadeOut: effects ? clip.fadeOut : .zero
        )
    }

    /// Orientasi file (rotasi bawaan kamera) dinormalisasi agar cocok dengan ruang Core Image.
    private static func makePlacement(for track: AVAssetTrack, transform: Transform) async throws -> LayerPlacement {
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let bounds = CGRect(origin: .zero, size: natural).applying(preferred).standardized
        let normalized = preferred.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
        return LayerPlacement(
            orientation: normalized,
            naturalSize: natural,
            orientedSize: bounds.size,
            transform: transform
        )
    }

    // MARK: - Audio

    /// Volume dasar dengan fade masuk dan keluar sebagai ramp.
    private static func applyVolume(
        _ params: AVMutableAudioMixInputParameters,
        level: Float,
        fadeIn: Ticks,
        fadeOut: Ticks,
        start: CMTime,
        duration: CMTime
    ) {
        params.setVolume(level, at: .zero)
        if fadeIn > .zero {
            params.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: level,
                timeRange: CMTimeRange(start: start, duration: fadeIn.cmTime)
            )
        }
        if fadeOut > .zero {
            params.setVolumeRamp(
                fromStartVolume: level,
                toEndVolume: 0,
                timeRange: CMTimeRange(start: start + duration - fadeOut.cmTime, duration: fadeOut.cmTime)
            )
        }
    }
}

/// Primaries, transfer, dan matriks YCbCr dari tag track sumber.
struct ColorInfo {
    let primaries: String
    let transfer: String
    let matrix: String

    static let hd = ColorInfo(
        primaries: AVVideoColorPrimaries_ITU_R_709_2,
        transfer: AVVideoTransferFunction_ITU_R_709_2,
        matrix: AVVideoYCbCrMatrix_ITU_R_709_2
    )

    static func read(from track: AVAssetTrack) async -> ColorInfo? {
        guard let description = (try? await track.load(.formatDescriptions))?.first else { return nil }
        func value(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(description, extensionKey: key) as? String
        }
        guard let primaries = value(kCMFormatDescriptionExtension_ColorPrimaries),
              let transfer = value(kCMFormatDescriptionExtension_TransferFunction),
              let matrix = value(kCMFormatDescriptionExtension_YCbCrMatrix) else { return nil }
        return ColorInfo(primaries: primaries, transfer: transfer, matrix: matrix)
    }
}
