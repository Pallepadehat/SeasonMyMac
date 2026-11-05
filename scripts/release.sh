#!/bin/zsh
# Makes a release: builds SeasonMyMac.dmg and publishes it as a GitHub release, where install.sh finds it. The
# version comes from MARKETING_VERSION in the Xcode project; the notes from its section in CHANGELOG.md.
#
#   ./scripts/release.sh                       signed with Developer ID and notarized by Apple
#   ./scripts/release.sh --without-notarizing  signed with Developer ID if you have it (otherwise your Apple
#                                              Development certificate), not notarized. install.sh still opens it
#                                              without a warning.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project SeasonMyMac.xcodeproj -scheme SeasonMyMac -showBuildSettings 2>/dev/null \
  | sed -nE 's/^[[:space:]]*MARKETING_VERSION = (.*)$/\1/p' | head -1)
[[ -n "$VERSION" ]] || { echo "Couldn't read MARKETING_VERSION from the project."; exit 1; }
TAG="v$VERSION"

[[ -z "$(git status --porcelain)" ]] || { echo "Commit or stash your changes first, so the release matches the code."; exit 1; }
git fetch --tags --quiet
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "$TAG already exists. Bump MARKETING_VERSION in the project first."
  exit 1
fi

# This version's section of CHANGELOG.md becomes the release notes.
# It ends at the next version's heading or at the link references at the bottom.
NOTES=$(awk -v version="$VERSION" '
  /^## / { if (found) exit; if (index($0, "[" version "]")) { found = 1; next } }
  /^\[[^]]+\]: / { if (found) exit }
  found { print }
' CHANGELOG.md)
[[ -n "$NOTES" ]] || { echo "Add a \"## [$VERSION]\" section to CHANGELOG.md first."; exit 1; }

if [[ "${1:-}" == "--without-notarizing" ]]; then
  if [[ "$(security find-identity -v -p codesigning)" == *'"Developer ID Application'* ]]; then
    ./scripts/make-dmg.sh --sign
  else
    ./scripts/make-dmg.sh
  fi
  NOTES+=$'\n\n'"> This build isn't notarized by Apple yet. Install it with the one-liner below, which handles that. If you download the .dmg yourself, see the README for opening it the first time."
else
  ./scripts/make-dmg.sh --notarize
fi

NOTES+=$'\n\n'"### Install"$'\n\n```sh\ncurl -fsSL https://raw.githubusercontent.com/Pallepadehat/SeasonMyMac/main/install.sh | bash\n```'

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/SeasonMyMac.dmg --title "SeasonMyMac $VERSION" --notes "$NOTES"
echo "Released $TAG. Anyone can now install it with:"
echo "  curl -fsSL https://raw.githubusercontent.com/Pallepadehat/SeasonMyMac/main/install.sh | bash"
