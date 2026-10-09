import AppKit
import SwiftUI
import XCTest
@testable import MontaseStudio

/// Merender setiap workspace ke gambar tanpa window (ImageRenderer). Memastikan layout dibangun dan tidak crash.
@MainActor
final class UIRenderTests: XCTestCase {
    private func render(_ app: AppState, name: String) throws {
        let view = WorkspaceView(app: app)
            .preferredColorScheme(.dark)
            .frame(width: 1400, height: 860)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertGreaterThan(image.width, 1000)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MontaseIT-frames/ui-\(name).png")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])?.write(to: url)
        print("UI \(name): \(url.path)")
    }

    private func sampleApp() -> AppState {
        var project = Project()
        project.name = "Contoh"
        let video = MediaItem(name: "Klip A", path: "/tmp/none-a.mov", duration: Ticks(seconds: 6), hasVideo: true, hasAudio: true, width: 1920, height: 1080)
        let music = MediaItem(name: "Musik", path: "/tmp/none-m.m4a", duration: Ticks(seconds: 8), hasVideo: false, hasAudio: true, width: 0, height: 0)
        let v = project.registerMedia(video)
        let m = project.registerMedia(music)
        let v1 = project.tracks[1].id
        let a1 = project.tracks[2].id
        let clip = project.addClip(mediaID: v.id, toTrack: v1, at: .zero)!
        _ = project.addClip(mediaID: m.id, toTrack: a1, at: .zero)
        _ = project.addTitle(TitleStyle(text: "Judul"), toTrack: project.tracks[0].id, at: Ticks(seconds: 1), duration: Ticks(seconds: 2))
        project.addMarker(at: Ticks(seconds: 2), name: "Tengah")
        _ = clip
        let app = AppState()
        app.store.replaceProject(project, fileURL: nil)
        app.store.selectedClipID = clip
        return app
    }

    func testRenderAllWorkspaces() throws {
        let app = sampleApp()
        for workspace in Workspace.allCases {
            app.show(workspace)
            try render(app, name: workspace.rawValue)
        }
    }
}
