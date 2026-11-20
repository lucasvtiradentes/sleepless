import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let checkInterval: TimeInterval = 30
    /// Written by scripts/install.sh before it restarts the app, so the old process keeps the Mac
    /// awake through the swap instead of letting a closed-lid Mac fall asleep mid-install.
    static let handoffMarker = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/sleepless/handoff")
    private static let handoffMaxAge: TimeInterval = 120

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var terminationSource: DispatchSourceSignal?
    private var lastMessage: String?
    private var lidMonitor: LidMonitor?
    private let lidActions = LidActions()
    private let settingsWindow = SettingsWindow()
    private let updater = Updater()

    private var wantsAwake: Bool {
        get { AppSettings.wantsAwake }
        set { AppSettings.wantsAwake = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        try? FileManager.default.removeItem(at: Self.handoffMarker)
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
        let timer = Timer(timeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.enforce() }
        }
        // Common modes keep the battery and heat checks running while a modal alert is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        // Only transitions act, so a restart with the lid already closed does not lock or mute.
        lidMonitor = LidMonitor { [weak self] closed in self?.lidChanged(closed) }

        if wantsAwake { apply(true) }
        refreshIcon()
        Log.write("started \(Updater.version), keep awake \(SleepControl.isSleepDisabled() ? "on" : "off")")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if isHandoff() {
            Log.write("restarting for an update, keeping the Mac awake")
            return
        }
        // Never leave the Mac unable to sleep once nothing is watching battery and heat.
        if SleepControl.isSleepDisabled() { try? SleepControl.setSleepDisabled(false) }
        Log.write("quit, lid sleep restored")
    }

    private func isHandoff() -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Self.handoffMarker.path)
        guard let created = attributes?[.modificationDate] as? Date else { return false }
        return Date().timeIntervalSince(created) < Self.handoffMaxAge
    }

    /// Lid actions only matter while the Mac is kept awake; otherwise closing the lid sleeps it anyway.
    private func lidChanged(_ closed: Bool) {
        if closed {
            guard SleepControl.isSleepDisabled() else { return }
            lidActions.lidClosed()
        } else {
            lidActions.lidOpened()
        }
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
        let settings = NSMenuItem(title: "Settings", action: #selector(showOptionsWindow), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let update = NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
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

    @objc private func showOptionsWindow() {
        settingsWindow.show()
    }

    @objc private func checkForUpdates() {
        updater.checkForUpdates()
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
                Log.write("turned off: \(reason)")
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
