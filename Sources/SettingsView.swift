import SwiftUI
import ServiceManagement

/// Preferences: fade length, end action, brightness, volume restore, login item and hotkey.
struct SettingsView: View {
    @AppStorage(Keys.fadeMinutes) private var fadeMinutes = 5
    @AppStorage(Keys.endAction) private var endAction = EndAction.sleepMac.rawValue
    @AppStorage(Keys.fadeBrightness) private var fadeBrightness = true
    @AppStorage(Keys.restoreVolume) private var restoreVolume = true
    @AppStorage(Keys.hotKeyCode) private var hotKeyCode = -1
    @AppStorage(Keys.hotKeyModifiers) private var hotKeyModifiers = 0
    @AppStorage(Keys.hotKeyLabel) private var hotKeyLabel = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Form {
            Stepper("Fade length: \(fadeMinutes) min", value: $fadeMinutes, in: 1...60)
            Picker("When the timer ends", selection: $endAction) {
                ForEach(EndAction.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Fade built-in display brightness", isOn: $fadeBrightness)
            Toggle("Restore volume after wake", isOn: $restoreVolume)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }

            LabeledContent("Start last duration") {
                HStack {
                    Button(recording ? "Press keys…" : (hotKeyLabel.isEmpty ? "Record Shortcut" : hotKeyLabel)) {
                        recording ? stopRecording() : startRecording()
                    }
                    if hotKeyCode >= 0 {
                        Button("Clear") {
                            hotKeyCode = -1; hotKeyLabel = ""
                            HotKeyService.shared.unregister()
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Support / Donate ❤️") { Support.open() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .onDisappear { stopRecording() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
        }
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 53 { stopRecording(); return nil } // Escape cancels.
            guard !flags.isEmpty else { return nil }
            hotKeyCode = Int(event.keyCode)
            hotKeyModifiers = HotKeyService.carbonModifiers(flags)
            hotKeyLabel = HotKeyService.label(for: flags, characters: event.charactersIgnoringModifiers ?? "?")
            HotKeyService.shared.register(keyCode: hotKeyCode, modifiers: hotKeyModifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
