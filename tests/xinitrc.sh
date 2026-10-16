#!/usr/bin/env bash
# xinitrc.sh — unit test: ~/.xinitrc is written for plain X desktops
# (dwm/openbox/awesome/qtile/xfce/... — no rice preset) so `startx` doesn't
# fall back to the default twm/xterm session. Pure function test, no system
# changes (chroot_run/verb are stubbed).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SELF/.." && pwd)"

verb() { :; }
chroot_run() { :; }
# shellcheck disable=SC1091
. "$ROOT/lib/desktop.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/rice.sh"

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
TARGET="$W"
USERNAME="tester"
mkdir -p "$W/home/$USERNAME"

gen() { rm -f "$W/home/$USERNAME/.xinitrc"; DESKTOP="$1" ensure_xinitrc; }
X="$W/home/$USERNAME/.xinitrc"

echo "== xinitrc unit tests =="
gen dwm;     check "dwm .xinitrc"           grep -q "exec dbus-run-session -- dwm" "$X"
gen openbox; check "openbox .xinitrc"       grep -q "exec dbus-run-session -- openbox-session" "$X"
gen awesome; check "awesome .xinitrc"       grep -q "exec dbus-run-session -- awesome" "$X"
gen qtile;   check "qtile .xinitrc"         grep -q "exec dbus-run-session -- qtile start" "$X"
gen xfce;    check "xfce .xinitrc"          grep -q "exec dbus-run-session -- startxfce4" "$X"
gen dwm;     check "xinitrc is executable"  test -x "$X"
gen sway;    check "no .xinitrc (wayland)"  bash -c "! test -e '$X'"
printf 'keep\n' >"$X"
DESKTOP=i3 ensure_xinitrc
check "existing .xinitrc kept" grep -qx "keep" "$X"

echo
if [ "$fail" = 0 ]; then echo "XINITRC UNIT TESTS PASSED"; else echo "XINITRC UNIT FAILURES PRESENT"; fi
exit "$fail"
