import Foundation
import IOKit
import IOKit.pwr_mgt

/// Reports lid open and close from powerd's root domain, which posts a clamshell message on each change.
@MainActor
final class LidMonitor {
    // iokit_family_msg(sub_iokit_powermanagement, 0x100); the Swift overlay does not export the macro.
    private static let clamshellStateChange: UInt32 = 0xE003_4100
    private static let clamshellClosedBit = 1

    private let onChange: (Bool) -> Void
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = IO_OBJECT_NULL
    private var lastClosed: Bool

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
        lastClosed = Self.isClosed()
        start()
    }

    static func isClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    private func start() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL, let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        defer { IOObjectRelease(service) }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = IOServiceAddInterestNotification(
            port, service, kIOGeneralInterest,
            { context, _, messageType, argument in
                guard messageType == LidMonitor.clamshellStateChange, let context else { return }
                let closed = (Int(bitPattern: argument) & LidMonitor.clamshellClosedBit) != 0
                let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.report(closed) }
            }, context, &notifier)
        if result != KERN_SUCCESS { Log.write("lid monitor failed: \(result)") }
    }

    /// powerd can repeat the message without a real change, so only transitions reach the caller.
    private func report(_ closed: Bool) {
        guard closed != lastClosed else { return }
        lastClosed = closed
        onChange(closed)
    }
}
