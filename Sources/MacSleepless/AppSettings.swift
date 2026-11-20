import Foundation

/// User preferences shared by the menu, the lid actions and the Settings window through UserDefaults.
enum AppSettings {
    static let wantsAwakeKey = "wantsAwake"
    static let displayOffKey = "lidClosedDisplayOff"
    static let muteKey = "lidClosedMute"
    static let lockKey = "lidClosedLock"
    static let minimumBatteryKey = "minimumBatteryPercent"

    static let batteryRange = 5...50
    static let defaultMinimumBattery = 15

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            displayOffKey: true,
            muteKey: true,
            lockKey: true,
            minimumBatteryKey: defaultMinimumBattery,
        ])
    }

    /// The user's choice, kept across launches so a restart, which resets SleepDisabled, re-arms it.
    static var wantsAwake: Bool {
        get { UserDefaults.standard.bool(forKey: wantsAwakeKey) }
        set { UserDefaults.standard.set(newValue, forKey: wantsAwakeKey) }
    }

    static var displayOff: Bool { UserDefaults.standard.bool(forKey: displayOffKey) }
    static var mute: Bool { UserDefaults.standard.bool(forKey: muteKey) }
    static var lock: Bool { UserDefaults.standard.bool(forKey: lockKey) }

    static var minimumBattery: Int {
        let value = UserDefaults.standard.integer(forKey: minimumBatteryKey)
        return min(max(value, batteryRange.lowerBound), batteryRange.upperBound)
    }
}
