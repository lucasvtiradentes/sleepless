import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettings.displayOffKey) private var displayOff = true
    @AppStorage(AppSettings.muteKey) private var mute = true
    @AppStorage(AppSettings.lockKey) private var lock = true
    @AppStorage(AppSettings.minimumBatteryKey) private var minimumBattery = AppSettings.defaultMinimumBattery

    var body: some View {
        Form {
            Section("When the lid closes") {
                Toggle("Turn off the display", isOn: $displayOff)
                Toggle("Mute sound", isOn: $mute)
                Toggle("Lock the Mac", isOn: $lock)
            }
            Section("Battery") {
                LabeledContent("Turn off below") {
                    HStack(spacing: 6) {
                        Text("\(minimumBattery)%").monospacedDigit()
                        Stepper("", value: $minimumBattery, in: AppSettings.batteryRange, step: 5).labelsHidden()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .tint(.blue)
        .frame(width: 320)
        .fixedSize()
    }
}

@MainActor
final class SettingsWindow {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "mac-sleepless Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu bar app is never frontmost, and macOS 14+ refuses a polite activate(), which leaves
        // the window behind others and inactive, drawing every switch gray instead of blue.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
