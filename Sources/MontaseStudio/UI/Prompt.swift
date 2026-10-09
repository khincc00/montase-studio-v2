import AppKit

/// Dialog satu field teks. Dipakai untuk nama marker dan folder, agar tidak ada TextField yang
/// bisa diganggu pintasan huruf tunggal di kanvas.
@MainActor
enum Prompt {
    static func text(title: String, initial: String, confirm: String = "OK", onSubmit: (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: initial)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Batal")

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            onSubmit(value)
        }
    }
}
