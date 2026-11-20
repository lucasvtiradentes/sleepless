import Foundation
import IOKit.ps

/// Conditions that must end a lid-closed session, because a closed Mac in a bag cannot cool down
/// and would otherwise drain the battery to zero.
enum SafetyGuard {
    struct Battery {
        let percent: Int
        let onBattery: Bool
    }

    static func battery() -> Battery? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard
                let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                    as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let state = description[kIOPSPowerSourceStateKey] as? String
            return Battery(percent: current * 100 / max, onBattery: state == kIOPSBatteryPowerValue)
        }
        return nil
    }

    /// Returns why the Mac must be allowed to sleep, or nil when keeping it awake is safe.
    static func stopReason() -> String? {
        if ProcessInfo.processInfo.thermalState == .critical {
            return "Mac is too hot"
        }
        if let battery = battery(), battery.onBattery, battery.percent < AppSettings.minimumBattery {
            return "battery at \(battery.percent)%"
        }
        return nil
    }
}
