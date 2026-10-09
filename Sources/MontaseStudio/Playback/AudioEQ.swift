import AudioToolbox
import AVFoundation
import Foundation
import MediaToolbox

/// Filter biquad (RBJ cookbook) untuk equalizer dasar.
struct Biquad {
    enum Shape {
        case lowShelf
        case peaking
        case highShelf
    }

    private var b0 = 1.0
    private var b1 = 0.0
    private var b2 = 0.0
    private var a1 = 0.0
    private var a2 = 0.0
    private var x1 = 0.0
    private var x2 = 0.0
    private var y1 = 0.0
    private var y2 = 0.0

    init(shape: Shape, frequency: Double, gainDB: Double, q: Double = 1, sampleRate: Double) {
        let amp = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * frequency / sampleRate
        let cosw = cos(w0)
        let sinw = sin(w0)
        let sqrtAmp = sqrt(amp)

        let (nb0, nb1, nb2, na0, na1, na2): (Double, Double, Double, Double, Double, Double)
        switch shape {
        case .peaking:
            let alpha = sinw / (2 * q)
            (nb0, nb1, nb2) = (1 + alpha * amp, -2 * cosw, 1 - alpha * amp)
            (na0, na1, na2) = (1 + alpha / amp, -2 * cosw, 1 - alpha / amp)
        case .lowShelf:
            let alpha = sinw / 2 * sqrt(2)
            (nb0, nb1, nb2) = (
                amp * ((amp + 1) - (amp - 1) * cosw + 2 * sqrtAmp * alpha),
                2 * amp * ((amp - 1) - (amp + 1) * cosw),
                amp * ((amp + 1) - (amp - 1) * cosw - 2 * sqrtAmp * alpha)
            )
            (na0, na1, na2) = (
                (amp + 1) + (amp - 1) * cosw + 2 * sqrtAmp * alpha,
                -2 * ((amp - 1) + (amp + 1) * cosw),
                (amp + 1) + (amp - 1) * cosw - 2 * sqrtAmp * alpha
            )
        case .highShelf:
            let alpha = sinw / 2 * sqrt(2)
            (nb0, nb1, nb2) = (
                amp * ((amp + 1) + (amp - 1) * cosw + 2 * sqrtAmp * alpha),
                -2 * amp * ((amp - 1) + (amp + 1) * cosw),
                amp * ((amp + 1) + (amp - 1) * cosw - 2 * sqrtAmp * alpha)
            )
            (na0, na1, na2) = (
                (amp + 1) - (amp - 1) * cosw + 2 * sqrtAmp * alpha,
                2 * ((amp - 1) - (amp + 1) * cosw),
                (amp + 1) - (amp - 1) * cosw - 2 * sqrtAmp * alpha
            )
        }

        b0 = nb0 / na0
        b1 = nb1 / na0
        b2 = nb2 / na0
        a1 = na1 / na0
        a2 = na2 / na0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1
        x1 = x
        y2 = y1
        y1 = y
        return y
    }
}

/// Equalizer tiga pita yang dipasang sebagai audio tap pada setiap track audio di `AVAudioMix`.
/// Karena berada di audio mix, efeknya ikut terbawa ke preview maupun export.
enum AudioEQ {
    final class Context {
        private let settings: EQSettings
        private var filters: [[Biquad]] = []

        init(settings: EQSettings) {
            self.settings = settings
        }

        func prepare(sampleRate: Double, channels: Int) {
            filters = (0..<max(channels, 1)).map { _ in
                [
                    Biquad(shape: .lowShelf, frequency: 120, gainDB: settings.low, sampleRate: sampleRate),
                    Biquad(shape: .peaking, frequency: 1000, gainDB: settings.mid, q: 1, sampleRate: sampleRate),
                    Biquad(shape: .highShelf, frequency: 8000, gainDB: settings.high, sampleRate: sampleRate),
                ]
            }
        }

        /// Format tap yang dipakai AVFoundation adalah float non-interleaved: satu buffer per kanal.
        func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            for (channel, buffer) in buffers.enumerated() where channel < filters.count {
                guard let data = buffer.mData else { continue }
                let samples = data.assumingMemoryBound(to: Float.self)
                for index in 0..<frames {
                    var value = Double(samples[index])
                    for stage in filters[channel].indices {
                        value = filters[channel][stage].process(value)
                    }
                    samples[index] = Float(value)
                }
            }
        }
    }

    static func makeTap(for settings: EQSettings) -> MTAudioProcessingTap? {
        let storage = Unmanaged.passRetained(Context(settings: settings)).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: storage,
            init: audioTapInit,
            finalize: audioTapFinalize,
            prepare: audioTapPrepare,
            unprepare: audioTapUnprepare,
            process: audioTapProcess
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &tap
        )
        guard status == noErr, let tap else {
            Unmanaged<Context>.fromOpaque(storage).release()
            return nil
        }
        return tap
    }
}

private func audioContext(of tap: MTAudioProcessingTap) -> AudioEQ.Context {
    Unmanaged<AudioEQ.Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private func audioTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func audioTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<AudioEQ.Context>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func audioTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ format: UnsafePointer<AudioStreamBasicDescription>
) {
    audioContext(of: tap).prepare(
        sampleRate: format.pointee.mSampleRate,
        channels: Int(format.pointee.mChannelsPerFrame)
    )
}

private func audioTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func audioTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }
    audioContext(of: tap).process(bufferListInOut, frames: Int(numberFramesOut.pointee))
}
