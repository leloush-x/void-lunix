#!/usr/bin/env bash
# units.sh — unit tests for logic best pinned down in isolation: the console
# keymap -> XKB translation, the LUKS passphrase re-prompt loop, the host
# repo conf lifecycle (URLs incl. musl, cleanup) and the shipped profiles.
# Temp dirs and function stubs only — host repo confs go to a temp dir via
# HOST_XBPS_DIR, so nothing system-wide is touched.
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SELF/.." && pwd)"

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
LOGFILE="$W/units.log"

# shellcheck disable=SC1090,SC1091
. "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/detect.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/desktop.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/install.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/configure.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/wizard.sh"

# ---------------------------------------------------------------- keymap ----
echo "== keymap -> XKB translation =="
wkm() { # <console keymap>: write console + X configs into the temp target
  KEYMAP="$1"; TIMEZONE=UTC; write_keymap
}
TARGET="$W/km"; mkdir -p "$TARGET/etc"
printf 'KEYMAP="de"\n' >"$TARGET/etc/rc.conf"
XCONF="$TARGET/etc/X11/xorg.conf.d/00-keyboard.conf"
wkm uk
check "console keeps uk"          grep -q 'KEYMAP="uk"' "$TARGET/etc/rc.conf"
check "uk -> XKB gb"              grep -q 'Option "XkbLayout" "gb"' "$XCONF"
wkm de-latin1
check "de-latin1 console kept"    grep -q 'KEYMAP="de-latin1"' "$TARGET/etc/rc.conf"
check "de-latin1 -> XKB de"       grep -q 'Option "XkbLayout" "de"' "$XCONF"
wkm us
check "us -> XKB us"              grep -q 'Option "XkbLayout" "us"' "$XCONF"

# ------------------------------------------------------------- LUKS loop ----
echo "== LUKS passphrase re-prompt loop =="
ui_yesno() { return 0; }        # choose to encrypt
ui_msg()   { :; }
LUKS_STUB="$W/luks_calls"; : >"$LUKS_STUB"
ask_password_twice() {          # two cancels (ESC/short), then a real one
  # step_luks calls this inside $(...) — state must live outside the subshell
  local n
  n=$(( $(cat "$LUKS_STUB" 2>/dev/null || echo 0) + 1 ))
  echo "$n" >"$LUKS_STUB"
  [ "$n" -lt 3 ] && return 1
  printf 'secretpass\n'
}
LUKS=no; LUKS_PASSWORD=""; SWAP_MB=512
step_luks
check "LUKS enabled"              [ "$LUKS" = yes ]
check "passphrase captured"       [ "$LUKS_PASSWORD" = secretpass ]
check "re-prompted then accepted" [ "$(cat "$LUKS_STUB")" = 3 ]
check "swap disabled for LUKS"    [ "$SWAP_MB" = 0 ]

# ----------------------------------------------------------- host repos -----
echo "== host repo conf lifecycle =="
HOST_XBPS_DIR="$W/xbps.d"
MIRROR="https://repo-default.voidlinux.org"
DESKTOP=i3
REPO_SEG=""
XBPS_ARCH=x86_64
EXTRAS="nonfree multilib"
enable_host_extra_repo
check "nonfree URL (glibc)"       grep -qx "repository=https://repo-default.voidlinux.org/current/nonfree" "$HOST_XBPS_DIR/20-repository-nonfree.conf"
check "multilib URL (glibc)"      grep -qx "repository=https://repo-default.voidlinux.org/current/multilib" "$HOST_XBPS_DIR/20-repository-multilib.conf"
check "i3 needs no desktop repo"  bash -c "! test -e '$HOST_XBPS_DIR/30-repository-desktop.conf'"
disable_host_extra_repo
check "cleanup removes both"      bash -c "! test -e '$HOST_XBPS_DIR/20-repository-nonfree.conf' && ! test -e '$HOST_XBPS_DIR/20-repository-multilib.conf'"

REPO_SEG="musl"; XBPS_ARCH="x86_64-musl"; EXTRAS="nonfree multilib"
enable_host_extra_repo
check "nonfree URL (musl)"        grep -qx "repository=https://repo-default.voidlinux.org/current/musl/nonfree" "$HOST_XBPS_DIR/20-repository-nonfree.conf"
check "no multilib conf on musl"  bash -c "! test -e '$HOST_XBPS_DIR/20-repository-multilib.conf'"
disable_host_extra_repo

REPO_SEG=""; XBPS_ARCH="x86_64"; EXTRAS=""; DESKTOP=hyprland
enable_host_extra_repo
check "hyprland repo conf"        grep -q "hyprland-void/repository-x86_64-glibc" "$HOST_XBPS_DIR/30-repository-desktop.conf"
disable_host_extra_repo
check "cleanup removes desktop"   bash -c "! test -e '$HOST_XBPS_DIR/30-repository-desktop.conf'"

# ------------------------------------------------------------- profiles -----
echo "== shipped profiles =="
for p in "$ROOT"/profiles/*.conf; do
  n="$(basename "$p")"
  check "$n parses"    bash -n "$p"
  check "$n has DISK"  grep -q '^DISK=' "$p"
done

echo
if [ "$fail" = 0 ]; then echo "UNIT TESTS PASSED"; else echo "UNIT TEST FAILURES PRESENT"; fi
exit "$fail"
