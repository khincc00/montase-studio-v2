import Foundation

/// LUT 3D dalam format RGBA float yang dibaca CIColorCube.
struct LUTData {
    let dimension: Int
    let data: Data
}

enum LUTLoader {
    /// Membaca berkas .cube 3D. LUT 1D tidak didukung.
    static func parseCube(_ text: String) -> LUTData? {
        var size = 0
        var values: [Float] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)

            if parts.first == "LUT_3D_SIZE", parts.count > 1, let n = Int(parts[1]) {
                size = n
            } else if parts.count == 3, let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                values += [r, g, b, 1]
            }
        }

        guard size > 1, values.count == size * size * size * 4 else { return nil }
        return LUTData(dimension: size, data: values.withUnsafeBufferPointer { Data(buffer: $0) })
    }
}

/// Cache LUT per jalur berkas. Dipakai dari thread compositor, karena itu dilindungi lock.
final class LUTCache: @unchecked Sendable {
    static let shared = LUTCache()

    private let lock = NSLock()
    private var cache: [String: LUTData] = [:]

    func lut(at path: String) -> LUTData? {
        lock.lock()
        defer { lock.unlock() }

        if let hit = cache[path] { return hit }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let lut = LUTLoader.parseCube(text) else { return nil }
        cache[path] = lut
        return lut
    }
}
