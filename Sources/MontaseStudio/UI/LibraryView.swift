import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    let app: AppState

    @State private var query = ""
    @State private var folder: String?
    @State private var isDropTargeted = false

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
                Text("\(media.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Theme.raised, in: Capsule())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                IconButton(systemImage: "plus", help: "Impor media", shortcut: "⌘I") { app.presentImportPanel() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            searchField
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            if !folders.isEmpty {
                folderBar
            }
            Hairline(vertical: false)

            if media.isEmpty {
                EmptyStateView(
                    systemImage: "square.and.arrow.down.on.square",
                    title: "Library masih kosong",
                    message: "Seret file video atau audio ke sini, atau impor dari komputer.",
                    actionTitle: "Impor Media…",
                    action: { app.presentImportPanel() }
                )
            } else if visible.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Theme.textTertiary)
                    Text("Tidak ada media yang cocok")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
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
        .overlay {
            // Umpan balik saat file diseret ke panel.
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .background(Theme.accent.opacity(0.06))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            importDropped(providers)
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            TextField("Cari media", text: $query)
                .textFieldStyle(.plain)
                .font(.callout)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .hoverHelp("Hapus pencarian")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.divider))
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
            .padding(.bottom, 10)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(selected ? Theme.accent : Theme.raised, in: Capsule())
                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
                .overlay(Capsule().stroke(selected ? .clear : Theme.divider))
        }
        .buttonStyle(PressableStyle())
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

    @State private var hovering = false

    private var isOnline: Bool { FileManager.default.fileExists(atPath: item.path) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MediaThumbnail(item: item)
                .frame(height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Text(item.duration.clockString)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                        .padding(4)
                }
                .overlay(alignment: .topLeading) {
                    // Jenis media: video atau audio.
                    Image(systemName: item.hasVideo ? "film" : "waveform")
                        .font(.caption2.weight(.bold))
                        .padding(4)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(4)
                }
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(hovering ? Theme.accent.opacity(0.7) : .clear, lineWidth: 1.5))
                .scaleEffect(hovering ? 1.03 : 1)

            Text(item.name)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .foregroundStyle(Theme.textPrimary)
            if !isOnline {
                Label("File hilang", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.warning)
            }
        }
        .padding(4)
        .background(hovering ? Theme.hover : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hovering)
        .draggable(item.id.uuidString)
        .onTapGesture(count: 2) {
            app.store.addToTimeline(mediaID: item.id)
        }
        .hoverHelp("Klik dua kali untuk menambah ke timeline, atau seret ke track", edge: .bottom)
        .contextMenu {
            Button("Tambah ke Timeline") { app.store.addToTimeline(mediaID: item.id) }
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
}

private struct MediaThumbnail: View {
    let item: MediaItem
    @State private var image: CGImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.surfaceActive, Theme.raised], startPoint: .top, endPoint: .bottom)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                Image(systemName: item.hasVideo ? "film" : "waveform")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.25), value: image != nil)
        .task(id: item.id) {
            if item.hasVideo {
                image = await MediaImporter.thumbnail(for: item)
            }
        }
    }
}
