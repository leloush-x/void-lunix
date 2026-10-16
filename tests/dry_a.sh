#!/usr/bin/env bash
# dry_a.sh — real `voidc --auto` entry point: BIOS + i3 + greetd + autostart.
# Needs /tmp/stubbin (tests/mkstubs.sh) and the /tmp/drysrc sandbox copy
# (tests/run.sh prepares both).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH=/tmp/stubbin:$PATH
export STUB_LOG=/tmp/stub_a.log STUB_MISSING="i3-gaps polkit-gnome matugen"
: >"$STUB_LOG"
rm -f /etc/xbps.d/30-repository-desktop.conf /tmp/dry_a.log
rm -f /tmp/fakedisk; : >/tmp/fakedisk
bash "$SELF/mkskel.sh" /tmp/drytarget >/dev/null

cat >/tmp/prof_a.conf <<'EOF'
DISK="/tmp/fakedisk"
HOSTNAME="voidtest"
USERNAME="void"
ROOT_PASS="rootpass"
USER_PASS="userpass"
TIMEZONE="UTC"
KEYMAP="us"
LOCALE="en_US.UTF-8"
DESKTOP="i3"
SESSION="any"
EXTRAS="audio networking bluetooth printing fonts ssh nonfree multilib"
GPU_DRIVER="auto"
LOGIN_MANAGER="greetd"
LUKS="no"
SWAP_MB="auto"
AUTOSTART_DESKTOP="yes"
MIRROR="default"
EOF

LOGFILE=/tmp/dry_a.log STUB_LOG="$STUB_LOG" STUB_MISSING="$STUB_MISSING" \
  bash /tmp/drysrc/voidc --target /tmp/drytarget --auto /tmp/prof_a.conf
rc=$?
echo "DRY_A_EXIT=$rc"
exit "$rc"
