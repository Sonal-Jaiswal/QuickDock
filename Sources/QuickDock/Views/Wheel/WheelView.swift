import SwiftUI
import QuickDockCore

struct WheelView: View {
    @ObservedObject var model: WheelViewModel
    let clipboardOnLeft: () -> Bool
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        let showClipboard = preferences.showClipboardInWheel
        let onLeft = clipboardOnLeft()
        HStack(spacing: WheelController.gap) {
            if showClipboard && onLeft { ClipboardPanel(model: model) }
            WheelRing(model: model)
                .frame(width: WheelController.wheelDiameter, height: WheelController.wheelDiameter)
            if showClipboard && !onLeft { ClipboardPanel(model: model) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Ring

private struct WheelRing: View {
    @ObservedObject var model: WheelViewModel
    @Environment(\.colorScheme) private var colorScheme

    private let outer: CGFloat = WheelController.wheelDiameter / 2 - 6
    private let inner: CGFloat = 84
    private var iconRadius: CGFloat { (outer + inner) / 2 }

    var body: some View {
        let count = model.items.count
        ZStack {
            GlassSurface(cornerRadius: WheelController.wheelDiameter / 2)
            Circle().strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.35), lineWidth: 1)

            if count > 0 {
                ForEach(0..<count, id: \.self) { index in
                    let slice = WheelSlice(index: index, count: count, inner: inner + 4, outer: outer - 4)
                    slice
                        .fill(model.highlighted == index ? Color.accentColor.opacity(0.38) : Color.primary.opacity(0.001))
                        .overlay(slice.stroke(model.highlighted == index ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.07),
                                              lineWidth: model.highlighted == index ? 1.5 : 1))
                        .contentShape(slice)
                        .onTapGesture { model.controller?.open(index: index) }
                        .onHover { inside in if inside { model.highlighted = index } }
                        .accessibilityElement()
                        .accessibilityLabel("\(model.items[index].name), slot \(index + 1)")
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { model.controller?.open(index: index) }
                }
                ForEach(0..<count, id: \.self) { index in
                    slotContent(index: index, count: count)
                }
            }

            hub
        }
        .animation(.easeOut(duration: 0.12), value: model.highlighted)
    }

    private func position(angle: Double, radius: CGFloat) -> CGPoint {
        let c = WheelController.wheelDiameter / 2
        return CGPoint(x: c + radius * CGFloat(sin(angle)), y: c - radius * CGFloat(cos(angle)))
    }

    @ViewBuilder
    private func slotContent(index: Int, count: Int) -> some View {
        let item = model.items[index]
        let angle = WheelLayout.centerAngle(of: index, count: count)
        let isHighlighted = model.highlighted == index
        let size: CGFloat = count > 10 ? 44 : (count > 8 ? 50 : 58)
        VStack(spacing: 3) {
            ItemIconView(item: item, size: size)
                .scaleEffect(isHighlighted ? 1.14 : 1)
                .shadow(color: .black.opacity(isHighlighted ? 0.35 : 0), radius: 8, y: 3)
            Circle()
                .fill(model.isRunning(item) ? Color.primary.opacity(0.75) : .clear)
                .frame(width: 4, height: 4)
        }
        .overlay(alignment: .topLeading) {
            if index < 9 {
                Text("\(index + 1)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .offset(x: -6, y: -4)
            }
        }
        .allowsHitTesting(false)
        .position(position(angle: angle, radius: iconRadius))
    }

    private var hub: some View {
        ZStack {
            Circle()
                .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.white.opacity(0.45))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 1))
            VStack(spacing: 4) {
                if let message = model.hubMessage {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 22)).foregroundStyle(.green)
                    Text(message).font(.system(size: 11, weight: .medium)).multilineTextAlignment(.center)
                } else if let item = model.highlightedItem {
                    Text(item.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    Text(model.isRunning(item) ? "Running · switch" : item.kind.displayName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else if model.items.isEmpty {
                    Image(systemName: "star").font(.system(size: 18)).foregroundStyle(.secondary)
                    Text("Add favorites to fill your wheel")
                        .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else {
                    Image(systemName: "circle.grid.cross").font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
                    Text("Point and release").font(.system(size: 11, weight: .medium))
                    Text("or click · 1–\(min(model.items.count, 9))").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: inner * 2 - 8, height: inner * 2 - 8)
        .contentShape(Circle())
        .onTapGesture { model.controller?.hide() }
        .accessibilityLabel(model.highlightedItem?.name ?? "Quick Wheel")
    }
}

/// An annular sector; angles are measured from the top, clockwise.
struct WheelSlice: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let width = 2 * Double.pi / Double(count)
        let gap = count > 1 ? 0.012 : 0
        let start = WheelLayout.centerAngle(of: index, count: count) - width / 2 + gap
        let end = start + width - gap * 2
        func point(_ angle: Double, _ radius: CGFloat) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(sin(angle)), y: center.y - radius * CGFloat(cos(angle)))
        }
        let steps = 32
        var path = Path()
        path.move(to: point(start, outer))
        for step in 1...steps { path.addLine(to: point(start + (end - start) * Double(step) / Double(steps), outer)) }
        for step in (0...steps).reversed() { path.addLine(to: point(start + (end - start) * Double(step) / Double(steps), inner)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Clipboard

private struct ClipboardPanel: View {
    @ObservedObject var model: WheelViewModel
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label("Clipboard", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if preferences.clipboardHistoryEnabled && !clipboard.history.entries.isEmpty {
                    Button { clipboard.clear() } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .focusable(false)
                        .help("Clear history (pinned items stay)")
                        .accessibilityLabel("Clear clipboard history")
                }
                Button { model.controller?.openSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .focusable(false)
                    .help("Wheel & Clipboard settings")
                    .accessibilityLabel("Wheel and clipboard settings")
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            Divider().opacity(0.6)
            content
        }
        .frame(width: WheelController.clipboardWidth, height: 400)
        .background(GlassSurface(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    @ViewBuilder
    private var content: some View {
        if !preferences.clipboardHistoryEnabled {
            VStack(spacing: 10) {
                Image(systemName: "lock.shield").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
                Text("Clipboard history is off").font(.system(size: 13, weight: .semibold))
                Text("Keep recent copied text here. It stays on this Mac, and copies from password managers are never saved. macOS may ask you to allow access once.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Turn On Clipboard History") { preferences.clipboardHistoryEnabled = true }
                    .controlSize(.small)
                    .focusable(false)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if clipboard.history.entries.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 24, weight: .light)).foregroundStyle(.secondary)
                Text("Copy some text and it will appear here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(clipboard.history.ordered.prefix(40)) { entry in
                        ClipboardRow(entry: entry) { model.controller?.copyClipboardEntry(entry) }
                    }
                }
                .padding(8)
            }
            Divider().opacity(0.6)
            Text("Click to copy, then paste with ⌘V")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).frame(height: 26)
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let copy: () -> Void
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @State private var isHovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.preview)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    if entry.isPinned { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text([entry.sourceApp, Self.relative.localizedString(for: entry.copiedAt, relativeTo: Date())]
                        .compactMap { $0 }.joined(separator: " · "))
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            if isHovered {
                VStack(spacing: 6) {
                    Button { clipboard.togglePin(entry.id) } label: { Image(systemName: entry.isPinned ? "pin.slash" : "pin") }
                        .help(entry.isPinned ? "Unpin" : "Pin").accessibilityLabel(entry.isPinned ? "Unpin" : "Pin")
                    Button { clipboard.remove(entry.id) } label: { Image(systemName: "xmark") }
                        .help("Remove").accessibilityLabel("Remove")
                }
                .buttonStyle(.plain)
                .focusable(false)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isHovered ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
        .onTapGesture(perform: copy)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Copies this text to the clipboard")
    }
}
