#!/usr/bin/env bash
# smoke.sh — CLI surface: --version/--help exit cleanly and print the right
# things, unknown flags fail loudly, and --check produces the environment
# report without touching anything. Uses the /tmp/drysrc copy and the
# /tmp/stubbin stubs (tests/run.sh prepares both).
set -u
export PATH=/tmp/stubbin:$PATH
V=/tmp/drysrc/voidc
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
export LOGFILE="$W/smoke.log"

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== CLI smoke tests =="
bash "$V" --version >"$W/version.out" 2>&1; vrc=$?
check "--version exits 0"           test "$vrc" -eq 0
check "--version prints name"       grep -q '^voidc ' "$W/version.out"
bash "$V" --help >"$W/help.out" 2>&1; hrc=$?
check "--help exits 0"              test "$hrc" -eq 0
check "--help lists --auto"         grep -q -- "--auto" "$W/help.out"
check "--help lists --check"        grep -q -- "--check" "$W/help.out"
bash "$V" --bogus >/dev/null 2>&1; brc=$?
check "unknown flag exits non-zero" test "$brc" -ne 0
bash "$V" --check >"$W/check.out" 2>&1; crc=$?
check "--check exits 0"             test "$crc" -eq 0
check "--check reports arch"        grep -q 'arch/libc:' "$W/check.out"
check "--check reports disks"       grep -q 'disks:' "$W/check.out"
check "--check reports mirror"      grep -q 'default mirror:' "$W/check.out"

echo
if [ "$fail" = 0 ]; then echo "SMOKE TESTS PASSED"; else echo "SMOKE TEST FAILURES PRESENT"; fi
exit "$fail"
