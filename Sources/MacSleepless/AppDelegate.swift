import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let wantsAwakeKey = "wantsAwake"
    private static let checkInterval: TimeInterval = 30

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var terminationSource: DispatchSourceSignal?
    private var lastMessage: String?

    /// The user's choice, kept across launches so a restart, which resets SleepDisabled, re-arms it.
    private var wantsAwake: Bool {
        get { UserDefaults.standard.bool(forKey: Self.wantsAwakeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.wantsAwakeKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        // No left state column, so every label starts at the same edge.
        menu.showsStateColumn = false
        item.menu = menu
        statusItem = item

        handleTerminationSignal()
        NotificationCenter.default.addObserver(
            self, selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce() }
        }

        if wantsAwake { apply(true) }
        refreshIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Never leave the Mac unable to sleep once nothing is watching battery and heat.
        if SleepControl.isSleepDisabled() { try? SleepControl.setSleepDisabled(false) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Kept short on purpose: the icon and the trailing checkmark already show the state.
        let toggle = NSMenuItem(title: "", action: #selector(toggleAwake), keyEquivalent: "")
        toggle.target = self
        toggle.attributedTitle = toggleTitle(awake: SleepControl.isSleepDisabled())
        menu.addItem(toggle)
        if let lastMessage {
            let message = NSMenuItem(title: lastMessage, action: nil, keyEquivalent: "")
            message.isEnabled = false
            menu.addItem(message)
        }
        // A custom selector instead of terminate(_:), which macOS 26 decorates with an icon.
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    /// "Keep Awake" with the checkmark pushed to the right edge by a right-aligned tab stop.
    private func toggleTitle(awake: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 110)]
        return NSAttributedString(
            string: awake ? "Keep Awake\t\u{2713}" : "Keep Awake",
            attributes: [.paragraphStyle: paragraph, .font: NSFont.menuFont(ofSize: 0)])
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    @objc private func toggleAwake() {
        let next = !SleepControl.isSleepDisabled()
        wantsAwake = next
        apply(next)
    }

    // ProcessInfo posts this on an arbitrary thread, so hop to the main actor.
    @objc nonisolated private func thermalStateChanged() {
        Task { @MainActor in self.enforce() }
    }

    private func apply(_ awake: Bool) {
        if awake, let reason = SafetyGuard.stopReason() {
            wantsAwake = false
            lastMessage = "Not turned on: \(reason)"
            refreshIcon()
            return
        }
        do {
            try SleepControl.setSleepDisabled(awake)
            lastMessage = nil
        } catch {
            wantsAwake = false
            lastMessage = error.localizedDescription
        }
        refreshIcon()
    }

    /// Runs on a timer and on heat changes: ends the session when it is no longer safe.
    private func enforce() {
        if SleepControl.isSleepDisabled(), let reason = SafetyGuard.stopReason() {
            wantsAwake = false
            do {
                try SleepControl.setSleepDisabled(false)
                lastMessage = "Turned off: \(reason)"
            } catch {
                lastMessage = "Could not turn off (\(reason)): \(error.localizedDescription)"
            }
        }
        refreshIcon()
    }

    private func refreshIcon() {
        let awake = SleepControl.isSleepDisabled()
        let image = NSImage(
            systemSymbolName: awake ? "cup.and.saucer.fill" : "moon.zzz",
            accessibilityDescription: awake ? "Keeping the Mac awake" : "Mac sleeps normally")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    /// launchd stops agents with SIGTERM, which skips applicationWillTerminate unless routed here.
    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSource = source
    }
}
