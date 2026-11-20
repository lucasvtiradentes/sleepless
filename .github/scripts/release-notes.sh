#!/usr/bin/env bash
# Prints Markdown release notes from the commit titles since the previous tag, grouped by type.
#   release-notes.sh <previous tag or empty> <new tag>
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-lucasvtiradentes/sleepless}"
TYPE_PREFIX='^[a-z]+(\([^)]*\))?!?: '

commits() {
  local previous="$1"
  local range="HEAD"
  [ -z "$previous" ] || range="$previous..HEAD"
  git log --no-merges --pretty='%s (%h)' "$range"
}

# Prints one "### title" list from the commits that match (or, with -v, do not match) the pattern.
section() {
  local title="$1"
  local grep_flags="$2"
  local pattern="$3"
  local commit_list="$4"
  local lines
  lines="$(printf "%s\n" "$commit_list" | grep -E "$grep_flags" "$pattern" | sed -E "s/$TYPE_PREFIX//" || true)"
  [ -n "$lines" ] || return 0
  printf "### %s\n\n" "$title"
  printf "%s\n" "$lines" | sed 's/^/- /'
  printf "\n"
}

main() {
  local previous="${1:-}"
  local tag="$2"
  local commit_list
  commit_list="$(commits "$previous")"

  printf "## Install\n\n"
  # shellcheck disable=SC2016 # the backticks are a Markdown code fence, not a command
  printf '```bash\ncurl -fsSL https://raw.githubusercontent.com/%s/%s/scripts/install.sh | SLEEPLESS_VERSION=%s bash\n```\n\n' \
    "$REPO" "$tag" "$tag"
  printf "## Changes\n\n"
  section "Features" -e '^feat(\(|!|:)' "$commit_list"
  section "Fixes" -e '^fix(\(|!|:)' "$commit_list"
  section "Other" -v '^(feat|fix)(\(|!|:)' "$commit_list"
  if [ -n "$previous" ]; then
    printf "Full changelog: https://github.com/%s/compare/%s...%s\n" "$REPO" "$previous" "$tag"
  fi
}

main "$@"
