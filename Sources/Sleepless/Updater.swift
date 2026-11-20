import AppKit

enum UpdateError: LocalizedError {
    case noRelease
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .noRelease: "No release is published on GitHub yet."
        case .badResponse(let status): "GitHub answered with status \(status)."
        }
    }
}

/// Checks GitHub for a newer release and installs it with the same script as the first install.
/// A build from source has version "dev" and updates with `make install` instead.
@MainActor
final class Updater {
    static let repository = "lucasvtiradentes/sleepless"

    /// Written next to the binary by scripts/install.sh: a release tag such as v0.1.0, or "dev".
    static let version: String = {
        guard let executable = Bundle.main.executableURL else { return "dev" }
        let file = executable.deletingLastPathComponent().appendingPathComponent("VERSION")
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? "dev"
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }()

    static var isLocalBuild: Bool { parse(version) == nil }

    private var checking = false
    /// Set once an installer starts, so a second click cannot start another one.
    private var updating = false

    func checkForUpdates() {
        guard !Self.isLocalBuild else {
            alert(
                "Local build",
                "This copy was built from source. To update, pull the repository and run make install.")
            return
        }
        guard !checking, !updating else { return }
        checking = true
        Task {
            defer { checking = false }
            do {
                let latest = try await Self.latestTag()
                // Only a well-formed tag reaches the installer's shell command below.
                guard let latestVersion = Self.parse(latest), let current = Self.parse(Self.version),
                    current.lexicographicallyPrecedes(latestVersion)
                else {
                    alert("You're up to date", "Sleepless \(Self.version) is the latest version.")
                    return
                }
                if confirm(
                    "Sleepless \(latest) is available",
                    "You have \(Self.version). Sleepless restarts after the update and keeps the Mac awake meanwhile.",
                    button: "Update")
                {
                    install(latest)
                }
            } catch {
                alert("Could not check for updates", error.localizedDescription)
            }
        }
    }

    private static func latestTag() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status != 404 else { throw UpdateError.noRelease }
        guard status == 200,
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String
        else { throw UpdateError.badResponse(status) }
        return tag
    }

    /// "v1.2.3" to [1, 2, 3]; nil for "dev" or anything else.
    private static func parse(_ tag: String) -> [Int]? {
        guard tag.hasPrefix("v") else { return nil }
        let parts = tag.dropFirst().split(separator: ".").map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// Runs the installer of that exact tag. The LaunchAgent sets AbandonProcessGroup, so launchd
    /// lets the installer keep running after it stops this app to swap the binary.
    private func install(_ tag: String) {
        let script = "https://raw.githubusercontent.com/\(Self.repository)/\(tag)/scripts/install.sh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // pipefail: a failed download must not look like an empty script that succeeded.
        process.arguments = ["-c", "set -o pipefail; curl -fsSL '\(script)' | SLEEPLESS_VERSION='\(tag)' /bin/bash"]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        do {
            // Reached only when the installer fails before stopping this app, so the old version keeps running.
            process.terminationHandler = { [weak self] finished in
                guard finished.terminationStatus != 0 else { return }
                Task { @MainActor in
                    self?.updating = false
                    self?.alert("Update failed", "Sleepless \(tag) could not be installed. See the log for details.")
                }
            }
            try process.run()
            updating = true
            Log.write("updating to \(tag)")
        } catch {
            alert("Could not start the update", error.localizedDescription)
        }
    }

    private func alert(_ title: String, _ message: String) {
        _ = confirm(title, message, button: nil)
    }

    /// A menu bar app is never frontmost, so activate it first or the alert opens behind other windows.
    private func confirm(_ title: String, _ message: String, button: String?) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        // A bare binary has no app icon, so NSAlert would fall back to a generic folder.
        alert.icon = NSImage(systemSymbolName: "cup.and.saucer.fill", accessibilityDescription: "Sleepless")
        alert.messageText = title
        alert.informativeText = message
        if let button {
            alert.addButton(withTitle: button)
            alert.addButton(withTitle: "Later")
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
