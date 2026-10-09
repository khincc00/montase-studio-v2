import SwiftUI

/// Pencarian perintah (⌘K). Panah atas-bawah memilih, Enter menjalankan, Esc menutup.
struct CommandPalette: View {
    let app: AppState

    @State private var query = ""
    @State private var selection = 0
    @FocusState private var searchFocused: Bool

    private var results: [PaletteCommand] {
        let all = app.paletteCommands
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.accent)
                TextField("Cari perintah…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit { runSelected() }
                    .onChange(of: query) { _, _ in selection = 0 }
                Text("esc")
                    .font(.caption2.monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(14)

            Hairline(vertical: false)

            if results.isEmpty {
                Text("Tidak ada perintah yang cocok")
                    .font(.callout)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                row(command, selected: index == selection)
                                    .id(command.id)
                                    .onTapGesture { run(command) }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 340)
                    .onChange(of: selection) { _, newValue in
                        guard results.indices.contains(newValue) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(results[newValue].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(width: 520)
        .background(Theme.panel)
        .onAppear { searchFocused = true }
        .onKeyPress(.downArrow) {
            selection = min(selection + 1, max(results.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selection = max(selection - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            app.isPaletteOpen = false
            return .handled
        }
    }

    private func row(_ command: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text(command.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(selected ? Theme.background : Theme.textPrimary)
            Spacer()
            if !command.shortcut.isEmpty {
                Text(command.shortcut)
                    .font(.caption.monospaced().weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(selected ? Theme.background.opacity(0.15) : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(selected ? Theme.background : Theme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(selected ? Theme.accent : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: selected)
    }

    private func runSelected() {
        guard results.indices.contains(selection) else { return }
        run(results[selection])
    }

    private func run(_ command: PaletteCommand) {
        app.isPaletteOpen = false
        command.action()
    }
}
