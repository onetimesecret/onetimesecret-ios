#!/usr/bin/env bash
# Verifies that a version string agrees with Version.swift and CHANGELOG.md.
#
#   scripts/check-version.sh 1.2.0
#
# Exits non-zero with a message pointing at the mismatch. Used by the release
# workflow (against the pushed tag) and by scripts/release.sh.
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: $0 <version>" >&2
  exit 2
fi
VERSION="${VERSION#v}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/Sources/OnetimeSecret/Client/Version.swift"
CHANGELOG="$ROOT/CHANGELOG.md"

SEMVER='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
if ! [[ "$VERSION" =~ $SEMVER ]]; then
  echo "::error::'$VERSION' is not a semantic version (MAJOR.MINOR.PATCH[-pre])" >&2
  exit 1
fi

IN_SOURCE="$(sed -nE 's/.*static let version = "([^"]+)".*/\1/p' "$VERSION_FILE")"
if [ "$IN_SOURCE" != "$VERSION" ]; then
  echo "::error file=Sources/OnetimeSecret/Client/Version.swift::Version.swift says '$IN_SOURCE', expected '$VERSION'" >&2
  exit 1
fi

ESCAPED="$(printf '%s' "$VERSION" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
if ! grep -qE "^## \[$ESCAPED\] - [0-9]{4}-[0-9]{2}-[0-9]{2}" "$CHANGELOG"; then
  echo "::error file=CHANGELOG.md::No '## [$VERSION] - YYYY-MM-DD' heading in CHANGELOG.md" >&2
  exit 1
fi

if [ -n "$("$ROOT/scripts/changelog-notes.sh" Unreleased 2>/dev/null | grep -vE '^[[:space:]]*$' || true)" ]; then
  echo "::warning file=CHANGELOG.md::The Unreleased section is not empty" >&2
fi

echo "Version $VERSION is consistent across Version.swift and CHANGELOG.md"
