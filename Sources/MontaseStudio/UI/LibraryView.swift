import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let app: AppState

    @State private var query = ""
    @State private var folder: String?

    private var media: [MediaItem] { app.store.project.media }

    private var folders: [String] {
        Array(Set(media.map(\.folder).filter { !$0.isEmpty })).sorted()
    }

    private var visible: [MediaItem] {
        media.filter { item in
            (folder == nil || item.folder == folder) &&
            (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("LIBRARY").panelTitle()
                Spacer()
                Button { app.presentImportPanel() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Impor media (⌘I)")
            }
            .padding(12)

            TextField("Cari media", text: $query)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if !folders.isEmpty {
                folderBar
            }
            Divider()

            if media.isEmpty {
                emptyState
            } else if visible.isEmpty {
                Text("Tidak ada media yang cocok.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 12) {
                        ForEach(visible) { item in
                            MediaTile(item: item, app: app, folders: folders)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            importDropped(providers)
        }
    }

    private var folderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("Semua", selected: folder == nil) { folder = nil }
                ForEach(folders, id: \.self) { name in
                    chip(name, selected: folder == name) { folder = name }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(selected ? Theme.accent : Theme.surfaceActive, in: Capsule())
                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.and.arrow.down")
                .font(.title2)
                .foregroundStyle(Theme.textSecondary)
            Text("Seret file video atau audio ke sini")
                .font(.callout)
            Text("atau tekan ⌘I")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
    }

    private func importDropped(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in await app.importMedia(urls: [url]) }
            }
        }
        return accepted
    }
}

private struct MediaTile: View {
    let item: MediaItem
    let app: AppState
    let folders: [String]

    private var isOnline: Bool { FileManager.default.fileExists(atPath: item.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            MediaThumbnail(item: item)
                .frame(height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottomTrailing) {
                    Text(item.duration.clockString)
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                        .padding(4)
                }
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
            badge
        }
        .contentShape(Rectangle())
        .draggable(item.id.uuidString)
        .onTapGesture(count: 2) {
            app.store.addToTimeline(mediaID: item.id)
        }
        .contextMenu {
            Button("Tambah ke Timeline") { app.store.addToTimeline(mediaID: item.id) }
            if item.hasVideo {
                Button("Buat Proxy") { app.requestProxy(for: item) }
                    .disabled(app.proxies.status(for: item) == .ready)
            }
            Menu("Pindahkan ke Folder") {
                Button("Tanpa Folder") { app.store.setFolder(mediaID: item.id, folder: "") }
                ForEach(folders, id: \.self) { name in
                    Button(name) { app.store.setFolder(mediaID: item.id, folder: name) }
                }
                Button("Folder Baru…") {
                    Prompt.text(title: "Nama folder", initial: "") { name in
                        app.store.setFolder(mediaID: item.id, folder: name)
                    }
                }
            }
            if !isOnline {
                Button("Relink…") { app.presentRelinkPanel(for: item) }
            }
        }
    }

    @ViewBuilder
    private var badge: some View {
        if !isOnline {
            Label("File hilang", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(Theme.warning)
        } else if item.hasVideo {
            switch app.proxies.status(for: item) {
            case .ready:
                Label("Proxy siap", systemImage: "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            case .queued:
                Label("Proxy dalam antrean", systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            case .generating(let value):
                ProgressView(value: value)
                    .controlSize(.mini)
            case .failed(let message):
                Text(message).font(.caption2).foregroundStyle(Theme.warning).lineLimit(1)
            case .none:
                EmptyView()
            }
        }
    }
}

private struct MediaThumbnail: View {
    let item: MediaItem
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.surfaceActive)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: item.hasVideo ? "film" : "waveform")
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .clipped()
        .task(id: item.id) {
            if item.hasVideo {
                image = await MediaImporter.thumbnail(for: item)
            }
        }
    }
}
