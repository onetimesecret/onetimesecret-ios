#!/usr/bin/env bash
# Release helper. Two steps, matching a protected main branch:
#
#   scripts/release.sh prepare 1.2.0   # branch, bump, changelog, commit -> open a PR
#   scripts/release.sh tag 1.2.0       # after the PR merged: tag main and push
#
# Pushing the tag triggers .github/workflows/release.yml, which re-verifies,
# runs CI and creates the GitHub release. See RELEASING.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
  exit 2
}

COMMAND="${1:-}"
VERSION="${2:-}"
[ -n "$COMMAND" ] && [ -n "$VERSION" ] || usage
VERSION="${VERSION#v}"
TAG="v$VERSION"
TODAY="$(date -u +%Y-%m-%d)"
VERSION_FILE="Sources/OnetimeSecret/Client/Version.swift"

require_clean_tree() {
  if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is not clean" >&2
    exit 1
  fi
}

case "$COMMAND" in
  prepare)
    require_clean_tree
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
      echo "error: tag $TAG already exists" >&2
      exit 1
    fi
    if [ -z "$(scripts/changelog-notes.sh Unreleased | grep -vE '^[[:space:]]*$' || true)" ]; then
      echo "error: CHANGELOG.md has nothing under Unreleased. Write the notes first." >&2
      exit 1
    fi

    git fetch --quiet origin main
    git switch -c "release/$TAG" origin/main

    # Version.swift
    sed -i.bak -E "s/(static let version = \")[^\"]+(\")/\1$VERSION\2/" "$VERSION_FILE"
    rm -f "$VERSION_FILE.bak"

    # CHANGELOG: promote Unreleased, refresh compare links.
    REPO_URL="$(git remote get-url origin | sed -E 's#^git@github.com:#https://github.com/#; s#\.git$##')"
    PREVIOUS="$(git tag --list 'v*' --sort=-v:refname | head -n 1)"
    python3 - "$VERSION" "$TODAY" "$REPO_URL" "$PREVIOUS" <<'PY'
import re, sys
version, today, repo, previous = sys.argv[1:5]
path = "CHANGELOG.md"
text = open(path).read()
text = text.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{version}] - {today}", 1)
# Link references at the bottom.
text = re.sub(r"^\[Unreleased\]: .*$", f"[Unreleased]: {repo}/compare/v{version}...HEAD", text, flags=re.M)
compare = f"{repo}/compare/{previous}...v{version}" if previous else f"{repo}/releases/tag/v{version}"
if f"[{version}]:" not in text:
    text = re.sub(r"(^\[Unreleased\]: .*$)", rf"\1\n[{version}]: {compare}", text, count=1, flags=re.M)
open(path, "w").write(text)
PY

    scripts/check-version.sh "$VERSION"
    git add "$VERSION_FILE" CHANGELOG.md
    git commit -m "Release $TAG"
    echo
    echo "Prepared release/$TAG. Next:"
    echo "  git push -u origin release/$TAG"
    echo "  gh pr create --fill --title 'Release $TAG'"
    echo "After the PR is merged:  scripts/release.sh tag $VERSION"
    ;;

  tag)
    require_clean_tree
    git fetch --quiet origin main --tags
    git switch --quiet main
    git merge --ff-only --quiet origin/main
    scripts/check-version.sh "$VERSION"
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
      echo "error: tag $TAG already exists locally" >&2
      exit 1
    fi
    NOTES="$(scripts/changelog-notes.sh "$VERSION")"
    # verbatim: Keep a Changelog headings start with '#', which git would
    # otherwise strip as comments.
    git tag -a "$TAG" --cleanup=verbatim -m "$TAG" -m "$NOTES"
    echo "Tagged $(git rev-parse --short HEAD) as $TAG."
    read -r -p "Push the tag and start the release workflow? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      git push origin "$TAG"
      echo "Pushed. Watch: gh run watch --workflow release.yml"
    else
      echo "Not pushed. When ready: git push origin $TAG"
    fi
    ;;

  *)
    usage
    ;;
esac
