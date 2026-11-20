import Foundation
import IOKit

enum SleepControlError: LocalizedError {
    case pmsetFailed(String)
    case setupCancelled
    case setupFailed(String)

    var errorDescription: String? {
        switch self {
        case .pmsetFailed(let output): "pmset failed: \(output)"
        case .setupCancelled: "Permission setup was cancelled"
        case .setupFailed(let message): "Permission setup failed: \(message)"
        }
    }
}

/// Toggles the system-wide `SleepDisabled` flag, the only switch that also stops lid-close sleep.
/// `caffeinate` and IOPM assertions only block idle sleep, so they are not enough with the lid closed.
enum SleepControl {
    static let pmsetPath = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/sleepless"

    /// Reads the flag from powerd's root domain, so the menu shows the real state even when
    /// something else, such as a manual `pmset`, changed it.
    static func isSleepDisabled() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)
        return (value?.takeRetainedValue() as? Bool) ?? false
    }

    static func setSleepDisabled(_ disabled: Bool) throws {
        let result = runSudoPmset(disabled)
        if result.status == 0 { return }
        // Only turning on may prompt: the safety path runs from a timer, maybe with the lid closed,
        // where a blocking password dialog would stop every later battery and heat check.
        guard disabled, !FileManager.default.fileExists(atPath: sudoersPath) else {
            throw SleepControlError.pmsetFailed(result.output)
        }
        try installSudoersRule()
        let retry = runSudoPmset(disabled)
        guard retry.status == 0 else { throw SleepControlError.pmsetFailed(retry.output) }
    }

    private static func runSudoPmset(_ disabled: Bool) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        // -n never prompts: without the sudoers rule it fails fast instead of hanging on a tty.
        process.arguments = ["-n", pmsetPath, "-a", "disablesleep", disabled ? "1" : "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Installs a sudoers rule limited to the two exact pmset commands, after one admin prompt,
    /// so later toggles run without a password.
    private static func installSudoersRule() throws {
        let user = NSUserName()
        let rule =
            "\(user) ALL=(root) NOPASSWD: \(pmsetPath) -a disablesleep 0, \(pmsetPath) -a disablesleep 1\n"
        let draft = FileManager.default.temporaryDirectory.appendingPathComponent("sleepless.sudoers")
        do {
            try rule.write(to: draft, atomically: true, encoding: .utf8)
        } catch {
            throw SleepControlError.setupFailed(error.localizedDescription)
        }
        defer { try? FileManager.default.removeItem(at: draft) }

        // Copy to a root-owned file first and validate that copy, so the draft cannot change between
        // the check and the install. sudo skips names with a dot, so the staged file is never loaded,
        // and visudo keeps a broken rule from locking sudo for everyone.
        let staged = sudoersPath + ".new"
        let command =
            "/usr/bin/install -m 0440 -o root -g wheel \(shellQuote(draft.path)) \(shellQuote(staged)) && "
            + "/usr/sbin/visudo -cf \(shellQuote(staged)) && /bin/mv -f \(shellQuote(staged)) \(shellQuote(sudoersPath)) "
            + "|| { /bin/rm -f \(shellQuote(staged)); exit 1; }"
        let source =
            "do shell script \(appleScriptQuote(command)) with administrator privileges "
            + "with prompt \"Sleepless needs your password once to keep the Mac awake with the lid closed.\""
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return }
        if (errorInfo[NSAppleScript.errorNumber] as? Int) == -128 { throw SleepControlError.setupCancelled }
        throw SleepControlError.setupFailed(errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptQuote(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
