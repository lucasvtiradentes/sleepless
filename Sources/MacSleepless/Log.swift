import Foundation

/// One timestamped line per event on stdout, which the LaunchAgent sends to
/// ~/Library/Logs/dev.lucasvtiradentes.mac-sleepless.out.log, so an agent can read it remotely.
enum Log {
    static func write(_ message: String) {
        print(
            "\(Date().formatted(.dateTime.year().month(.twoDigits).day(.twoDigits).hour().minute().second())) \(message)"
        )
        fflush(stdout)
    }
}
