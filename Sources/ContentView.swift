import SwiftUI

/// The menu bar popover: presets when idle, countdown ring and controls while running.
struct ContentView: View {
    @EnvironmentObject private var model: SleepTimerModel
    @AppStorage(Keys.customMinutes) private var customMinutes = 20
    @AppStorage(Keys.endAction) private var endActionRaw = EndAction.sleepMac.rawValue
    @State private var trusted = PowerService.isAccessibilityTrusted

    private let presets = [15, 30, 45, 60, 90]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("FadeToSleep").font(.headline)
            if model.isRunning { running } else { idle }

            if let note = model.deviceNote {
                Label(note, systemImage: "speaker.slash").font(.caption).foregroundStyle(.secondary)
            }
            if model.fadeInterrupted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("You changed the volume, so fading is paused.").font(.caption)
                    Button("Resume Fade") { model.resumeFade() }
                }
            }
            if !trusted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Grant Accessibility access so FadeToSleep can pause media at the end.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Open Accessibility Settings…") { PowerService.openAccessibilitySettings() }
                        .controlSize(.small)
                }
            }

            Divider()
            HStack {
                SettingsLink { Text("Settings…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Spacer()
                Button("Support / Donate ❤️") { Support.open() }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { trusted = PowerService.isAccessibilityTrusted }
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fade out and sleep in…").foregroundStyle(.secondary)
            HStack {
                ForEach(presets, id: \.self) { minutes in
                    Button("\(minutes)m") { model.start(minutes: minutes) }
                        .frame(maxWidth: .infinity)
                }
            }
            HStack {
                TextField("Minutes", value: $customMinutes, format: .number)
                    .frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                Stepper("min", value: $customMinutes, in: 1...600)
                Spacer()
                Button("Start") { model.start(minutes: min(max(customMinutes, 1), 600)) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var running: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(Color.indigo, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: model.progress)
                VStack(spacing: 2) {
                    Text(Self.format(model.remaining))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if model.isFading { Text("Fading…").font(.caption).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 160, height: 160)
            .frame(maxWidth: .infinity)

            HStack {
                Button("Add 15 Minutes") { model.addFifteenMinutes() }
                Button("Cancel", role: .cancel) { model.cancel() }
            }
            Text("At the end: \((EndAction(rawValue: endActionRaw) ?? .sleepMac).summary)")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    static func format(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }
}
