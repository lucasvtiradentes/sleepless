# mac-sleepless

A menu bar app that keeps a MacBook awake with the lid closed, so agents keep running and the Mac stays reachable from a phone.

## How it works

- Closing the lid sleeps the Mac even with `caffeinate` running; only the system `SleepDisabled` flag stops it.
- The app sets it with `pmset -a disablesleep 1|0` through a sudoers rule limited to those two commands.
- The first time you turn it on, macOS asks for your password once to install that rule in `/etc/sudoers.d/mac-sleepless`.
- The menu bar icon reads the real flag: a cup when awake, a moon when the Mac sleeps normally. Its menu has only Keep Awake and Quit.

## Safety

- Turns off below 15% battery when unplugged, and when macOS reports a critical temperature.
- Turns off when you quit the app or when launchd stops it.
- Remembers your choice, so it turns on again after a restart, which resets the flag.

## Usage

```bash
make install    # build, install and start at login
make uninstall  # stop, remove the login agent and the sudoers rule
make dev        # run the debug build
make check      # swift-format lint
```

Quit other lid-sleep tools, such as Clamshell or Amphetamine, so they do not reset the flag.
