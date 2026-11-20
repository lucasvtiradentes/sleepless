import Foundation

/// What happens when the lid closes while the Mac is kept awake, and how it is undone when it opens.
@MainActor
final class LidActions {
    private static let mutedByAppKey = "mutedByApp"

    /// Persisted so a restart with the lid closed still unmutes on the next open.
    private var mutedByApp: Bool {
        get { UserDefaults.standard.bool(forKey: Self.mutedByAppKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.mutedByAppKey) }
    }

    func lidClosed() {
        var done: [String] = []
        if AppSettings.mute, !isMuted() {
            setMuted(true)
            mutedByApp = true
            done.append("muted")
        }
        if AppSettings.lock {
            lockScreen()
            done.append("locked")
        }
        // Locking only asks loginwindow, which then draws the lock screen and can wake the display,
        // so turn it off a moment later.
        if AppSettings.displayOff {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.run("/usr/bin/pmset", ["displaysleepnow"])
            }
            done.append("display off")
        }
        Log.write("lid closed: \(done.isEmpty ? "no actions" : done.joined(separator: ", "))")
    }

    /// Only undoes what this app did, so a Mac the user muted stays muted.
    func lidOpened() {
        if mutedByApp {
            setMuted(false)
            mutedByApp = false
        }
        Log.write("lid opened")
    }

    private func isMuted() -> Bool {
        appleScript("output muted of (get volume settings)")?.booleanValue ?? false
    }

    private func setMuted(_ muted: Bool) {
        _ = appleScript("set volume output muted \(muted)")
    }

    /// The same call the Lock Screen menu item uses; it lives in a private framework with no public API.
    private func lockScreen() {
        guard
            let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
            let symbol = dlsym(handle, "SACLockScreenImmediate")
        else {
            Log.write("lock failed: SACLockScreenImmediate not found")
            return
        }
        typealias LockFunction = @convention(c) () -> Int32
        _ = unsafeBitCast(symbol, to: LockFunction.self)()
    }

    private func appleScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error { Log.write("AppleScript failed: \(error)") }
        return result
    }

    private func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }
}
