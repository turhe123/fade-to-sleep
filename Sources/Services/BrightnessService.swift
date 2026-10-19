import CoreGraphics
import IOKit
import IOKit.graphics

/// Adjusts the built-in display's brightness via IODisplayConnect parameters.
/// Silently does nothing when no built-in display supports it.
enum BrightnessService {
    private static let key = "brightness" as CFString

    private static var hasBuiltInDisplay: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count = UInt32(0)
        guard CGGetActiveDisplayList(16, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) != 0 }
    }

    private static func withService<T>(_ body: (io_service_t) -> T?) -> T? {
        guard hasBuiltInDisplay else { return nil }
        var iter = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }
        var service = IOIteratorNext(iter)
        while service != 0 {
            defer { IOObjectRelease(service) }
            if let result = body(service) { return result }
            service = IOIteratorNext(iter)
        }
        return nil
    }

    static func brightness() -> Float? {
        withService { service in
            var value: Float = 0
            return IODisplayGetFloatParameter(service, 0, key, &value) == kIOReturnSuccess ? value : nil
        }
    }

    static func setBrightness(_ value: Float) {
        _ = withService { service -> Bool? in
            IODisplaySetFloatParameter(service, 0, key, min(max(value, 0), 1)) == kIOReturnSuccess ? true : nil
        }
    }
}
