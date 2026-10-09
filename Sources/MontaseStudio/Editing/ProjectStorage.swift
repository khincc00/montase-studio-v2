import Foundation

/// Penyimpanan proyek sebagai JSON. Penulisan atomik agar file tidak rusak saat aplikasi berhenti mendadak.
enum ProjectStorage {
    static let fileExtension = "montase"

    /// Salinan pemulihan yang ditulis otomatis; dihapus setelah proyek disimpan secara eksplisit.
    static var recoveryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support
            .appendingPathComponent("Montase Studio", isDirectory: true)
            .appendingPathComponent("recovery.\(fileExtension)")
    }

    static func write(_ project: Project, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> Project {
        let project = try JSONDecoder().decode(Project.self, from: Data(contentsOf: url))
        guard project.schemaVersion <= Project.currentSchemaVersion else {
            throw StorageError.newerSchema
        }
        return project
    }

    enum StorageError: LocalizedError {
        case newerSchema

        var errorDescription: String? {
            "Proyek ini dibuat oleh versi aplikasi yang lebih baru."
        }
    }
}
