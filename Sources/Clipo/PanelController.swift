import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import SwiftUI

enum PanelLayout: String, CaseIterable, Identifiable {
    case split, list, cards

    var id: Self { self }

    var width: CGFloat {
        switch self {
        case .split: 720
        case .list: 460
        case .cards: 420
        }
    }

    var title: String {
        switch self {
        case .split: "Список и превью"
        case .list: "Список"
        case .cards: "Карточки"
        }
    }

    var symbol: String {
        switch self {
        case .split: "sidebar.left"
        case .list: "list.bullet"
        case .cards: "rectangle.grid.1x2"
        }
    }

    var next: PanelLayout {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

final class PanelState: ObservableObject {
    @Published var query = ""
    @Published var selection = 0
    /// Bumped every time the panel opens so the view can refocus the search field.
    @Published var openCount = 0
    @Published var layout = PanelLayout(rawValue: UserDefaults.standard.string(forKey: "layout") ?? "") ?? .split {
        didSet { UserDefaults.standard.set(layout.rawValue, forKey: "layout") }
    }
}

/// A borderless panel that takes keyboard focus without activating Clipo,
/// so the app you were typing in stays frontmost and receives the paste.
final class FloatingPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onUserMoved: (() -> Void)?
    var onResetPosition: (() -> Void)?

    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // the glass draws its own edge; a window shadow adds a square frame
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

final class PanelController {
    private static let height: CGFloat = 460
    private static let originKey = "panelOrigin"

    private let store: ClipboardStore
    private let state = PanelState()
    private let panel: FloatingPanel
    private var keyMonitor: Any?
    private var outsideClickMonitor: Any?
    private var layoutObserver: AnyCancellable?
    var onOpenSettings: (() -> Void)?

    init(store: ClipboardStore) {
        self.store = store
        let size = NSSize(width: state.layout.width, height: Self.height)
        panel = FloatingPanel(size: size)

        let hosting = NSHostingView(rootView: HistoryView(store: store, state: state) { [weak self] item, plainText in
            self?.paste(item, plainText: plainText)
        })
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting

        panel.onResignKey = { [weak self] in
            DispatchQueue.main.async { self?.hide() }
        }
        panel.onUserMoved = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: Self.originKey)
        }
        panel.onResetPosition = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.removeObject(forKey: Self.originKey)
            positionPanel()
        }
        // @Published fires before the value changes; resize on the next turn so SwiftUI
        // has already applied the new layout, otherwise the old one stays drawn.
        layoutObserver = state.$layout.dropFirst().receive(on: RunLoop.main).sink { [weak self] layout in
            self?.resize(for: layout)
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        state.query = ""
        state.selection = 0
        positionPanel()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        state.openCount += 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        // A click in another app or on the desktop closes the panel, even if it kept key status.
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] _ in
                // Clipo is never the active app, so clicks on the panel itself can arrive here too.
                guard let self, !panel.frame.contains(NSEvent.mouseLocation) else { return }
                hide()
            }
        }
    }

    func hide() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    /// Changes width around the current center so the window doesn't jump.
    private func resize(for layout: PanelLayout) {
        var frame = panel.frame
        frame.origin.x += (frame.width - layout.width) / 2
        frame.size.width = layout.width
        panel.setFrame(frame, display: true)
    }

    // MARK: - Keyboard

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow else { return event }
        let items = store.visible(matching: state.query)
        let selected = items.indices.contains(state.selection) ? items[state.selection] : nil
        let command = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)

        switch Int(event.keyCode) {
        case kVK_Escape:
            hide()
        case kVK_DownArrow:
            state.selection = min(state.selection + 1, max(items.count - 1, 0))
        case kVK_UpArrow:
            state.selection = max(state.selection - 1, 0)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let selected { paste(selected, plainText: shift) }
        case kVK_Delete where command:
            if let selected {
                store.delete(selected)
                state.selection = min(state.selection, max(items.count - 2, 0))
            }
        case kVK_ANSI_P where command:
            if let selected { store.togglePin(selected) }
        case kVK_ANSI_L where command:
            state.layout = state.layout.next
        case kVK_ANSI_W where command:
            hide()
        case kVK_ANSI_Comma where command:
            onOpenSettings?()
        default:
            if command, let digit = Int(event.charactersIgnoringModifiers ?? ""),
               (1...9).contains(digit), items.indices.contains(digit - 1) {
                paste(items[digit - 1])
                return nil
            }
            return event
        }
        return nil
    }

    // MARK: - Paste

    private func paste(_ item: ClipItem, plainText: Bool = false) {
        store.copy(item, plainText: plainText)
        hide()
        guard AXIsProcessTrusted() else {
            Self.requestAccessibility()
            return
        }
        // Give the previous app a moment to get keyboard focus back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { Self.sendCommandV() }
    }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func sendCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Positioning

    /// Opens where the user last dragged it, otherwise centered in the upper part of the screen like Spotlight.
    private func positionPanel() {
        let size = panel.frame.size
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let frame = NSRect(origin: NSPointFromString(saved), size: size)
            if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) {
                let bounds = screen.visibleFrame
                let origin = NSPoint(
                    x: min(max(frame.minX, bounds.minX), bounds.maxX - size.width),
                    y: min(max(frame.minY, bounds.minY), bounds.maxY - size.height)
                )
                panel.setFrameOrigin(origin)
                return
            }
        }

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let bounds = screen.visibleFrame
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: max(bounds.minY + 8, bounds.maxY - bounds.height * 0.18 - size.height)
        )
        panel.setFrameOrigin(origin)
    }
}
