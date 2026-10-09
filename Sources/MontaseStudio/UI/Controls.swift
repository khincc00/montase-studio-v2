import SwiftUI

/// Slider yang hanya menulis ke model saat pengguna selesai menggeser, supaya undo tidak penuh entri.
struct CommitSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let value: Double
    var step: Double?
    let format: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(shown))
                    .font(.caption.monospacedDigit())
            }
            Slider(
                value: Binding(get: { shown }, set: { draft = $0 }),
                in: range,
                step: step ?? (range.upperBound - range.lowerBound) / 200,
                onEditingChanged: { editing in
                    guard !editing, let committed = draft else { return }
                    onCommit(committed)
                    draft = nil
                }
            )
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
            Text(value)
                .font(.callout.monospacedDigit())
                .lineLimit(2)
                .textSelection(.enabled)
        }
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
    }
}
