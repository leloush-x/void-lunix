#!/usr/bin/env bash
# dry_fail.sh — scenario D: a critical package missing from the repositories
# (here: grub) must abort the install BEFORE the disk is touched, and the
# live-system repo confs voidc added must be cleaned up on the abort path.
# Needs /tmp/stubbin (tests/mkstubs.sh) and the /tmp/drysrc sandbox copy
# (tests/run.sh prepares both).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
export PATH=/tmp/stubbin:$PATH
export STUB_LOG=/tmp/stub_f.log STUB_MISSING="grub"
: >"$STUB_LOG"
rm -f /tmp/dry_fail.log
rm -f /tmp/fakedisk; : >/tmp/fakedisk

# nothing voidc added to the live system may survive scenarios A/B/C
for f in 30-repository-desktop.conf 20-repository-nonfree.conf 20-repository-multilib.conf; do
  if [ -e "/etc/xbps.d/$f" ]; then echo "HOST REPO LEAK BEFORE D: /etc/xbps.d/$f"; exit 1; fi
done

cat >/tmp/prof_f.conf <<'EOF'
DISK="/tmp/fakedisk"
HOSTNAME="failtest"
USERNAME="failuser"
ROOT_PASS="rootpass"
USER_PASS="userpass"
TIMEZONE="UTC"
KEYMAP="us"
LOCALE="en_US.UTF-8"
DESKTOP="none"
EXTRAS="nonfree"
GPU_DRIVER="auto"
LOGIN_MANAGER="none"
LUKS="no"
SWAP_MB="0"
AUTOSTART_DESKTOP="no"
MIRROR="default"
EOF

LOGFILE=/tmp/dry_fail.log STUB_LOG="$STUB_LOG" STUB_MISSING="$STUB_MISSING" \
  bash /tmp/drysrc/voidc --target /tmp/drytarget_f --auto /tmp/prof_f.conf \
  >/tmp/dry_fail.out 2>/tmp/dry_fail.err
rc=$?

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== scenario D (missing critical package must abort early) =="
check "install aborted (rc=$rc)"   test "$rc" -ne 0
check "log names package"          grep -q "Critical package 'grub'" /tmp/dry_fail.log
check "disk untouched (no parted)" bash -c "! grep -q 'mklabel gpt' '$STUB_LOG'"
check "no install transaction"     bash -c "! grep -q 'xbps-install -Sy -y -r' '$STUB_LOG'"
check "host nonfree conf removed"  bash -c "! test -e /etc/xbps.d/20-repository-nonfree.conf"

echo
if [ "$fail" = 0 ]; then echo "SCENARIO D ASSERTIONS PASSED"; else echo "SCENARIO D FAILURES PRESENT"; fi
exit "$fail"
