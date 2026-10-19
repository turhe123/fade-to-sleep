import CoreAudio
import AudioToolbox

/// Reads and writes the default output device's volume through Core Audio,
/// preferring the virtual main volume and falling back to per-channel scalars.
enum AudioService {
    static func defaultOutputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private static func mainAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func channelAddress(_ channel: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: channel)
    }

    private static func read(_ device: AudioDeviceID, _ addr: AudioObjectPropertyAddress) -> Float? {
        var addr = addr
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func write(_ device: AudioDeviceID, _ addr: AudioObjectPropertyAddress, _ value: Float) -> Bool {
        var addr = addr
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(value)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    /// Current volume (0…1), or nil if the device exposes no volume control.
    static func volume(_ device: AudioDeviceID) -> Float? {
        if let v = read(device, mainAddress()) { return v }
        let values = [UInt32(1), 2].compactMap { read(device, channelAddress($0)) }
        return values.isEmpty ? nil : values.reduce(0, +) / Float(values.count)
    }

    @discardableResult
    static func setVolume(_ value: Float, on device: AudioDeviceID) -> Bool {
        let v = min(max(value, 0), 1)
        if write(device, mainAddress(), v) { return true }
        var ok = false
        for ch in [UInt32(1), 2] where write(device, channelAddress(ch), v) { ok = true }
        return ok
    }
}
