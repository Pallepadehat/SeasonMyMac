#!/bin/zsh
# Makes a release: builds SeasonMyMac.dmg and publishes it as a GitHub release, along with appcast.xml, where the app
# itself finds it (Sparkle) and install.sh does too. The version comes from MARKETING_VERSION in the Xcode project; the
# notes from its section in CHANGELOG.md.
#
# The appcast is signed with the "SeasonMyMac" Sparkle key in your keychain (its public half is SUPublicEDKey in
# Config/Info.plist). Back it up: `generate_keys --account SeasonMyMac -x seasonmymac-sparkle-key.txt`. Without it,
# copies already out there can't update.
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

# The appcast: one entry for this version, signed with our EdDSA key, pointing at this release's disk image.
GENERATE_APPCAST=$(find build/DerivedData/SourcePackages/artifacts -name generate_appcast -type f -perm -u+x | head -1)
[[ -n "$GENERATE_APPCAST" ]] || { echo "Couldn't find Sparkle's generate_appcast. Build once so Swift packages are fetched."; exit 1; }
rm -rf build/appcast
mkdir -p build/appcast
cp build/SeasonMyMac.dmg build/appcast/
"$GENERATE_APPCAST" --account SeasonMyMac \
  --download-url-prefix "https://github.com/Pallepadehat/SeasonMyMac/releases/download/$TAG/" \
  --link "https://github.com/Pallepadehat/SeasonMyMac/releases/tag/$TAG" --maximum-versions 1 build/appcast
[[ -f build/appcast/appcast.xml ]] || { echo "No appcast was made."; exit 1; }

NOTES+=$'\n\n'"### Install"$'\n\n```sh\ncurl -fsSL https://raw.githubusercontent.com/Pallepadehat/SeasonMyMac/main/install.sh | bash\n```'

git tag "$TAG"
git push origin "$TAG"
gh release create "$TAG" build/SeasonMyMac.dmg build/appcast/appcast.xml --title "SeasonMyMac $VERSION" --notes "$NOTES"
echo "Released $TAG. Anyone can now install it with:"
echo "  curl -fsSL https://raw.githubusercontent.com/Pallepadehat/SeasonMyMac/main/install.sh | bash"
