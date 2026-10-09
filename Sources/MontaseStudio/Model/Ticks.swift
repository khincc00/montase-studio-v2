import CoreMedia
import Foundation

/// Waktu timeline dalam satuan bilangan bulat, sehingga operasi berulang tidak menumpuk error floating-point.
/// 60.000 unit per detik dapat merepresentasikan frame 24, 25, 30, dan 60 fps secara tepat.
struct Ticks: Codable, Hashable, Comparable, Sendable {
    static let perSecond: Int64 = 60_000
    static let zero = Ticks(0)
    static let infinite = Ticks(Int64.max / 4)

    var units: Int64

    init(_ units: Int64) {
        self.units = units
    }

    init(seconds: Double) {
        units = Int64((seconds * Double(Ticks.perSecond)).rounded())
    }

    var seconds: Double { Double(units) / Double(Ticks.perSecond) }
    var cmTime: CMTime { CMTime(value: units, timescale: CMTimeScale(Ticks.perSecond)) }

    /// Mengalikan durasi dengan faktor (mis. speed) dalam satu pembulatan.
    func scaled(by factor: Double) -> Ticks {
        Ticks(Int64((Double(units) * factor).rounded()))
    }

    /// Format mm:ss untuk ruler dan daftar.
    var clockString: String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Format hh:mm:ss:ff untuk viewer dan inspector.
    func timecode(frameRate: Int) -> String {
        let fps = max(frameRate, 1)
        let totalFrames = max(0, Int((seconds * Double(fps)).rounded(.down)))
        let totalSeconds = totalFrames / fps
        return String(
            format: "%02d:%02d:%02d:%02d",
            totalSeconds / 3600,
            (totalSeconds / 60) % 60,
            totalSeconds % 60,
            totalFrames % fps
        )
    }

    static func + (lhs: Ticks, rhs: Ticks) -> Ticks { Ticks(lhs.units + rhs.units) }
    static func - (lhs: Ticks, rhs: Ticks) -> Ticks { Ticks(lhs.units - rhs.units) }
    static func < (lhs: Ticks, rhs: Ticks) -> Bool { lhs.units < rhs.units }
}
