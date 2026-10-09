import XCTest
@testable import MontaseStudio

/// Uji untuk perbaikan yang dicatat di README dan hasil tinjauan kode.
@MainActor
final class RegressionTests: XCTestCase {
    // MARK: - Ekspor

    func testExportSuffixDistinguishesOrientations() {
        var settings = ExportSettings()
        XCTAssertEqual(settings.fileSuffix, "")

        settings.orientation = .portrait
        XCTAssertEqual(settings.fileSuffix, "-vertikal")

        // Square dulu ikut "-vertikal" karena kondisi lama hanya membandingkan lebar > tinggi.
        settings.orientation = .square
        XCTAssertEqual(settings.fileSuffix, "-persegi")
    }

    func testExportQualityScalesBitrate() {
        var settings = ExportSettings()
        XCTAssertEqual(settings.bitrate, 12_000_000)

        settings.quality = .high
        XCTAssertEqual(settings.bitrate, 19_200_000)

        settings.codec = .hevc
        XCTAssertEqual(settings.bitrate, 12_800_000)
    }

    // MARK: - Undo

    func testUndoHistoryIsCappedAt50() {
        let store = EditorStore()
        let initialTracks = store.project.tracks.count
        for _ in 0..<60 {
            store.addTrack(kind: .video)
        }
        XCTAssertEqual(store.undoSteps.count, EditorStore.undoLimit)
        XCTAssertEqual(EditorStore.undoLimit, 50)

        // Hanya 50 langkah yang bisa diurungkan; 10 langkah terlama sudah tidak bisa dikembalikan.
        for _ in 0..<50 {
            store.undo()
        }
        XCTAssertFalse(store.canUndo)
        XCTAssertEqual(store.project.tracks.count, initialTracks + 10)
    }

    // MARK: - Penyimpanan

    func testCorruptProjectFileThrows() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("corrupt-\(UUID().uuidString).montase")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{ bukan json".utf8).write(to: url)

        XCTAssertThrowsError(try ProjectStorage.read(from: url))
    }

    func testProjectRoundTripsThroughStorage() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("roundtrip-\(UUID().uuidString).montase")
        defer { try? FileManager.default.removeItem(at: url) }

        var project = Project()
        project.name = "Uji"
        _ = project.addMarker(at: Ticks(seconds: 2), name: "A")
        try ProjectStorage.write(project, to: url)

        let loaded = try ProjectStorage.read(from: url)
        XCTAssertEqual(loaded, project)
    }

    func testNewerSchemaIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("future-\(UUID().uuidString).montase")
        defer { try? FileManager.default.removeItem(at: url) }

        var project = Project()
        project.schemaVersion = Project.currentSchemaVersion + 1
        try ProjectStorage.write(project, to: url)

        XCTAssertThrowsError(try ProjectStorage.read(from: url))
    }
}
