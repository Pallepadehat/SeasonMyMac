#!/bin/bash
# Installs SeasonMyMac: snow and holiday lights for your Mac's desktop.
#
#   curl -fsSL https://raw.githubusercontent.com/Pallepadehat/SeasonMyMac/main/install.sh | bash
#
# It downloads the latest SeasonMyMac.dmg from GitHub Releases, puts the app in /Applications (replacing an older
# copy) and opens it. It also clears the "downloaded from the internet" flag, so a release that isn't notarized by
# Apple yet still opens without a warning.
#
# Options (after `bash -s --` when piping):
#   path/to/SeasonMyMac.dmg   install from a .dmg you already have instead of downloading
#   --no-open                 don't open the app afterwards
#
# SEASONMYMAC_INSTALL_DIR overrides /Applications; SEASONMYMAC_DMG_URL overrides where the .dmg comes from.
#
# Everything runs inside main(), so a download cut off half way can't run half a script.

set -euo pipefail

# Global, not local to main(): the clean-up below runs after main() has returned.
tmp=""

say() { printf '\033[1m❄️  %s\033[0m\n' "$*"; }
die() { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

main() {
  local repo="Pallepadehat/SeasonMyMac"
  local url="${SEASONMYMAC_DMG_URL:-https://github.com/${repo}/releases/latest/download/SeasonMyMac.dmg}"
  local dest="${SEASONMYMAC_INSTALL_DIR:-/Applications}"
  local app="SeasonMyMac.app"
  local process="SeasonMyMac"
  local bundle_id="com.pallepadehat.SeasonMyMac"
  local open_after=1 dmg=""

  for arg in "$@"; do
    case "${arg}" in
      --no-open) open_after=0 ;;
      -h | --help) sed -n '2,16p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *.dmg) dmg="${arg}" ;;
      *) die "Unknown option: ${arg}" ;;
    esac
  done

  [[ "$(uname -s)" == "Darwin" ]] || die "SeasonMyMac is a Mac app."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 14 )) || die "SeasonMyMac needs macOS 14 or later (you have $(sw_vers -productVersion))."

  tmp="$(mktemp -d)"
  # Clean up however it ends, keeping the real exit status.
  trap 'status=$?; hdiutil detach "$tmp/mount" -quiet -force >/dev/null 2>&1 || true; rm -rf "$tmp"; exit $status' EXIT

  if [[ -z "${dmg}" ]]; then
    say "Downloading SeasonMyMac…"
    curl -fL --progress-bar "${url}" -o "$tmp/SeasonMyMac.dmg" \
      || die "Couldn't download ${url}. Is there a release with SeasonMyMac.dmg attached?"
    dmg="$tmp/SeasonMyMac.dmg"
  fi
  [[ -f "${dmg}" ]] || die "No such file: ${dmg}"

  hdiutil attach "${dmg}" -nobrowse -readonly -noautoopen -mountpoint "$tmp/mount" -quiet \
    || die "Couldn't open the disk image."
  [[ -d "$tmp/mount/${app}" ]] || die "The disk image doesn't have ${app} in it."

  # A running copy has to quit before the new one moves in.
  if pgrep -x "${process}" >/dev/null; then
    say "Quitting the running copy…"
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x "${process}" >/dev/null || break; sleep 0.5; done
    pkill -x "${process}" 2>/dev/null || true
  fi

  say "Installing to ${dest}…"
  # Runs as you, or with sudo when the folder isn't yours to write (an empty array trips bash 3.2's `set -u`).
  local use_sudo=""
  if [[ -e "${dest}/${app}" && ! -w "${dest}/${app}" ]] || { [[ -d "${dest}" ]] && [[ ! -w "${dest}" ]]; }; then
    say "${dest} needs your password."
    use_sudo=1
  fi
  run() { if [[ -n "$use_sudo" ]]; then sudo "$@"; else "$@"; fi; }
  run mkdir -p "${dest}"
  run rm -rf "${dest}/${app}"
  run ditto "$tmp/mount/${app}" "${dest}/${app}"
  # A disk image made without notarization would be blocked while it carries the download flag.
  run xattr -dr com.apple.quarantine "${dest}/${app}" 2>/dev/null || true

  say "SeasonMyMac is installed in ${dest}. Let it snow!"
  if (( open_after )); then
    open "${dest}/${app}"
    say "Look for the ❄︎ in your menu bar. Allow Accessibility access when asked, so snow and lights fit the Dock."
  fi
}

main "$@"
