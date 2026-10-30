import SwiftUI

private let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
}()

func relativeTime(_ date: Date) -> String {
    relativeFormatter.localizedString(for: date, relativeTo: Date())
}

/// Spotlight-style window with three layouts: list + preview, plain list, and Windows-like cards.
struct HistoryView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var state: PanelState
    let onPaste: (ClipItem, _ plainText: Bool) -> Void

    @FocusState private var searchFocused: Bool
    @AppStorage("listWidth") private var listWidth = SplitHandle.defaultWidth

    private var items: [ClipItem] { store.visible(matching: state.query) }

    private var selectedItem: ClipItem? {
        items.indices.contains(state.selection) ? items[state.selection] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            grabber
            searchBar
            Divider().opacity(0.6)
            if items.isEmpty {
                emptyState
            } else if state.layout == .split {
                HStack(spacing: 0) {
                    list
                        .frame(width: listWidth)
                    SplitHandle(width: $listWidth)
                    if let selectedItem {
                        PreviewPane(item: selectedItem, store: store, onPaste: onPaste)
                    }
                }
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .onAppear { searchFocused = true }
        .onChange(of: state.openCount) { searchFocused = true }
        .onChange(of: state.query) { state.selection = 0 }
    }

    /// Handle for moving the window around the screen; double-click puts it back in the center.
    private var grabber: some View {
        ZStack {
            WindowDragArea()
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 38, height: 5)
                .allowsHitTesting(false)
        }
        .frame(height: 16)
        .help("Перетащите, чтобы переместить окно. Двойной клик — в центр")
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(state.layout == .split ? "Поиск в буфере обмена" : "Поиск", text: $state.query)
                .textFieldStyle(.plain)
                .font(.system(size: 21, weight: .regular))
                .focused($searchFocused)
            if store.hasUnpinned {
                ClearButton(isCompact: state.layout != .split) { store.clearUnpinned() }
            }
            LayoutSwitcher(layout: $state.layout)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .padding(.bottom, 4)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: state.layout == .cards ? 8 : 2) {
                    let pinnedCount = items.prefix { $0.pinned }.count
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index == 0 && pinnedCount > 0 {
                            sectionTitle("Закреплённые")
                        } else if index == pinnedCount && pinnedCount > 0 {
                            sectionTitle("Недавние")
                        }
                        row(item, at: index)
                            .id(item.id)
                    }
                }
                .padding(state.layout == .cards ? 12 : 8)
            }
            .scrollIndicators(.never)
            .onChange(of: state.selection) { _, selection in
                guard items.indices.contains(selection) else { return }
                proxy.scrollTo(items[selection].id)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: ClipItem, at index: Int) -> some View {
        let isSelected = index == state.selection
        switch state.layout {
        case .split:
            // With a preview, a click selects and a double click pastes.
            ClipRow(item: item, index: index, isSelected: isSelected, store: store, showsDetails: false)
                .onTapGesture { state.selection = index }
                .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(item, false) })
        case .list:
            ClipRow(item: item, index: index, isSelected: isSelected, store: store, showsDetails: true)
                .onTapGesture { onPaste(item, false) }
        case .cards:
            ClipCard(item: item, index: index, isSelected: isSelected, store: store)
                .onTapGesture { onPaste(item, false) }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: state.query.isEmpty ? "list.clipboard" : "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(state.query.isEmpty ? "Здесь пока пусто" : "Ничего не найдено")
                .font(.headline)
            Text(state.query.isEmpty
                 ? "Скопируйте что-нибудь с помощью ⌘C — и оно появится здесь."
                 : "Попробуйте другой запрос.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Clear all" that asks for a second click, so history isn't wiped by accident.
struct ClearButton: View {
    let isCompact: Bool
    let action: () -> Void

    @State private var isConfirming = false

    var body: some View {
        Button {
            if isConfirming {
                isConfirming = false
                action()
            } else {
                isConfirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { isConfirming = false }
            }
        } label: {
            if isCompact {
                Image(systemName: isConfirming ? "trash.fill" : "trash")
            } else {
                Text(isConfirming ? "Точно очистить?" : "Очистить всё")
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .tint(isConfirming ? .red : nil)
        .foregroundStyle(isConfirming ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
        .help(isConfirming ? "Нажмите ещё раз, чтобы удалить всё, кроме закреплённого" : "Очистить всё")
        .animation(.snappy(duration: 0.15), value: isConfirming)
    }
}

/// Three-way layout toggle. Plain SwiftUI buttons so every click lands.
struct LayoutSwitcher: View {
    @Binding var layout: PanelLayout

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PanelLayout.allCases) { option in
                let isOn = option == layout
                Button { layout = option } label: {
                    Image(systemName: option.symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isOn ? Color.white : Color.secondary)
                        .frame(width: 28, height: 22)
                        .background(isOn ? Color.accentColor : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(option.title) (⌘L)")
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .animation(.snappy(duration: 0.15), value: layout)
    }
}

/// Empty space that moves the window when dragged.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? FloatingPanel else { return }
            if event.clickCount == 2 {
                panel.onResetPosition?()
            } else {
                panel.performDrag(with: event)
                panel.onUserMoved?()
            }
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

/// The draggable line between the list and the preview. Double-click resets the width.
struct SplitHandle: View {
    static let defaultWidth = 290.0
    private static let range = 200.0...480.0

    @Binding var width: Double
    @State private var startWidth: Double?
    @State private var isHovered = false

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovered || startWidth != nil ? 0.25 : 0.1))
            .frame(width: 1)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                hovering ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(max(start + value.translation.width, Self.range.lowerBound), Self.range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .onTapGesture(count: 2) { width = Self.defaultWidth }
    }
}

struct ClipRow: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let store: ClipboardStore
    /// Plain list mode: second line with source and time, hover actions.
    let showsDetails: Bool

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            ClipIcon(item: item, store: store)
                .frame(width: showsDetails ? 26 : 22, height: showsDetails ? 26 : 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if showsDetails {
                    Text([store.appName(for: item.appBundleID), relativeTime(item.date)].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsDetails && isHovered {
                ItemActions(item: item, store: store)
            } else {
                if item.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : Color.accentColor)
                }
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
                }
            }
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 10)
        .frame(height: showsDetails ? 46 : 36)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(isHovered ? 0.07 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
    }
}

/// Windows-style card with a multi-line preview.
struct ClipCard: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool
    let store: ClipboardStore

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            HStack(spacing: 6) {
                ClipIcon(item: item, store: store)
                    .frame(width: 14, height: 14)
                Text(relativeTime(item.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovered {
                    ItemActions(item: item, store: store)
                } else {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.accentColor)
                    }
                    if index < 9 {
                        Text("⌘\(index + 1)")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 20)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(isHovered ? 0.09 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : .clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            Text(String(item.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400)))
                .font(.system(size: 13))
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        case .file:
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePaths[0]))
                    .resizable()
                    .frame(width: 32, height: 32)
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        }
    }
}

/// App icon for text, thumbnail for images, Finder icon for files.
struct ClipIcon: View {
    let item: ClipItem
    let store: ClipboardStore

    var body: some View {
        switch item.kind {
        case .image:
            if let image = store.image(for: item) {
                // Fill the icon's square and crop, instead of spilling outside it.
                Color.clear
                    .overlay {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePaths[0]))
                .resizable()
        case .text:
            if let appIcon = store.appIcon(for: item.appBundleID) {
                Image(nsImage: appIcon).resizable()
            } else {
                Image(systemName: "text.alignleft")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Pin and delete buttons shown on hover.
struct ItemActions: View {
    let item: ClipItem
    let store: ClipboardStore

    var body: some View {
        HStack(spacing: 4) {
            button(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Открепить" : "Закрепить") {
                store.togglePin(item)
            }
            button("trash", help: "Удалить") { store.delete(item) }
        }
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 20)
                .background(Color.primary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct PreviewPane: View {
    let item: ClipItem
    let store: ClipboardStore
    let onPaste: (ClipItem, _ plainText: Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.6)
            info
            actions
        }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.text)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
            }
        case .image:
            if let image = store.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(18)
            }
        case .file:
            VStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.filePaths[0]))
                    .resizable()
                    .frame(width: 72, height: 72)
                ForEach(item.filePaths.prefix(5), id: \.self) { path in
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                }
                if item.filePaths.count > 5 {
                    Text("и ещё \(item.filePaths.count - 5)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(18)
        }
    }

    private var info: some View {
        VStack(spacing: 6) {
            if let app = store.appName(for: item.appBundleID) {
                infoRow("Источник", app)
            }
            infoRow("Скопировано", relativeTime(item.date))
            infoRow(item.detailLabel, item.detail(image: store.image(for: item)))
            if item.kind == .text {
                infoRow("Формат", item.hasFormatting ? "С форматированием" : "Простой текст")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            Spacer()
            Text(value).lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { store.togglePin(item) } label: {
                Image(systemName: item.pinned ? "pin.slash" : "pin")
            }
            .help(item.pinned ? "Открепить (⌘P)" : "Закрепить (⌘P)")
            Button { store.delete(item) } label: {
                Image(systemName: "trash")
            }
            .help("Удалить (⌘⌫)")
            Spacer()
            if item.hasFormatting {
                Button("Как текст") { onPaste(item, true) }
                    .help("Вставить без форматирования (⇧↩)")
            }
            Button { onPaste(item, false) } label: {
                Text("Вставить  ↩")
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
        }
        .buttonStyle(.glass)
        .padding(14)
    }
}

extension ClipItem {
    /// One-line label for the list.
    var title: String {
        switch kind {
        case .text:
            let line = text.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return line.trimmingCharacters(in: .whitespaces)
        case .image:
            return "Изображение"
        case .file:
            let name = (filePaths[0] as NSString).lastPathComponent
            return filePaths.count > 1 ? "\(name) и ещё \(filePaths.count - 1)" : name
        }
    }

    var detailLabel: String {
        switch kind {
        case .text: "Символов"
        case .image: "Размер"
        case .file: "Файлов"
        }
    }

    func detail(image: NSImage?) -> String {
        switch kind {
        case .text:
            return "\(text.count)"
        case .image:
            guard let rep = image?.representations.first else { return "—" }
            return "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        case .file:
            return "\(filePaths.count)"
        }
    }
}
