#!/usr/bin/env bash
set -euo pipefail

APP_NAME="mac-sleepless"
APP_LABEL="dev.lucasvtiradentes.mac-sleepless"
SUDOERS_PATH="/etc/sudoers.d/mac-sleepless"

stop_agent() {
  # bootout sends SIGTERM, and the app turns lid sleep back on before it exits.
  launchctl bootout "gui/$(id -u)/$APP_LABEL" 2>/dev/null || true
  pkill -TERM -x "$APP_NAME" 2>/dev/null || true
}

remove_files() {
  rm -f "$HOME/Library/LaunchAgents/$APP_LABEL.plist"
  rm -f "$HOME/Library/Application Support/$APP_NAME/bin/$APP_NAME"
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
