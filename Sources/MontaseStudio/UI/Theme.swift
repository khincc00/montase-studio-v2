import SwiftUI

/// Palet dan ukuran dasar. Dipusatkan di sini agar tampilan bisa diubah dari satu tempat.
enum Theme {
    // Permukaan: grafit gelap dengan lapisan yang makin terang.
    static let background = Color(hex: 0x0D0F12)
    static let panel = Color(hex: 0x15181D)
    static let raised = Color(hex: 0x1D2128)
    static let surfaceActive = Color(hex: 0x262C36)
    static let hover = Color.white.opacity(0.06)
    static let pressed = Color.white.opacity(0.1)

    static let textPrimary = Color(hex: 0xEEF2F7)
    static let textSecondary = Color(hex: 0x9AA5B5)
    static let textTertiary = Color(hex: 0x66707F)

    // Aksen: teal segar untuk tindakan dan status aktif.
    static let accent = Color(hex: 0x3DD9C5)
    static let accentDeep = Color(hex: 0x14937F)
    static let warning = Color(hex: 0xF7B955)
    static let danger = Color(hex: 0xFF6B6B)

    // Warna klip: biru-violet untuk video, hijau-teal untuk audio, magenta untuk teks.
    static let videoClip = Color(hex: 0x4F6BFF)
    static let videoClipTop = Color(hex: 0x6F86FF)
    static let audioClip = Color(hex: 0x17A38A)
    static let audioClipTop = Color(hex: 0x2CC7A8)
    static let titleClip = Color(hex: 0xB04FD9)
    static let titleClipTop = Color(hex: 0xCB6FF0)

    static let divider = Color.white.opacity(0.07)
    static let radius: CGFloat = 10
    static let smallRadius: CGFloat = 7
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
            .tracking(0.6)
            .foregroundStyle(Theme.textSecondary)
    }

    /// Kartu gelap dengan sudut membulat, dipakai untuk mengelompokkan kontrol.
    func card(padding: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .stroke(Theme.divider, lineWidth: 1)
            )
    }
}
