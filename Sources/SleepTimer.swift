import AppKit
import CoreAudio
import UserNotifications

/// What happens once the countdown reaches zero.
enum EndAction: String, CaseIterable, Identifiable {
    case sleepMac, sleepDisplay, pauseOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sleepMac: return "Sleep Mac"
        case .sleepDisplay: return "Sleep display only"
        case .pauseOnly: return "Do nothing but pause"
        }
    }
    var summary: String {
        switch self {
        case .sleepMac: return "Media pauses, then your Mac sleeps."
        case .sleepDisplay: return "Media pauses, then the display sleeps."
        case .pauseOnly: return "Media pauses; the Mac stays awake."
        }
    }
}

/// UserDefaults keys shared by the model and `@AppStorage` views.
enum Keys {
    static let fadeMinutes = "fadeMinutes"
    static let endAction = "endAction"
    static let fadeBrightness = "fadeBrightness"
    static let restoreVolume = "restoreVolume"
    static let lastDuration = "lastDuration"
    static let customMinutes = "customMinutes"
    static let hotKeyCode = "hotKeyCode"
    static let hotKeyModifiers = "hotKeyModifiers"
    static let hotKeyLabel = "hotKeyLabel"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            fadeMinutes: 5, endAction: EndAction.sleepMac.rawValue, fadeBrightness: true,
            restoreVolume: true, lastDuration: 30, customMinutes: 20, hotKeyCode: -1,
            hotKeyModifiers: 0, hotKeyLabel: "",
        ])
    }
}

/// Owns the countdown and the volume/brightness fade, and restores state on cancel, wake or quit.
@MainActor
final class SleepTimerModel: ObservableObject {
    static let shared = SleepTimerModel()

    @Published private(set) var endDate: Date?
    @Published private(set) var totalSeconds: TimeInterval = 0
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var isFading = false
    @Published private(set) var fadeInterrupted = false
    @Published private(set) var deviceNote: String?

    var isRunning: Bool { endDate != nil }
    var progress: Double { totalSeconds > 0 ? remaining / totalSeconds : 0 }
    var endAction: EndAction { EndAction(rawValue: defaults.string(forKey: Keys.endAction) ?? "") ?? .sleepMac }

    private let defaults = UserDefaults.standard
    private var ticker: Timer?
    private var fadeLength: TimeInterval = 300
    private var originalVolume: (device: AudioDeviceID, value: Float)?
    private var originalBrightness: Float?
    private var rampDevice: AudioDeviceID?
    private var rampBase: Float?
    private var rampWindow: TimeInterval = 1
    private var lastSetVolume: Float?
    private var brightnessWindow: TimeInterval = 1
    private var pendingWakeRestore = false
    private var askedForNotifications = false
    private let warningID = "fade-warning"

    private init() {
        Keys.registerDefaults()
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.handleEarlySleep() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            }
        }
    }

    // MARK: - Controls

    func start(minutes: Int) {
        guard minutes > 0 else { return }
        if isRunning { cancel() }
        defaults.set(minutes, forKey: Keys.lastDuration)
        totalSeconds = TimeInterval(minutes * 60)
        // Guard against a duration shorter than the fade window by shrinking the window.
        fadeLength = min(TimeInterval(max(1, defaults.integer(forKey: Keys.fadeMinutes)) * 60), totalSeconds)
        endDate = Date().addingTimeInterval(totalSeconds)
        remaining = totalSeconds
        deviceNote = nil
        if !PowerService.isAccessibilityTrusted { PowerService.requestAccessibility() }
        scheduleWarning()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        tick()
    }

    func startLast() {
        start(minutes: max(1, defaults.integer(forKey: Keys.lastDuration)))
    }

    func addFifteenMinutes() {
        guard let end = endDate else { return }
        endDate = end.addingTimeInterval(900)
        totalSeconds += 900
        remaining = max(0, endDate?.timeIntervalSinceNow ?? 0)
        if isFading {
            if remaining > fadeLength {
                restoreState()
                isFading = false
                fadeInterrupted = false
            } else {
                restartRamp()
            }
        }
        scheduleWarning()
    }

    func cancel() {
        stopTicker()
        restoreState()
        reset()
    }

    func resumeFade() {
        fadeInterrupted = false
        restartRamp()
    }

    /// Called on app termination: never leave the Mac silent or dark.
    func restoreForQuit() {
        stopTicker()
        restoreState()
    }

    // MARK: - Fade engine

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finish(); return }
        guard remaining <= fadeLength else { return }
        if !isFading { beginFade() } else if !fadeInterrupted { stepFade() }
    }

    private func beginFade() {
        isFading = true
        if let device = AudioService.defaultOutputDevice(), let v = AudioService.volume(device) {
            originalVolume = (device, v)
        }
        if defaults.bool(forKey: Keys.fadeBrightness), let b = BrightnessService.brightness() {
            originalBrightness = b
            brightnessWindow = remaining
        }
        restartRamp()
        stepFade()
    }

    /// (Re)starts the volume ramp from the current device's present level.
    private func restartRamp() {
        rampDevice = AudioService.defaultOutputDevice()
        rampBase = rampDevice.flatMap { AudioService.volume($0) }
        rampWindow = max(1, remaining)
        lastSetVolume = rampBase
        deviceNote = (rampDevice != nil && rampBase == nil)
            ? "This output device has no volume control, so it can't be faded." : nil
    }

    private func stepFade() {
        let device = AudioService.defaultOutputDevice()
        if device != rampDevice {
            restartRamp() // Output device changed mid-fade.
        } else if let device, let last = lastSetVolume, let current = AudioService.volume(device),
                  abs(current - last) > 0.03 {
            fadeInterrupted = true // The user adjusted the volume; respect it.
            return
        }
        if let device = rampDevice, let base = rampBase {
            let target = base * Float(min(max(remaining / rampWindow, 0), 1))
            AudioService.setVolume(target, on: device)
            lastSetVolume = AudioService.volume(device) ?? target
        }
        if let b = originalBrightness {
            BrightnessService.setBrightness(b * Float(min(max(remaining / brightnessWindow, 0), 1)))
        }
    }

    private func finish() {
        stopTicker()
        if !fadeInterrupted, let device = rampDevice, rampBase != nil {
            AudioService.setVolume(0, on: device)
        }
        PowerService.playPause()
        let action = endAction
        reset()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            switch action {
            case .sleepMac:
                self.pendingWakeRestore = true
                PowerService.sleepSystem()
            case .sleepDisplay:
                self.pendingWakeRestore = true
                PowerService.sleepDisplay()
            case .pauseOnly:
                self.restoreAfterSession()
            }
        }
    }

    // MARK: - State restoration

    private func restoreState() {
        if let original = originalVolume { AudioService.setVolume(original.value, on: original.device) }
        if let b = originalBrightness { BrightnessService.setBrightness(b) }
        originalVolume = nil
        originalBrightness = nil
    }

    /// After the session ends: brightness always comes back, volume only if the user wants it.
    private func restoreAfterSession() {
        if !defaults.bool(forKey: Keys.restoreVolume) { originalVolume = nil }
        restoreState()
    }

    private func handleEarlySleep() {
        if isRunning { cancel() } // Mac slept early or the lid closed.
    }

    private func handleWake() {
        guard pendingWakeRestore else { return }
        pendingWakeRestore = false
        restoreAfterSession()
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [warningID])
    }

    private func reset() {
        endDate = nil
        remaining = 0
        totalSeconds = 0
        isFading = false
        fadeInterrupted = false
        rampDevice = nil
        rampBase = nil
        lastSetVolume = nil
    }

    // MARK: - Notifications

    /// Posts a heads-up one minute before the fade begins.
    private func scheduleWarning() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [warningID])
        let delay = remaining - fadeLength - 60
        guard delay > 1 else { return }
        let id = warningID
        let schedule = {
            let content = UNMutableNotificationContent()
            content.title = "FadeToSleep"
            content.body = "Your Mac starts fading out in one minute."
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        if askedForNotifications {
            schedule()
        } else {
            askedForNotifications = true
            center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                if granted { schedule() }
            }
        }
    }
}
