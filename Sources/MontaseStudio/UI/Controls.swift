import AppKit
import SwiftUI

// MARK: - Tooltip

/// Keterangan fungsi yang muncul saat kursor berhenti di atas elemen. Lebih cepat dan lebih jelas dari `.help`,
/// dan bisa menampilkan pintasan keyboard.
struct HoverTip: ViewModifier {
    let text: String
    let shortcut: String?
    let edge: VerticalEdge

    @State private var visible = false
    @State private var pending: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onHover { hovering in
                pending?.cancel()
                if hovering {
                    pending = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.14)) { visible = true }
                    }
                } else {
                    withAnimation(.easeIn(duration: 0.1)) { visible = false }
                }
            }
            .onDisappear {
                pending?.cancel()
                visible = false
            }
            .accessibilityHint(shortcut.map { "\(text) (\($0))" } ?? text)
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if visible {
                    TipBubble(text: text, shortcut: shortcut)
                        // Bubble berjarak 6 pt dari tepi elemen, di atas atau di bawahnya.
                        .alignmentGuide(edge == .top ? .top : .bottom) { dimensions in
                            edge == .top ? dimensions[.bottom] + 6 : dimensions[.top] - 6
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: edge == .top ? .bottom : .top)))
                        .allowsHitTesting(false)
                        .zIndex(100)
                }
            }
    }
}

extension View {
    /// Menampilkan keterangan fungsi saat kursor diarahkan ke elemen.
    func hoverHelp(_ text: String, shortcut: String? = nil, edge: VerticalEdge = .top) -> some View {
        modifier(HoverTip(text: text, shortcut: shortcut, edge: edge))
    }
}

struct TipBubble: View {
    let text: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.caption.weight(.medium))
            if let shortcut {
                Text(shortcut)
                    .font(.caption2.weight(.semibold).monospaced())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
        .fixedSize()
    }
}

// MARK: - Tombol

/// Tombol ikon dengan latar saat disorot, mengecil sedikit saat ditekan, dan keterangan fungsi.
struct IconButton: View {
    let systemImage: String
    let help: String
    var shortcut: String?
    var isOn = false
    var isDisabled = false
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: size, height: size - 2)
                .foregroundStyle(foreground)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(background)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(isDisabled)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .hoverHelp(help, shortcut: shortcut)
    }

    private var foreground: Color {
        if isDisabled { return Theme.textTertiary }
        return isOn ? Theme.accent : Theme.textPrimary
    }

    private var background: Color {
        if isOn { return Theme.accent.opacity(0.16) }
        return hovering && !isDisabled ? Theme.hover : .clear
    }
}

/// Efek tekan: skala turun sedikit saat ditekan, kembali saat dilepas.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Tombol berbentuk kapsul. `prominent` memakai warna aksen untuk tindakan utama.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, isPressed: configuration.isPressed, prominent: prominent)
    }
}

private struct PillLabel<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let prominent: Bool

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        label
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .foregroundStyle(prominent ? Theme.background : Theme.textPrimary)
            .background(Capsule(style: .continuous).fill(fill))
            .overlay(Capsule(style: .continuous).stroke(prominent ? .clear : Theme.divider))
            .opacity(isEnabled ? 1 : 0.4)
            .scaleEffect(isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var fill: Color {
        if prominent {
            return isPressed ? Theme.accentDeep : (hovering ? Theme.accent.opacity(0.9) : Theme.accent)
        }
        if isPressed { return Theme.pressed }
        return hovering ? Theme.surfaceActive : Theme.raised
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var prominentPill: PillButtonStyle { PillButtonStyle(prominent: true) }
}

// MARK: - Slider dan informasi

/// Slider yang hanya menulis ke model saat pengguna selesai menggeser, supaya undo tidak penuh entri.
/// Klik dua kali pada judul mengembalikan nilai ke default.
struct CommitSlider: View {
    let title: String
    let range: ClosedRange<Double>
    let value: Double
    var step: Double?
    var defaultValue: Double?
    let format: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text(format(shown))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(isChanged(shown) ? Theme.accent : Theme.textPrimary)
                    .contentTransition(.numericText())
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                guard let defaultValue else { return }
                onCommit(defaultValue)
            }
            .hoverHelp(defaultValue == nil ? title : "\(title) — klik dua kali untuk mengembalikan", edge: .bottom)

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
            .controlSize(.small)
            .tint(Theme.accent)
        }
    }

    private func isChanged(_ shown: Double) -> Bool {
        guard let defaultValue else { return false }
        return abs(shown - defaultValue) > (range.upperBound - range.lowerBound) / 400
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
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, 4)
    }
}

/// Bagian yang bisa dilipat. Membuat panel panjang tetap mudah dipindai.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    var initiallyExpanded = true
    @ViewBuilder let content: () -> Content

    @State private var expanded: Bool?

    private var isExpanded: Bool { expanded ?? initiallyExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    expanded = !isExpanded
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .card()
    }
}

/// Pesan saat area kosong, lengkap dengan tombol tindakan.
struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.accent)
                .padding(.bottom, 2)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: 240)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.prominentPill)
                    .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Garis pegangan untuk mengubah tinggi area. Kursor berubah saat disorot.
struct VerticalResizeHandle: View {
    @Binding var height: CGFloat
    let range: ClosedRange<CGFloat>

    @State private var startHeight: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.background)
            Capsule()
                .fill(hovering ? Theme.accent : Theme.textTertiary.opacity(0.6))
                .frame(width: 44, height: 4)
        }
        .frame(height: 9)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startHeight == nil { startHeight = height }
                    height = min(max((startHeight ?? height) - value.translation.height, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in startHeight = nil }
        )
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
