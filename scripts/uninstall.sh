#!/usr/bin/env bash
# Removes Sleepless, its login agent and its sudoers rule, and lets the Mac sleep with the lid closed again.
#   curl -fsSL https://raw.githubusercontent.com/lucasvtiradentes/sleepless/main/scripts/uninstall.sh | bash
set -euo pipefail

APP_NAME="sleepless"
APP_LABEL="dev.lucasvtiradentes.sleepless"
SUDOERS_PATH="/etc/sudoers.d/sleepless"

stop_agent() {
  # bootout sends SIGTERM, and the app turns lid sleep back on before it exits.
  launchctl bootout "gui/$(id -u)/$APP_LABEL" 2>/dev/null || true
  pkill -TERM -x "$APP_NAME" 2>/dev/null || true
}

remove_files() {
  rm -f "$HOME/Library/LaunchAgents/$APP_LABEL.plist"
  rm -rf "$HOME/Library/Application Support/$APP_NAME"
}

remove_sudoers_rule() {
  sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || true
  if [ -e "$SUDOERS_PATH" ]; then
    sudo rm -f "$SUDOERS_PATH"
  fi
}

main() {
  stop_agent
  remove_files
  remove_sudoers_rule
  printf "Removed %s.\n" "$APP_NAME"
}

main "$@"
