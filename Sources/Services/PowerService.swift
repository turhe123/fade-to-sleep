import AppKit
import IOKit
import IOKit.pwr_mgt

/// Ends a session: posts the play/pause media key and sleeps the Mac or display.
enum PowerService {
    /// Sends a system-defined play/pause media key press (requires Accessibility).
    static func playPause() {
        let keyCode = 16 // NX_KEYTYPE_PLAY
        for down in [true, false] {
            let state = down ? 0xA : 0xB
            guard let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
                data1: (keyCode << 16) | (state << 8), data2: -1) else { continue }
            event.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    static func sleepSystem() {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard port != 0 else { return }
        IOPMSleepSystem(port)
        IOServiceClose(port)
    }

    /// Equivalent of `pmset displaysleepnow`: asks the display wrangler to go idle.
    static func sleepDisplay() {
        let wrangler = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler")
        guard wrangler != 0 else { return }
        IORegistryEntrySetCFProperty(wrangler, "IORequestIdle" as CFString, kCFBooleanTrue)
        IOObjectRelease(wrangler)
    }

    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
