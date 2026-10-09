import SwiftUI

/// Palet dari blueprint (dark studio). Dipusatkan di sini agar mudah diubah.
enum Theme {
    static let background = Color(hex: 0x141619)
    static let panel = Color(hex: 0x1D2025)
    static let surfaceActive = Color(hex: 0x282D34)
    static let textPrimary = Color(hex: 0xF2F4F7)
    static let textSecondary = Color(hex: 0xA7AFBA)
    static let accent = Color(hex: 0x58A6FF)
    static let warning = Color(hex: 0xE8B35D)
    static let videoClip = Color(hex: 0x2F5D8C)
    static let audioClip = Color(hex: 0x2E7D6B)
    static let divider = Color.white.opacity(0.08)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Label kecil berhuruf kapital untuk judul panel.
    func panelTitle() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
    }
}
