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

            ValueSlider(
                value: shown,
                range: range,
                step: step,
                origin: defaultValue,
                format: format,
                onChange: { draft = $0 },
                onCommit: { committed in
                    onCommit(committed)
                    draft = nil
                },
                onReset: defaultValue.map { reset in { onCommit(reset); draft = nil } }
            )
        }
    }

    private func isChanged(_ shown: Double) -> Bool {
        guard let defaultValue else { return false }
        return abs(shown - defaultValue) > (range.upperBound - range.lowerBound) / 400
    }
}

/// Slider kustom: area sentuh lebih besar, bagian terisi mulai dari nilai netral, dan klik langsung melompat ke posisi.
/// Tahan Shift saat menyeret untuk penyesuaian halus. Klik dua kali mengembalikan ke nilai default.
struct ValueSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double?
    /// Nilai netral. Bagian terisi berawal dari sini, dan sebuah tanda ditampilkan pada posisinya.
    var origin: Double?
    let format: (Double) -> String
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    var onReset: (() -> Void)?

    @State private var hovering = false
    @State private var dragging = false
    @State private var dragBase: Double?
    /// Nilai terakhir selama seret; dipakai saat commit agar tidak membaca nilai parent yang mungkin belum diperbarui.
    @State private var lastValue: Double?

    private let knob: CGFloat = 14
    private let track: CGFloat = 5
    private let height: CGFloat = 22

    private var span: Double { range.upperBound - range.lowerBound }

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - knob, 1)
            let knobCenter = knob / 2 + CGFloat(fraction(value)) * usable
            let originX = knob / 2 + CGFloat(fraction(origin ?? range.lowerBound)) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.background)
                    .frame(height: track)
                    .overlay(Capsule().stroke(Theme.divider))

                // Bagian terisi: dari nilai netral ke posisi knob.
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(abs(knobCenter - originX), 0), height: track)
                    .offset(x: min(knobCenter, originX))

                if origin != nil {
                    Rectangle()
                        .fill(Theme.textTertiary)
                        .frame(width: 1.5, height: track + 6)
                        .offset(x: originX - 0.75)
                }

                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: dragging ? 5 : 2, y: 1)
                    .frame(width: knob, height: knob)
                    .scaleEffect(dragging ? 1.2 : (hovering ? 1.08 : 1))
                    .offset(x: knobCenter - knob / 2)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: dragging)
                    .animation(.easeOut(duration: 0.12), value: hovering)

                if dragging {
                    Text(format(value))
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.surfaceActive, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize()
                        .offset(x: knobCenter - 20, y: -height)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if dragBase == nil {
                            dragBase = value
                            dragging = true
                        }
                        let base = dragBase ?? value
                        // Klik tanpa geser langsung melompat ke posisi kursor; seret mengikuti jarak geser.
                        let fine = NSEvent.modifierFlags.contains(.shift) ? 0.2 : 1
                        let target: Double
                        if abs(drag.translation.width) < 2 {
                            target = valueAt(x: drag.location.x, usable: usable)
                        } else {
                            target = base + Double(drag.translation.width / usable) * span * fine
                        }
                        lastValue = snapped(target)
                        onChange(snapped(target))
                    }
                    .onEnded { _ in
                        onCommit(lastValue ?? value)
                        lastValue = nil
                        dragBase = nil
                        dragging = false
                    }
            )
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { onReset?() }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            let delta = (step ?? span / 100) * (direction == .increment ? 1 : -1)
            onCommit(snapped(value + delta))
        }
    }

    private func fraction(_ v: Double) -> Double {
        guard span > 0 else { return 0 }
        return min(max((v - range.lowerBound) / span, 0), 1)
    }

    private func valueAt(x: CGFloat, usable: CGFloat) -> Double {
        let f = min(max(Double((x - knob / 2) / usable), 0), 1)
        return range.lowerBound + f * span
    }

    private func snapped(_ v: Double) -> Double {
        let clamped = min(max(v, range.lowerBound), range.upperBound)
        let increment = step ?? span / 200
        guard increment > 0 else { return clamped }
        let stepped = ((clamped - range.lowerBound) / increment).rounded() * increment + range.lowerBound
        return min(max(stepped, range.lowerBound), range.upperBound)
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
