import Foundation

/// Bahasa ucapan yang bisa dipilih. Ketersediaan tiap bahasa dicek saat transkripsi berjalan,
/// karena model offline hanya ada jika sudah dipasang di macOS.
struct AutoClipLanguage: Identifiable, Hashable {
    let id: String
    let name: String

    static let all: [AutoClipLanguage] = [
        AutoClipLanguage(id: "id-ID", name: "Indonesia"),
        AutoClipLanguage(id: "en-US", name: "Inggris (AS)"),
        AutoClipLanguage(id: "en-GB", name: "Inggris (UK)"),
        AutoClipLanguage(id: "ms-MY", name: "Melayu"),
        AutoClipLanguage(id: "ja-JP", name: "Jepang"),
        AutoClipLanguage(id: "ko-KR", name: "Korea"),
        AutoClipLanguage(id: "zh-CN", name: "Mandarin (Tiongkok)"),
        AutoClipLanguage(id: "es-ES", name: "Spanyol"),
        AutoClipLanguage(id: "fr-FR", name: "Prancis"),
        AutoClipLanguage(id: "de-DE", name: "Jerman"),
        AutoClipLanguage(id: "pt-BR", name: "Portugis (Brasil)"),
        AutoClipLanguage(id: "it-IT", name: "Italia"),
        AutoClipLanguage(id: "nl-NL", name: "Belanda"),
        AutoClipLanguage(id: "ru-RU", name: "Rusia"),
        AutoClipLanguage(id: "ar-SA", name: "Arab"),
        AutoClipLanguage(id: "hi-IN", name: "Hindi"),
        AutoClipLanguage(id: "th-TH", name: "Thai"),
        AutoClipLanguage(id: "vi-VN", name: "Vietnam"),
        AutoClipLanguage(id: "tr-TR", name: "Turki"),
    ]

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }
}
