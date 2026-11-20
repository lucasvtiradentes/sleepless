# mac-sleepless

A menu bar app that keeps a MacBook awake with the lid closed, so agents keep running and the Mac stays reachable from a phone.

## How it works

- Closing the lid sleeps the Mac even with `caffeinate` running; only the system `SleepDisabled` flag stops it.
- The app sets it with `pmset -a disablesleep 1|0` through a sudoers rule limited to those two commands.
- The first time you turn it on, macOS asks for your password once to install that rule in `/etc/sudoers.d/mac-sleepless`.
- The menu bar icon reads the real flag: a cup when awake, a moon when the Mac sleeps normally. Its menu has Keep Awake, Settings and Quit.

## Lid closed

While Keep Awake is on, closing the lid turns off the display, mutes the sound and locks the Mac; opening it unmutes, only when the app muted it. Each action has a switch in Settings. Every lid change and automatic turn-off goes to `~/Library/Logs/dev.lucasvtiradentes.mac-sleepless.out.log`.

## Safety

- Turns off below a battery level when unplugged, 15% by default and 5% to 50% in Settings, and when macOS reports a critical temperature.
- Turns off when you quit the app or when launchd stops it.
- Remembers your choice, so it turns on again after a restart, which resets the flag.

## Usage

```bash
make install    # build, install and start at login; safe with the lid closed
make uninstall  # stop, remove the login agent and the sudoers rule
make dev        # run the debug build
make check      # swift-format lint
```

Quit other lid-sleep tools, such as Clamshell or Amphetamine, so they do not reset the flag.

## Remote screen

To see and control the Mac from an iPhone with the lid closed, follow [docs/remote-screen.md](docs/remote-screen.md): macOS Screen Sharing, Tailscale and RealVNC Viewer.
