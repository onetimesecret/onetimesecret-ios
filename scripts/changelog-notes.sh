#!/usr/bin/env bash
# Prints the body of one CHANGELOG.md section (Keep a Changelog format).
#
#   scripts/changelog-notes.sh 1.2.0
#   scripts/changelog-notes.sh Unreleased
set -euo pipefail

SECTION="${1:?usage: $0 <version|Unreleased>}"
SECTION="${SECTION#v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

awk -v section="$SECTION" '
  /^## \[/ {
    if (printing) exit
    heading = $0
    sub(/^## \[/, "", heading); sub(/\].*$/, "", heading)
    if (heading == section) { printing = 1; next }
  }
  printing && /^\[.*\]: http/ { exit }
  printing { print }
' "$ROOT/CHANGELOG.md" | awk 'NF { started = 1 } started' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
