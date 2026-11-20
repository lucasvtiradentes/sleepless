#!/usr/bin/env bash
# Prints previous=<tag> and tag=<next tag> for GITHUB_OUTPUT, bumping the latest vX.Y.Z tag.
set -euo pipefail

latest_tag() {
  git tag --list 'v*' --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -n 1 || true
}

bump() {
  local version="$1"
  local part="$2"
  local major minor patch
  IFS=. read -r major minor patch <<EOF
$version
EOF

  case "$part" in
    major) printf "%s.0.0" "$((major + 1))" ;;
    minor) printf "%s.%s.0" "$major" "$((minor + 1))" ;;
    patch) printf "%s.%s.%s" "$major" "$minor" "$((patch + 1))" ;;
    *)
      printf "Unknown bump: %s\n" "$part" >&2
      exit 1
      ;;
  esac
}

main() {
  local part="${1:-patch}"
  local previous base
  previous="$(latest_tag)"
  # The first release starts from 0.0.0, so a minor bump gives v0.1.0.
  base="${previous#v}"
  [ -n "$base" ] || base="0.0.0"

  printf "previous=%s\n" "$previous"
  printf "tag=v%s\n" "$(bump "$base" "$part")"
}

main "$@"
