import Foundation

enum DevicePairingSupport {
    static var supportsOnDevicePairing: Bool {
#if DEBUG
        // Preview the iOS 26 setup UI on a newer simulator; no device handshake is simulated.
        if ProcessInfo.processInfo.arguments.contains("--preview-computer-pairing") { return false }
#endif
        return supportsOnDevicePairing(on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func supportsOnDevicePairing(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion >= 27
    }

    /// iOS 17.4–17.x has no network remote-pairing service. WrapPin instead uses
    /// a classic lockdown pairing file (.mobiledevicepairing) and lockdown's
    /// CoreDeviceProxy tunnel, and mounts the Developer Disk Image itself.
    static var usesLockdownTunnel: Bool {
        usesLockdownTunnel(on: ProcessInfo.processInfo.operatingSystemVersion)
    }

    static func usesLockdownTunnel(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion == 17
    }

    /// CoreDeviceProxy over lockdown first appeared in iOS 17.4.
    static func isLockdownTunnelAvailable(on version: OperatingSystemVersion) -> Bool {
        version.majorVersion > 17 || (version.majorVersion == 17 && version.minorVersion >= 4)
    }
}
