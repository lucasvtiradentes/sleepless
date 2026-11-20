#!/usr/bin/env bash
set -euo pipefail

APP_NAME="mac-sleepless"
APP_LABEL="dev.lucasvtiradentes.mac-sleepless"

xml_escape() {
  printf "%s" "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

build_and_install_binary() {
  local repo_dir="$1"
  local target_bin="$2"

  swift build -c release --package-path "$repo_dir"
  mkdir -p "$(dirname "$target_bin")"
  # A new file instead of writing over the old one: macOS caches the signature per file, and
  # overwriting a signed binary in place can get the next launch killed.
  cp "$repo_dir/.build/release/$APP_NAME" "$target_bin.new"
  chmod +x "$target_bin.new"
  codesign --force --sign - --identifier "$APP_LABEL" "$target_bin.new"
  mv -f "$target_bin.new" "$target_bin"
}

write_launch_agent() {
  local plist_path="$1"
  local target_bin="$2"
  local log_dir="$HOME/Library/Logs"

  mkdir -p "$(dirname "$plist_path")" "$log_dir"
  # KeepAlive restarts it only after a crash, so the battery and heat checks keep running,
  # while Quit from the menu stays quit.
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$APP_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$target_bin")</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$log_dir/$APP_LABEL.out.log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$log_dir/$APP_LABEL.err.log")</string>
</dict>
</plist>
PLIST
}

stop_running_app() {
  local tries=0

  launchctl bootout "gui/$(id -u)/$APP_LABEL" 2>/dev/null || true
  pkill -TERM -x "$APP_NAME" 2>/dev/null || true
  # The app turns lid sleep back on before exiting; bootstrap fails while the old job lingers.
  while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
}

start_launch_agent() {
  local plist_path="$1"
  local domain
  domain="gui/$(id -u)"

  launchctl enable "$domain/$APP_LABEL"
  launchctl bootstrap "$domain" "$plist_path"
}

main() {
  local script_dir repo_dir target_bin plist_path
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  repo_dir="$(cd -- "$script_dir/.." && pwd)"
  target_bin="$HOME/Library/Application Support/$APP_NAME/bin/$APP_NAME"
  plist_path="$HOME/Library/LaunchAgents/$APP_LABEL.plist"

  stop_running_app
  build_and_install_binary "$repo_dir" "$target_bin"
  write_launch_agent "$plist_path" "$target_bin"
  start_launch_agent "$plist_path"
  printf "Installed %s and started it at login: %s\n" "$APP_NAME" "$plist_path"
}

main "$@"
