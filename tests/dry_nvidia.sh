#!/usr/bin/env bash
# dry_nvidia.sh — scenario E: GPU_DRIVER=nvidia through the real
# `voidc --auto` pipeline. Verifies that nonfree is enabled automatically,
# the driver packages end up in the single transaction, multilib is handled
# per libc, and `nvidia_drm.modeset=1` lands on the GRUB command line.
# Needs /tmp/stubbin and the /tmp/drysrc copy (tests/run.sh prepares both).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH=/tmp/stubbin:$PATH
export STUB_LOG=/tmp/stub_e.log STUB_MISSING=""
: >"$STUB_LOG"
rm -f /tmp/dry_e.log
rm -f /tmp/fakedisk; : >/tmp/fakedisk
bash "$SELF/mkskel.sh" /tmp/drytarget_e >/dev/null

cat >/tmp/prof_e.conf <<'EOF'
DISK="/tmp/fakedisk"
HOSTNAME="nvidiatest"
USERNAME="nvidiauser"
ROOT_PASS="rootpass"
USER_PASS="userpass"
TIMEZONE="UTC"
KEYMAP="us"
LOCALE="en_US.UTF-8"
DESKTOP="none"
EXTRAS="audio"
GPU_DRIVER="nvidia"
LOGIN_MANAGER="none"
LUKS="no"
SWAP_MB="0"
AUTOSTART_DESKTOP="no"
MIRROR="default"
EOF

LOGFILE=/tmp/dry_e.log STUB_LOG="$STUB_LOG" STUB_MISSING="$STUB_MISSING" \
  bash /tmp/drysrc/voidc --target /tmp/drytarget_e --auto /tmp/prof_e.conf \
  >/tmp/dry_e.out 2>/tmp/dry_e.err
rc=$?

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

E=/tmp/drytarget_e
echo "== scenario E (nvidia driver + GRUB modeset) =="
check "install rc=0 (rc=$rc)"        test "$rc" -eq 0
check "grub cmdline nvidia modeset"  grep -qx 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4 nvidia_drm.modeset=1"' "$E/etc/default/grub"
check "log: nonfree auto-enabled"    grep -q "nvidia selected: nonfree repo enabled" /tmp/dry_e.log
check "target nonfree conf"          test -e "$E/etc/xbps.d/20-repository-nonfree.conf"
if [ "${TEST_ARCH:-x86_64}" = x86_64 ]; then
  check "log: multilib auto-enabled" grep -q "multilib repo enabled automatically" /tmp/dry_e.log
  check "target multilib conf"       test -e "$E/etc/xbps.d/20-repository-multilib.conf"
else
  check "no multilib conf (musl)"    bash -c "! test -e '$E/etc/xbps.d/20-repository-multilib.conf'"
fi
check "no desktop extra conf"        bash -c "! test -e '$E/etc/xbps.d/30-repository-desktop.conf'"
check "driver in transaction"        bash -c "grep 'xbps-install -Sy -y -r /tmp/drytarget_e' '$STUB_LOG' | grep -q nvidia"
check "vulkan in transaction"        bash -c "grep 'xbps-install -Sy -y -r /tmp/drytarget_e' '$STUB_LOG' | grep -q vulkan-tools"
for f in 30-repository-desktop.conf 20-repository-nonfree.conf 20-repository-multilib.conf; do
  if [ -e "/etc/xbps.d/$f" ]; then echo "HOST REPO LEAK: /etc/xbps.d/$f" >&2; rc=1; fi
done
check "host repo confs cleaned"      test "$rc" -eq 0

echo
if [ "$fail" = 0 ]; then echo "SCENARIO E ASSERTIONS PASSED"; else echo "SCENARIO E FAILURES PRESENT"; fi
exit "$fail"
