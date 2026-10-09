import AVFoundation
import Foundation

/// Bagian sunyi dalam audio, dalam detik dari awal media.
struct SilenceInterval: Equatable {
    let start: Double
    let end: Double
    var middle: Double { (start + end) / 2 }
}

/// Mendeteksi jeda dari energi sinyal audio. Recognizer on-device tidak memberi jeda yang bisa diandalkan
/// (kata-katanya menyambung), dan tidak memberi tanda baca, sehingga batas kalimat diambil dari audio langsung.
enum AutoClipSilence {
    /// Jendela pengukuran dan ambang sunyi. Di bawah -40 dBFS dianggap diam.
    static let windowSeconds = 0.05
    static let thresholdDecibels: Float = -40

    static func detect(in url: URL, minimumSeconds: Double = AutoClipRules.sentenceGapSeconds / 2) throws -> [SilenceInterval] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        let windowFrames = max(Int(sampleRate * windowSeconds), 1)
        let chunkFrames: AVAudioFrameCount = 65_536
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else { return [] }

        var silentWindows: [Bool] = []
        var energy = 0.0
        var count = 0

        // Berhenti tepat di akhir berkas; membaca melewati akhir berkas melempar error di AVAudioFile.
        while file.framePosition < file.length {
            let remaining = AVAudioFrameCount(file.length - file.framePosition)
            try file.read(into: buffer, frameCount: min(chunkFrames, remaining))
            let frames = Int(buffer.frameLength)
            if frames == 0 { break }
            guard let channel = buffer.floatChannelData?[0] else { break }
            for index in 0..<frames {
                let sample = Double(channel[index])
                energy += sample * sample
                count += 1
                if count == windowFrames {
                    let rms = Float((energy / Double(count)).squareRoot())
                    silentWindows.append(decibels(rms) < thresholdDecibels)
                    energy = 0
                    count = 0
                }
            }
        }
        return intervals(from: silentWindows, minimumSeconds: minimumSeconds)
    }

    static func decibels(_ rms: Float) -> Float {
        guard rms > 0 else { return -160 }
        return 20 * log10(rms)
    }

    /// Mengubah deret jendela sunyi menjadi interval yang cukup panjang.
    static func intervals(from silentWindows: [Bool], minimumSeconds: Double) -> [SilenceInterval] {
        var result: [SilenceInterval] = []
        var runStart: Int?
        for (index, silent) in silentWindows.enumerated() {
            if silent {
                if runStart == nil { runStart = index }
            } else if let start = runStart {
                append(start, index, &result, minimumSeconds)
                runStart = nil
            }
        }
        if let start = runStart {
            append(start, silentWindows.count, &result, minimumSeconds)
        }
        return result
    }

    private static func append(_ start: Int, _ end: Int, _ result: inout [SilenceInterval], _ minimumSeconds: Double) {
        let interval = SilenceInterval(start: Double(start) * windowSeconds, end: Double(end) * windowSeconds)
        if interval.end - interval.start >= minimumSeconds {
            result.append(interval)
        }
    }
}
