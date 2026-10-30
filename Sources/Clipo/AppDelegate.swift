import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = ClipboardStore()
    private let preferences = Preferences.shared
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var observers: Set<AnyCancellable> = []
    private let openItem = NSMenuItem(title: "Открыть историю", action: #selector(openPanel), keyEquivalent: "v")
    private let loginItem = NSMenuItem(title: "Запускать при входе", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let accessItem = NSMenuItem(title: "Разрешить автовставку…", action: #selector(openAccessibility), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController(store: store)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        store.start()
        setUpStatusItem()

        preferences.$hotKey
            .sink { [weak self] preset in self?.registerHotKey(preset) }
            .store(in: &observers)
        preferences.$historyLimit
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.store.trim() }
            .store(in: &observers)

        if CommandLine.arguments.contains("--show") { panel.show() }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    /// Opening Clipo again (Finder, Launchpad, Spotlight) shows the history window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.show()
        return false
    }

    private func registerHotKey(_ preset: HotKeyPreset) {
        hotKey = nil
        hotKey = HotKey(keyCode: kVK_ANSI_V, modifiers: preset.carbonModifiers) { [weak self] in
            self?.panel.toggle()
        }
    }

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Clipo")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Очистить историю…", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(loginItem)
        menu.addItem(accessItem)
        menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти из Clipo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        openItem.keyEquivalentModifierMask = preferences.hotKey.menuModifiers
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        accessItem.isHidden = AXIsProcessTrusted()
    }

    @objc private func openPanel() {
        // Let the menu finish closing before the panel takes focus.
        DispatchQueue.main.async { self.panel.show() }
    }

    @objc private func clearHistory() {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Очистить историю?"
        alert.informativeText = "Все записи, кроме закреплённых, будут удалены."
        alert.addButton(withTitle: "Очистить")
        alert.addButton(withTitle: "Отмена")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc private func openSettings() {
        panel.hide()
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Настройки Clipo"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось изменить автозапуск"
            alert.runModal()
        }
    }

    @objc private func openAccessibility() {
        PanelController.requestAccessibility()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
