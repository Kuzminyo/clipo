import AppKit
import Carbon.HIToolbox

enum HotKeyPreset: String, CaseIterable, Identifiable {
    case controlV, controlOptionV, commandShiftV, optionV

    var id: Self { self }

    var title: String {
        switch self {
        case .controlV: "⌃V"
        case .controlOptionV: "⌃⌥V"
        case .commandShiftV: "⇧⌘V"
        case .optionV: "⌥V"
        }
    }

    var carbonModifiers: Int {
        switch self {
        case .controlV: controlKey
        case .controlOptionV: controlKey | optionKey
        case .commandShiftV: cmdKey | shiftKey
        case .optionV: optionKey
        }
    }

    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .controlV: [.control]
        case .controlOptionV: [.control, .option]
        case .commandShiftV: [.command, .shift]
        case .optionV: [.option]
        }
    }

    /// What the shortcut takes away from other apps.
    var note: String {
        switch self {
        case .controlV: "В Терминале и vim ⌃V перестанет работать."
        case .controlOptionV: "Ни с чем не пересекается."
        case .commandShiftV: "В некоторых приложениях это «Вставить без форматирования»."
        case .optionV: "Перестанет печататься символ √ (≈ в русской раскладке)."
        }
    }
}

final class Preferences: ObservableObject {
    static let shared = Preferences()
    static let historyLimits = [25, 50, 100, 200, 500]

    @Published var hotKey: HotKeyPreset {
        didSet { UserDefaults.standard.set(hotKey.rawValue, forKey: "hotKey") }
    }

    @Published var historyLimit: Int {
        didSet { UserDefaults.standard.set(historyLimit, forKey: "historyLimit") }
    }

    private init() {
        let defaults = UserDefaults.standard
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: "hotKey") ?? "") ?? .controlV
        let limit = defaults.integer(forKey: "historyLimit")
        historyLimit = Self.historyLimits.contains(limit) ? limit : 50
    }
}
