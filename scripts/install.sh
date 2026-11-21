#!/usr/bin/env bash
# Installs Sleepless and starts it at login.
#   curl -fsSL https://raw.githubusercontent.com/lucasvtiradentes/sleepless/main/scripts/install.sh | bash
#   scripts/install.sh --from-source       build from this checkout instead of downloading
#   SLEEPLESS_VERSION=v0.1.0 ... | bash    pin a release instead of the latest one
# Running it again updates an existing install.
set -euo pipefail

APP_NAME="sleepless"
APP_LABEL="dev.lucasvtiradentes.sleepless"
REPO="lucasvtiradentes/sleepless"
ASSET="sleepless-macos-universal.tar.gz"

fail() {
  printf "Error: %s\n" "$1" >&2
  exit 1
}

xml_escape() {
  printf "%s" "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

check_platform() {
  [ "$(uname -s)" = "Darwin" ] || fail "Sleepless only runs on macOS."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$major" -ge 14 ] || fail "Sleepless needs macOS 14 or later."
}

build_from_source() {
  local repo_dir="$1"
  local output="$2"

  swift build -c release --package-path "$repo_dir"
  cp "$repo_dir/.build/release/$APP_NAME" "$output/$APP_NAME"
  # "dev" tells the app's Check for Updates that this copy updates with make install.
  printf "dev\n" > "$output/VERSION"
}

release_url() {
  local file="$1"
  local version="${SLEEPLESS_VERSION:-}"

  if [ -n "$version" ]; then
    printf "https://github.com/%s/releases/download/%s/%s" "$REPO" "$version" "$file"
  else
    printf "https://github.com/%s/releases/latest/download/%s" "$REPO" "$file"
  fi
}

download_release() {
  local work_dir="$1"
  local output="$2"
  local expected actual

  printf "Downloading %s...\n" "$(release_url "$ASSET")"
  curl -fsSL "$(release_url "$ASSET")" -o "$work_dir/$ASSET" || fail "Download failed."
  curl -fsSL "$(release_url "$ASSET.sha256")" -o "$work_dir/$ASSET.sha256" || fail "Checksum download failed."
  expected="$(cut -d' ' -f1 < "$work_dir/$ASSET.sha256")"
  actual="$(shasum -a 256 "$work_dir/$ASSET" | cut -d' ' -f1)"
  [ "$expected" = "$actual" ] || fail "Checksum mismatch for $ASSET."

  mkdir -p "$output"
  tar -xzf "$work_dir/$ASSET" -C "$output"
}

install_binary() {
  local source_dir="$1"
  local target_bin="$2"
  local source_bin="$source_dir/$APP_NAME"

  mkdir -p "$(dirname "$target_bin")"
  # A new file instead of writing over the old one: macOS caches the signature per file, and
  # overwriting a signed binary in place can get the next launch killed.
  cp "$source_bin" "$target_bin.new"
  chmod +x "$target_bin.new"
  # curl does not set the quarantine flag, so Gatekeeper lets an ad hoc signature run without
  # a paid Developer ID; a browser download would be quarantined and blocked.
  codesign --force --sign - --identifier "$APP_LABEL" "$target_bin.new"
  cp "$source_dir/VERSION" "$(dirname "$target_bin")/VERSION"
  mv -f "$target_bin.new" "$target_bin"
}

# The new app deletes the handoff marker at launch; if it never does, it is crashing, and the old
# one already left sleep disabled, so report failure and let the EXIT trap restore lid sleep.
wait_for_new_app() {
  local handoff_marker="$1"
  local tries=0

  while [ -e "$handoff_marker" ] && [ "$tries" -lt 150 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
  [ ! -e "$handoff_marker" ] || fail "The new version did not start."
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
  <!-- Lets the installer started by Check for Updates outlive the app it replaces. -->
  <key>AbandonProcessGroup</key>
  <true/>
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
  local handoff_marker="$1"
  local tries=0

  # Tells the running app this is an update, so it keeps the Mac awake while it exits;
  # otherwise a Mac with the lid closed would sleep before the new app starts.
  mkdir -p "$(dirname "$handoff_marker")"
  touch "$handoff_marker"

  launchctl bootout "gui/$(id -u)/$APP_LABEL" 2>/dev/null || true
  pkill -TERM -x "$APP_NAME" 2>/dev/null || true
  # The app turns lid sleep back on before exiting; bootstrap fails while the old job lingers.
  while pgrep -x "$APP_NAME" >/dev/null 2>&1 && [ "$tries" -lt 50 ]; do
    sleep 0.1
    tries=$((tries + 1))
  done
}

# If the new app cannot start, nothing watches battery and heat, so let the Mac sleep again.
restore_lid_sleep() {
  local handoff_marker="$1"

  rm -f "$handoff_marker"
  sudo -n /usr/bin/pmset -a disablesleep 0 2>/dev/null || true
}

# The Settings switch "Open at login" stores its choice as launchd's disable override.
# Recent launchd prints "label" => disabled, older versions => true.
login_disabled() {
  launchctl print-disabled "gui/$(id -u)" 2>/dev/null |
    grep -E "\"$APP_LABEL\" => (disabled|true)" >/dev/null
}

start_launch_agent() {
  local plist_path="$1"
  local domain was_disabled=false
  domain="gui/$(id -u)"

  if login_disabled; then was_disabled=true; fi
  # bootstrap refuses a disabled job, so enable it to start now, then restore the choice:
  # disable only affects the next login and leaves the running app alone.
  launchctl enable "$domain/$APP_LABEL"
  launchctl bootstrap "$domain" "$plist_path"
  [ "$was_disabled" = false ] || launchctl disable "$domain/$APP_LABEL"
}

WORK_DIR=""
HANDOFF_MARKER=""
SWAP_STATE="none"

# Runs on every exit, including set -e failures inside functions, which an ERR trap would miss.
on_exit() {
  [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
  if [ "$SWAP_STATE" = "started" ]; then
    restore_lid_sleep "$HANDOFF_MARKER"
    printf "Install failed after stopping the old app; lid sleep is back on.\n" >&2
  fi
}

source_dir() {
  [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] ||
    fail "--from-source needs a local checkout: run scripts/install.sh --from-source from the repo."
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
}

main() {
  local from_source=false
  local support_dir target_bin plist_path repo_dir=""
  case "${1:-}" in
    --from-source) from_source=true ;;
    "") ;;
    *) fail "Unknown option: $1" ;;
  esac

  check_platform
  [ "$from_source" = false ] || repo_dir="$(source_dir)"
  support_dir="$HOME/Library/Application Support/$APP_NAME"
  target_bin="$support_dir/bin/$APP_NAME"
  plist_path="$HOME/Library/LaunchAgents/$APP_LABEL.plist"
  HANDOFF_MARKER="$support_dir/handoff"
  WORK_DIR="$(mktemp -d)"
  trap on_exit EXIT

  # Get and swap the binary while the old app still runs, so a failed build or download leaves it guarding.
  if [ "$from_source" = true ]; then
    mkdir -p "$WORK_DIR/new"
    build_from_source "$repo_dir" "$WORK_DIR/new"
  else
    download_release "$WORK_DIR" "$WORK_DIR/new"
  fi
  install_binary "$WORK_DIR/new" "$target_bin"

  SWAP_STATE="started"
  stop_running_app "$HANDOFF_MARKER"
  write_launch_agent "$plist_path" "$target_bin"
  start_launch_agent "$plist_path"
  wait_for_new_app "$HANDOFF_MARKER"
  SWAP_STATE="done"
  printf "Installed %s %s and started it at login. Click its menu bar icon and choose Keep Awake.\n" "$APP_NAME" "$(cat "$WORK_DIR/new/VERSION")"
}

main "$@"
