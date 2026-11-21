import Foundation

/// Whether the LaunchAgent written by scripts/install.sh starts Sleepless at login.
/// The choice lives in launchd's own enable and disable overrides, the same ones the installer reads,
/// so there is one source of truth. Disabling only skips the next login; the running app keeps going.
enum LoginItem {
    static let label = "dev.lucasvtiradentes.sleepless"

    private static var domain: String { "gui/\(getuid())" }

    /// Recent launchd prints `"label" => disabled` and older versions `=> true`;
    /// a label with no line has never been overridden, so RunAtLoad starts it.
    static var isEnabled: Bool {
        guard let output = launchctl(["print-disabled", domain]) else { return true }
        let line = output.split(separator: "\n").first { $0.contains("\"\(label)\"") }
        guard let state = line?.split(separator: "=>").last?.trimmingCharacters(in: .whitespaces) else { return true }
        return state != "disabled" && state != "true"
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let done = launchctl([enabled ? "enable" : "disable", "\(domain)/\(label)"]) != nil
        Log.write("open at login \(enabled ? "on" : "off")\(done ? "" : " failed")")
        return done
    }

    /// Returns the output, or nil when launchctl failed.
    private static func launchctl(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
