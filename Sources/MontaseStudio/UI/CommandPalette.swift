import SwiftUI

/// Pencarian perintah (⌘K). Enter menjalankan hasil pertama.
struct CommandPalette: View {
    let app: AppState

    @State private var query = ""

    private var results: [PaletteCommand] {
        let all = app.paletteCommands
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Cari perintah…", text: $query)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if let first = results.first { run(first) }
                }

            List(results) { command in
                Button {
                    run(command)
                } label: {
                    HStack {
                        Text(command.title)
                        Spacer()
                        if !command.shortcut.isEmpty {
                            Text(command.shortcut)
                                .font(.caption.monospaced())
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 340)
        }
        .padding(16)
        .frame(width: 480)
        .background(Theme.panel)
    }

    private func run(_ command: PaletteCommand) {
        app.isPaletteOpen = false
        command.action()
    }
}
