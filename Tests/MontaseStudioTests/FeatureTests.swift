import CoreImage
import XCTest
@testable import MontaseStudio

/// Test untuk fitur yang ditambahkan setelah MVP: speed, tautan, marker, track, relink, migrasi, EQ, geometri, dan LUT.
final class FeatureTests: XCTestCase {
    private var project = Project()
    private var videoTrack: UUID { project.tracks[1].id }   // V1
    private var topTrack: UUID { project.tracks[0].id }     // V2
    private var audioTrack: UUID { project.tracks[2].id }   // A1

    private func register(seconds: Double, hasVideo: Bool = true, hasAudio: Bool = true, name: String = "Clip") -> MediaItem {
        project.registerMedia(MediaItem(
            name: name,
            path: "/tmp/\(UUID().uuidString).mov",
            duration: Ticks(seconds: seconds),
            hasVideo: hasVideo,
            hasAudio: hasAudio,
            width: 1920,
            height: 1080
        ))
    }

    private func clip(_ id: UUID?) -> Clip {
        guard let id, let clip = project.clip(id: id) else {
            XCTFail("Clip tidak ditemukan")
            fatalError()
        }
        return clip
    }

    // MARK: - Speed

    func testSpeedChangesTimelineDurationButKeepsSourceDuration() throws {
        let item = register(seconds: 8)
        let id = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: .zero))

        XCTAssertTrue(project.setSpeed(clipID: id, speed: 2))

        XCTAssertEqual(clip(id).duration.seconds, 4, accuracy: 0.001)
        XCTAssertEqual(clip(id).sourceDuration.seconds, 8, accuracy: 0.001)
    }

    func testSpeedIsRejectedWhenItOverlapsNextClip() throws {
        let item = register(seconds: 4)
        let id = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: .zero))
        _ = project.addClip(mediaID: item.id, toTrack: videoTrack, at: Ticks(seconds: 4.5))

        XCTAssertFalse(project.setSpeed(clipID: id, speed: 0.5)) // durasi jadi 8 s, menabrak klip kedua
        XCTAssertEqual(clip(id).speed, 1)
    }

    func testLeadingTrimWithSpeedAdvancesSourceByScaledAmount() throws {
        let item = register(seconds: 20)
        let id = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: Ticks(seconds: 10)))
        XCTAssertTrue(project.setSpeed(clipID: id, speed: 2))   // timeline 5 s, sumber 10 s

        project.trimClip(id: id, edge: .leading, to: Ticks(seconds: 11))

        XCTAssertEqual(clip(id).timelineStart.seconds, 11, accuracy: 0.001)
        XCTAssertEqual(clip(id).sourceStart.seconds, 2, accuracy: 0.001) // 1 s timeline = 2 s sumber
    }

    // MARK: - Tautan dan audio terpisah

    func testLinkedClipsMoveTogether() throws {
        let item = register(seconds: 2)
        let music = register(seconds: 2, hasVideo: false, name: "Musik")
        let video = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: Ticks(seconds: 1)))
        let audio = try XCTUnwrap(project.addClip(mediaID: music.id, toTrack: audioTrack, at: Ticks(seconds: 1)))
        project.link(ids: [video, audio])

        XCTAssertTrue(project.moveClip(id: video, toTrack: videoTrack, at: Ticks(seconds: 5)))

        XCTAssertEqual(clip(video).timelineStart.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(clip(audio).timelineStart.seconds, 5, accuracy: 0.001)
    }

    func testDetachAudioCreatesLinkedAudioClipAndMutesVideo() throws {
        let item = register(seconds: 3)
        let video = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: .zero))

        XCTAssertTrue(project.detachAudio(clipID: video))

        let audioClip = try XCTUnwrap(project.tracks[2].clips.first)
        XCTAssertEqual(audioClip.mediaID, item.id)
        XCTAssertEqual(clip(video).volume, 0)
        XCTAssertNotNil(clip(video).linkID)
        XCTAssertEqual(clip(video).linkID, audioClip.linkID)
    }

    func testUnlinkRemovesGroup() throws {
        let item = register(seconds: 2)
        let music = register(seconds: 2, hasVideo: false, name: "Musik")
        let a = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: .zero))
        let b = try XCTUnwrap(project.addClip(mediaID: music.id, toTrack: audioTrack, at: .zero))
        project.link(ids: [a, b])
        project.unlink(clipID: a)

        XCTAssertNil(clip(a).linkID)
        XCTAssertNil(clip(b).linkID)
    }

    // MARK: - Teks, marker, dan track

    func testTitleClipIsOnlyAllowedOnVideoTracks() throws {
        XCTAssertNotNil(project.addTitle(TitleStyle(), toTrack: topTrack, at: .zero))
        XCTAssertNil(project.addTitle(TitleStyle(), toTrack: audioTrack, at: Ticks(seconds: 10)))
    }

    func testMarkersStaySortedAndCanBeRemoved() {
        let late = project.addMarker(at: Ticks(seconds: 9), name: "B")
        let early = project.addMarker(at: Ticks(seconds: 2), name: "A")

        XCTAssertEqual(project.markers.map(\.id), [early, late])
        project.removeMarker(id: early)
        XCTAssertEqual(project.markers.map(\.id), [late])
    }

    func testAddingVideoTrackRenumbersNames() {
        project.addTrack(kind: .video)

        XCTAssertEqual(project.tracks.filter { $0.kind == .video }.map(\.name), ["V3", "V2", "V1"])
        XCTAssertEqual(project.tracks.filter { $0.kind == .audio }.map(\.name), ["A1", "A2"])
    }

    func testRemovingNonEmptyOrLastTrackIsRejected() throws {
        // Simpan id di awal: indeks track berubah setelah penghapusan.
        let top = topTrack
        let bottom = videoTrack
        let item = register(seconds: 1)
        _ = project.addClip(mediaID: item.id, toTrack: bottom, at: .zero)

        XCTAssertFalse(project.removeTrack(id: bottom))  // tidak kosong
        XCTAssertTrue(project.removeTrack(id: top))      // kosong, masih ada track video lain
        XCTAssertFalse(project.removeTrack(id: bottom))  // satu-satunya track video
    }

    // MARK: - Media dan migrasi

    func testRelinkKeepsMediaIdAndClips() throws {
        let item = register(seconds: 3)
        let id = try XCTUnwrap(project.addClip(mediaID: item.id, toTrack: videoTrack, at: .zero))
        let replacement = MediaItem(name: "x", path: "/tmp/baru.mov", duration: Ticks(seconds: 3), hasVideo: true, hasAudio: false, width: 1280, height: 720)

        project.relinkMedia(id: item.id, to: replacement)

        XCTAssertEqual(project.mediaItem(id: item.id)?.path, "/tmp/baru.mov")
        XCTAssertEqual(clip(id).mediaID, item.id)
    }

    func testSchemaV1FileDecodesWithDefaults() throws {
        let json = """
        {
          "schemaVersion": 1,
          "name": "Lama",
          "sequence": { "width": 1920, "height": 1080, "frameRate": 30 },
          "media": [{ "id": "11111111-1111-1111-1111-111111111111", "name": "A", "path": "/tmp/a.mov",
                      "duration": { "units": 60000 }, "hasVideo": true, "hasAudio": true, "width": 1920, "height": 1080 }],
          "tracks": [{ "id": "22222222-2222-2222-2222-222222222222", "kind": "video", "name": "V1",
                       "isMuted": false, "clips": [{ "id": "33333333-3333-3333-3333-333333333333",
                       "mediaID": "11111111-1111-1111-1111-111111111111", "name": "A",
                       "sourceStart": { "units": 0 }, "timelineStart": { "units": 0 }, "duration": { "units": 60000 } }] }]
        }
        """
        let decoded = try JSONDecoder().decode(Project.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.name, "Lama")
        XCTAssertEqual(decoded.tracks[0].clips[0].speed, 1)
        XCTAssertEqual(decoded.tracks[0].clips[0].opacity, 1)
        XCTAssertEqual(decoded.tracks[0].volume, 1)
        XCTAssertEqual(decoded.markers, [])
        XCTAssertEqual(decoded.media[0].folder, "")
    }

    // MARK: - Audio dan geometri

    /// Peaking +12 dB di 1 kHz harus menguatkan sinus 1 kHz sekitar 4 kali (10^(12/20)).
    func testPeakingEQBoostsCenterFrequency() {
        let sampleRate = 48_000.0
        var filter = Biquad(shape: .peaking, frequency: 1000, gainDB: 12, q: 1, sampleRate: sampleRate)
        var inputPower = 0.0
        var outputPower = 0.0
        for n in 0..<48_000 {
            let x = sin(2 * Double.pi * 1000 * Double(n) / sampleRate)
            let y = filter.process(x)
            if n > 4_800 {
                inputPower += x * x
                outputPower += y * y
            }
        }
        let gain = sqrt(outputPower / inputPower)
        XCTAssertEqual(gain, pow(10, 12.0 / 20), accuracy: 0.25)
    }

    func testFlatEQIsDetected() {
        XCTAssertTrue(EQSettings().isFlat)
        XCTAssertFalse(EQSettings(low: 2, mid: 0, high: 0).isFlat)
    }

    /// Klip 2:1 di kanvas 200×200 harus di-fit ke lebar penuh dan dipusatkan vertikal.
    func testPlacementFitsAndCentersAspectCorrectly() {
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 50))
        let placement = LayerPlacement(
            orientation: .identity,
            naturalSize: CGSize(width: 100, height: 50),
            orientedSize: CGSize(width: 100, height: 50),
            transform: Transform()
        )
        let extent = EffectCompositor.place(source, placement, canvas: CGRect(x: 0, y: 0, width: 200, height: 200)).extent

        XCTAssertEqual(extent.width, 200, accuracy: 0.5)
        XCTAssertEqual(extent.height, 100, accuracy: 0.5)
        XCTAssertEqual(extent.midY, 100, accuracy: 0.5)
    }

    func testCropReducesVisibleExtent() {
        let source = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        var transform = Transform()
        transform.cropLeft = 0.25
        transform.cropRight = 0.25
        let placement = LayerPlacement(
            orientation: .identity,
            naturalSize: CGSize(width: 100, height: 100),
            orientedSize: CGSize(width: 100, height: 100),
            transform: transform
        )
        let extent = EffectCompositor.place(source, placement, canvas: CGRect(x: 0, y: 0, width: 200, height: 200)).extent

        // Sisa 50 × 100 px, di-fit ke kanvas 200 × 200 (skala 2) → 100 × 200.
        XCTAssertEqual(extent.width, 100, accuracy: 0.5)
        XCTAssertEqual(extent.height, 200, accuracy: 0.5)
    }

    func testTitleRendererProducesCanvasSizedImage() {
        let image = TitleRenderer.image(for: TitleStyle(), canvas: CGSize(width: 640, height: 360))
        XCTAssertEqual(image.extent.width, 640, accuracy: 0.5)
        XCTAssertEqual(image.extent.height, 360, accuracy: 0.5)
    }

    func testCubeLUTParsesTwoByTwoByTwo() throws {
        let cube = """
        TITLE "Test"
        LUT_3D_SIZE 2
        0 0 0
        1 0 0
        0 1 0
        1 1 0
        0 0 1
        1 0 1
        0 1 1
        1 1 1
        """
        let lut = try XCTUnwrap(LUTLoader.parseCube(cube))
        XCTAssertEqual(lut.dimension, 2)
        XCTAssertEqual(lut.data.count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)
    }

    func testExportSizeFollowsOrientation() {
        var settings = ExportSettings()
        settings.resolution = .hd
        settings.orientation = .portrait
        XCTAssertEqual(settings.size, CGSize(width: 1080, height: 1920))
        settings.orientation = .square
        XCTAssertEqual(settings.size, CGSize(width: 1080, height: 1080))
        settings.resolution = .uhd
        settings.orientation = .landscape
        XCTAssertEqual(settings.size, CGSize(width: 3840, height: 2160))
    }
}
