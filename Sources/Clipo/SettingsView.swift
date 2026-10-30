import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences = Preferences.shared
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var canAutoPaste = AXIsProcessTrusted()

    private let permissionTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Picker("Открыть историю", selection: $preferences.hotKey) {
                    ForEach(HotKeyPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Сочетание клавиш")
            } footer: {
                Text(preferences.hotKey.note)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Хранить записей", selection: $preferences.historyLimit) {
                    ForEach(Preferences.historyLimits, id: \.self) { limit in
                        Text("\(limit)").tag(limit)
                    }
                }
            } header: {
                Text("История")
            } footer: {
                Text("Закреплённые записи не считаются и не удаляются.")
                    .foregroundStyle(.secondary)
            }

            Section("Система") {
                Toggle("Запускать при входе", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                LabeledContent("Автовставка") {
                    if canAutoPaste {
                        Label("Разрешена", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Разрешить…") {
                            PanelController.requestAccessibility()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section {
                LabeledContent("Версия", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(permissionTimer) { _ in canAutoPaste = AXIsProcessTrusted() }
    }
}
