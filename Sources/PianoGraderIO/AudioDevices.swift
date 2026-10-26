#if os(macOS)
import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// An audio device the Mac has: a microphone, an interface, speakers, headphones.
public struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    /// Core Audio's `AudioDeviceID` (changes between launches).
    public let id: UInt32
    /// Stable across launches and reconnects: what settings remember.
    public let uid: String
    public let name: String
    public let isBuiltIn: Bool
}

/// The Mac's audio devices, for choosing what to listen to and where to play.
public enum AudioDevices {
    public static func inputs() -> [AudioDeviceInfo] {
        all().filter { hasStreams($0.id, scope: kAudioDevicePropertyScopeInput) }
    }

    public static func outputs() -> [AudioDeviceInfo] {
        all().filter { hasStreams($0.id, scope: kAudioDevicePropertyScopeOutput) }
    }

    /// The built-in microphone, if this Mac has one (a Mac mini or Mac Studio doesn't).
    public static func builtInInput() -> AudioDeviceInfo? {
        inputs().first { $0.isBuiltIn }
    }

    /// The output macOS is using (System Settings → Sound → Output).
    public static func defaultOutput() -> AudioDeviceInfo? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return info(id)
    }

    public static func device(uid: String) -> AudioDeviceInfo? {
        all().first { $0.uid == uid }
    }

    /// Points an engine's output at a device (nil: the system default output). Stops the engine
    /// while switching and starts it again if it was running.
    @discardableResult
    public static func setOutput(of engine: AVAudioEngine, toUID uid: String?) -> Bool {
        guard let target = uid.flatMap(device(uid:)) ?? defaultOutput(),
              let unit = engine.outputNode.audioUnit else { return false }
        var id = AudioDeviceID(target.id)
        let wasRunning = engine.isRunning
        if wasRunning { engine.stop() }
        let status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                          &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        if wasRunning { try? engine.start() }
        return status == noErr
    }

    // MARK: Core Audio

    private static func all() -> [AudioDeviceInfo] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(info)
    }

    private static func info(_ id: AudioDeviceID) -> AudioDeviceInfo? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID) else { return nil }
        return AudioDeviceInfo(id: id, uid: uid, name: string(id, kAudioObjectPropertyName) ?? uid, isBuiltIn: isBuiltIn(id))
    }

    private static func string(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr,
              let string = value?.takeRetainedValue() else { return nil }
        return string as String
    }

    private static func isBuiltIn(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBuiltIn
    }

    private static func hasStreams(_ id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr && size > 0
    }
}
#endif
