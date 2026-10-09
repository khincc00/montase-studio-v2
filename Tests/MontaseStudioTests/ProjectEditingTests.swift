import XCTest
@testable import MontaseStudio

final class ProjectEditingTests: XCTestCase {
    private var project = Project()
    private var videoTrack: UUID { project.tracks[1].id }   // V1
    private var audioTrack: UUID { project.tracks[2].id }   // A1

    private func registerVideo(seconds: Double, name: String = "Clip") -> MediaItem {
        let item = MediaItem(
            name: name,
            path: "/tmp/\(UUID().uuidString).mov",
            duration: Ticks(seconds: seconds),
            hasVideo: true,
            hasAudio: true,
            width: 1920,
            height: 1080
        )
        return project.registerMedia(item)
    }

    private func place(_ item: MediaItem, on trackID: UUID, at seconds: Double) -> UUID? {
        project.addClip(mediaID: item.id, toTrack: trackID, at: Ticks(seconds: seconds))
    }

    private func clip(_ id: UUID?) -> Clip {
        guard let id, let clip = project.clip(id: id) else {
            XCTFail("Clip tidak ditemukan")
            fatalError()
        }
        return clip
    }

    func testTicksTimecodeUsesFrameRate() {
        XCTAssertEqual(Ticks(seconds: 1.5).timecode(frameRate: 30), "00:00:01:15")
        XCTAssertEqual(Ticks(seconds: 65).clockString, "01:05")
    }

    func testSplitCreatesContiguousHalvesWithSourceOffset() throws {
        let item = registerVideo(seconds: 10)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 0))

        let rightID = try XCTUnwrap(project.split(clipID: id, at: Ticks(seconds: 4)))

        let left = clip(id)
        let right = clip(rightID)
        XCTAssertEqual(left.duration, Ticks(seconds: 4))
        XCTAssertEqual(right.timelineStart, Ticks(seconds: 4))
        XCTAssertEqual(right.sourceStart, Ticks(seconds: 4))
        XCTAssertEqual(right.duration, Ticks(seconds: 6))
    }

    func testSplitOutsideClipIsRejected() throws {
        let item = registerVideo(seconds: 10)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 0))
        XCTAssertNil(project.split(clipID: id, at: Ticks(seconds: 10)))
        XCTAssertNil(project.split(clipID: id, at: Ticks(seconds: 0)))
    }

    func testTrailingTrimIsClampedToMediaEnd() throws {
        let item = registerVideo(seconds: 10)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 0))

        project.trimClip(id: id, edge: .trailing, to: Ticks(seconds: 20))

        XCTAssertEqual(clip(id).duration, Ticks(seconds: 10))
    }

    func testLeadingTrimCannotExtendBeforeMediaStart() throws {
        let item = registerVideo(seconds: 10)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 5))
        project.split(clipID: id, at: Ticks(seconds: 7))   // sisakan bagian kanan agar tidak mengubah id kiri
        project.trimClip(id: id, edge: .leading, to: Ticks(seconds: 0))

        // Sumber dimulai dari 0, jadi awal timeline tidak boleh kurang dari 5 detik.
        XCTAssertEqual(clip(id).timelineStart, Ticks(seconds: 5))
    }

    func testRippleDeleteShiftsFollowingClips() throws {
        let first = registerVideo(seconds: 4, name: "A")
        let second = registerVideo(seconds: 4, name: "B")
        let firstID = try XCTUnwrap(place(first, on: videoTrack, at: 0))
        let secondID = try XCTUnwrap(place(second, on: videoTrack, at: 4))

        project.deleteClips(ids: [firstID], ripple: true)

        XCTAssertEqual(clip(secondID).timelineStart, .zero)
    }

    func testPlainDeleteLeavesGap() throws {
        let first = registerVideo(seconds: 4, name: "A")
        let second = registerVideo(seconds: 4, name: "B")
        let firstID = try XCTUnwrap(place(first, on: videoTrack, at: 0))
        let secondID = try XCTUnwrap(place(second, on: videoTrack, at: 4))

        project.deleteClips(ids: [firstID], ripple: false)

        XCTAssertEqual(clip(secondID).timelineStart, Ticks(seconds: 4))
    }

    func testMoveIntoOverlapIsRejected() throws {
        let first = registerVideo(seconds: 4, name: "A")
        let second = registerVideo(seconds: 4, name: "B")
        let firstID = try XCTUnwrap(place(first, on: videoTrack, at: 0))
        let secondID = try XCTUnwrap(place(second, on: videoTrack, at: 10))

        XCTAssertFalse(project.moveClip(id: secondID, toTrack: videoTrack, at: Ticks(seconds: 2)))
        XCTAssertEqual(clip(secondID).timelineStart, Ticks(seconds: 10))
        XCTAssertNotNil(project.clip(id: firstID))
    }

    func testMoveAcrossTrackKindIsRejected() throws {
        let item = registerVideo(seconds: 4)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 0))

        XCTAssertFalse(project.moveClip(id: id, toTrack: audioTrack, at: .zero))
    }

    func testVideoCannotBePlacedOnAudioTrack() {
        let item = registerVideo(seconds: 4)
        XCTAssertNil(place(item, on: audioTrack, at: 0))
    }

    func testDuplicatePlacesCopyAfterOriginal() throws {
        let item = registerVideo(seconds: 4)
        let id = try XCTUnwrap(place(item, on: videoTrack, at: 0))

        let copyID = try XCTUnwrap(project.duplicateClip(id: id))

        XCTAssertEqual(clip(copyID).timelineStart, Ticks(seconds: 4))
        XCTAssertEqual(clip(copyID).mediaID, item.id)
    }

    func testRegisteringSameFileTwiceReusesEntry() {
        let item = registerVideo(seconds: 4)
        let again = project.registerMedia(MediaItem(
            name: item.name,
            path: item.path,
            duration: item.duration,
            hasVideo: true,
            hasAudio: true,
            width: 1920,
            height: 1080
        ))
        XCTAssertEqual(again.id, item.id)
        XCTAssertEqual(project.media.count, 1)
    }
}
