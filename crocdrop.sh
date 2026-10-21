#!/usr/bin/env bash

VER="11.5.5"
BASE="https://github.com/schollz/croc/releases/download/v${VER}"

MODE="$1"
CODE="$2"
if [ $# -ge 2 ]; then shift 2; else shift $#; fi

say() { printf '%s\n' "$*"; }
die() { say ""; say "Sorry, something went wrong: $*"; exit 1; }

sum_for() {
  case "$1" in
    macOS-ARM64) echo "44dce75f98e29cbcb1f4239e1e493ef337c8013a7be48517eb21eced771bffaa" ;;
    macOS-64bit) echo "7a008d61dd7f7da02b42344057ba46ad810be7252f33b2fafebec8f48060c4ec" ;;
    Linux-64bit) echo "2dee9b7ede849971532c597ef3fd29507bfc970330758cfed13657be04f34243" ;;
    Linux-ARM64) echo "c8606c6b4450e4a50b3ef25bd486ed4f9fa4a1ac6e2ecefb2bcbdbbfce1a51a9" ;;
    Linux-32bit) echo "43a80c0da9c1aec75bb14e418cee487aab1d02ac3257ef34d6f98ea29c4d5ab0" ;;
    Linux-ARM) echo "a729adefe57a249d0be53c3baf5748040973cee6971245508acc8e1795dbd6e1" ;;
  esac
}

pick_asset() {
  case "$(uname -s)" in
    Darwin)
      case "$(uname -m)" in
        arm64) ASSET="macOS-ARM64" ;;
        x86_64) ASSET="macOS-64bit" ;;
      esac ;;
    Linux)
      case "$(uname -m)" in
        x86_64|amd64) ASSET="Linux-64bit" ;;
        aarch64|arm64) ASSET="Linux-ARM64" ;;
        i386|i686) ASSET="Linux-32bit" ;;
        armv7l|armv6l) ASSET="Linux-ARM" ;;
      esac ;;
  esac
}

file_sum() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

SB=""
KEEP=0
cleanup() {
  if [ -n "$SB" ] && [ "$KEEP" -eq 0 ]; then rm -rf "$SB"; fi
}
trap cleanup EXIT
trap 'say ""; say "Stopped. Run the same command again any time to resume."; exit 130' INT TERM

case "$MODE" in
  send|receive) ;;
  *) die "unknown mode" ;;
esac

if [ -z "$CODE" ] || [ "${#CODE}" -lt 6 ]; then die "missing or short code"; fi

pick_asset
[ -n "$ASSET" ] || die "this computer type is not supported"

SB="$(mktemp -d "${TMPDIR:-/tmp}/crocdrop.XXXXXX")" || die "could not create a temporary folder"
mkdir -p "$SB/home" "$SB/cfg"

say ""
say "CrocDrop"
say "Getting ready (one-time download, about 9 MB)..."

ARCHIVE="$SB/croc.tar.gz"
curl -fsSL "${BASE}/croc_v${VER}_${ASSET}.tar.gz" -o "$ARCHIVE" || die "download failed, check your internet"

[ "$(file_sum "$ARCHIVE")" = "$(sum_for "$ASSET")" ] || die "download did not pass the safety check"

mkdir -p "$SB/bin"
tar -xzf "$ARCHIVE" -C "$SB/bin" || die "could not unpack"
CROC="$SB/bin/croc"
chmod +x "$CROC"

EXTRA=($CROCDROP_FLAGS)
SEND_EXTRA=($CROCDROP_SEND_FLAGS)

INHIBIT=()
if [ "$(uname -s)" = "Darwin" ]; then
  INHIBIT=(caffeinate -i)
elif command -v systemd-inhibit >/dev/null 2>&1 && systemd-inhibit --what=idle:sleep true >/dev/null 2>&1; then
  INHIBIT=(systemd-inhibit --what=idle:sleep --why=CrocDrop)
fi

pick_folder() {
  if [ "$(uname -s)" = "Darwin" ]; then
    osascript -e 'tell me to activate' -e 'POSIX path of (choose folder with prompt "Choose the folder to send")' 2>/dev/null
  elif command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --directory --title="Choose the folder to send" 2>/dev/null
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --getexistingdirectory "$HOME" 2>/dev/null
  fi
}

open_folder() {
  if [ "$(uname -s)" = "Darwin" ]; then open "$1" >/dev/null 2>&1
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$1" >/dev/null 2>&1
  fi
}

retry_note() {
  say ""
  say "Waiting to connect. Keep this window open. (Press Ctrl+C to stop)"
  sleep 5
}

if [ "$MODE" = "send" ]; then
  ITEMS=()
  if [ $# -gt 0 ]; then
    ITEMS=("$@")
  else
    while true; do
      say ""
      say "Drag the files or folder you want to send into this window,"
      say "then press Enter. (Or just press Enter to browse.)"
      printf '> '
      read -r LINE
      if [ -z "$LINE" ]; then
        PICKED="$(pick_folder)"
        if [ -z "$PICKED" ]; then say "Nothing chosen."; continue; fi
        ITEMS=("$PICKED")
      else
        eval "ITEMS=($LINE)" 2>/dev/null || { say "Could not read that, try again."; continue; }
      fi
      BAD=0
      for P in "${ITEMS[@]}"; do
        if [ ! -e "$P" ]; then say "Cannot find: $P"; BAD=1; fi
      done
      [ "$BAD" -eq 0 ] && [ "${#ITEMS[@]}" -gt 0 ] && break
    done
  fi

  say ""
  say "Waiting for your friend to connect. Keep this window open."
  while true; do
    env HOME="$SB/home" XDG_CONFIG_HOME="$SB/cfg" CROC_SECRET="$CODE" "${INHIBIT[@]}" "$CROC" --ignore-stdin --disable-clipboard "${EXTRA[@]}" send "${SEND_EXTRA[@]}" "${ITEMS[@]}" && break
    retry_note
  done
  DONE_MSG="All done. Your files were sent."
else
  DEST="$1"
  if [ -z "$DEST" ]; then
    if [ "$PWD" != "$HOME" ] && [ "$PWD" != "/" ]; then DEST="$PWD"; else DEST="$HOME/Downloads/CrocDrop"; fi
  fi
  mkdir -p "$DEST" || die "could not create $DEST"
  say ""
  say "Files will be saved to: $DEST"
  say "Waiting for your friend to send. Keep this window open."
  while true; do
    env HOME="$SB/home" XDG_CONFIG_HOME="$SB/cfg" CROC_SECRET="$CODE" "${INHIBIT[@]}" "$CROC" --yes --overwrite --disable-clipboard "${EXTRA[@]}" --out "$DEST" && break
    retry_note
  done
  DONE_MSG="All done. Your files are in: $DEST"
  open_folder "$DEST"
fi

say ""
say "$DONE_MSG"
say ""
printf 'Your transferred files are safe and will not be touched.\nClean up the small helper program CrocDrop used? Press Enter for yes, or type n to keep it: '
read -r ANSWER
case "$ANSWER" in
  n|N|no|NO) KEEP=1; say "Helper program kept at: $SB" ;;
  *) say "Cleaned up. Your transferred files were not touched." ;;
esac
