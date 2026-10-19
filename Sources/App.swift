import SwiftUI

/// Restores volume/brightness on quit and wires up the global hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let defaults = UserDefaults.standard
        HotKeyService.shared.onPress = { Task { @MainActor in SleepTimerModel.shared.startLast() } }
        HotKeyService.shared.register(keyCode: defaults.integer(forKey: Keys.hotKeyCode),
                                      modifiers: defaults.integer(forKey: Keys.hotKeyModifiers))
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { SleepTimerModel.shared.restoreForQuit() }
    }
}

/// App entry point: a window-style menu bar extra plus a Settings scene.
@main
struct FadeToSleepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = SleepTimerModel.shared

    var body: some Scene {
        MenuBarExtra {
            ContentView().environmentObject(model)
        } label: {
            if model.isRunning {
                Label("\(Int((model.remaining / 60).rounded(.up)))m", systemImage: "moon.zzz.fill")
                    .labelStyle(.titleAndIcon)
            } else {
                Image(systemName: "moon.zzz")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

/// Opens the donation page.
enum Support {
    static func open() {
        if let url = URL(string: "https://ko-fi.com/leodavidai") { NSWorkspace.shared.open(url) }
    }
}
