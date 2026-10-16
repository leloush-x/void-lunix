#!/usr/bin/env bash
# fs-matrix.sh — unit test for the root-filesystem matrix (ext4/btrfs/xfs/f2fs),
# no install involved: lib/partition.sh is sourced with tiny stubs and checked
# for (a) the exact mkfs command per filesystem, (b) the tool-missing hint,
# (c) the generated fstab — root passno (0 for btrfs/xfs/f2fs, 1 for ext4),
# the tmpfs /tmp line, and the swap line only when a swap device is set.
set -u
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
same() { # <desc> <got> <want>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got: $2)"; fi
}

# fake mkfs tools so `command -v` succeeds on any host
BIN=/tmp/fsbin
rm -rf "$BIN"; mkdir -p "$BIN"
for t in mkfs.ext4 mkfs.btrfs mkfs.xfs mkfs.f2fs; do
  printf '#!/bin/sh\nexit 0\n' >"$BIN/$t"; chmod 0755 "$BIN/$t"
done
export PATH="$BIN:$PATH"

BASH_BIN="$(command -v bash)"
mkfs_for() { # <fs> -> the mkfs command mkfs_root would run
  FILESYSTEM="$1" ROOTDEV_FS=/dev/fakepart ROOT="$ROOT" "$BASH_BIN" -c '
    set -u
    run()  { shift; printf "%s\n" "$*"; }
    try()  { :; }
    verb() { :; }
    die()  { echo "DIE: $*"; exit 1; }
    . "$ROOT/lib/partition.sh"
    mkfs_root
  '
}

FSTAB_OUT=/tmp/fsmatrix.fstab
fstab_for() { # <fs> [swapdev] -> writes the generated fstab to $FSTAB_OUT
  local t; t="$(mktemp -d)"; mkdir -p "$t/etc"
  TARGET="$t" FILESYSTEM="$1" SWAPDEV="${2:-}" ROOTDEV_FS=/dev/fakepart ROOT="$ROOT" "$BASH_BIN" -c '
    set -u
    uuid_of() { printf "uuid-%s\n" "$1"; }
    run()  { :; }
    try()  { :; }
    verb() { :; }
    die()  { echo "DIE: $*"; exit 1; }
    LOGFILE=/dev/null
    . "$ROOT/lib/partition.sh"
    write_fstab
  '
  cp "$t/etc/fstab" "$FSTAB_OUT"
  rm -rf "$t"
}

echo "== mkfs command per filesystem =="
same "mkfs ext4"  "$(mkfs_for ext4)"  "mkfs.ext4 -q -L voidroot /dev/fakepart"
same "mkfs btrfs" "$(mkfs_for btrfs)" "mkfs.btrfs -f -L voidroot /dev/fakepart"
same "mkfs xfs"   "$(mkfs_for xfs)"   "mkfs.xfs -f -i sparse=0 -L voidroot /dev/fakepart"
same "mkfs f2fs"  "$(mkfs_for f2fs)"  "mkfs.f2fs -f -l voidroot /dev/fakepart"
same "unsupported fs dies" "$(mkfs_for vfat)" "DIE: Unsupported filesystem: vfat"

out="$(PATH='' FILESYSTEM=f2fs ROOTDEV_FS=/dev/fakepart ROOT="$ROOT" "$BASH_BIN" -c '
  set -u
  run()  { :; }
  try()  { :; }
  verb() { :; }
  die()  { echo "DIE: $*"; exit 1; }
  . "$ROOT/lib/partition.sh"
  mkfs_root
')"
case "$out" in
  *"xbps-install -Sy f2fs-tools"*) ok "missing-tool hint names the package" ;;
  *) bad "missing-tool hint (got: $out)" ;;
esac

echo "== generated fstab =="
fstab_for ext4 /dev/fakeswap
check "fstab root ext4 passno 1" grep -qF "$(printf 'UUID=uuid-/dev/fakepart\t/\t\text4\tdefaults,noatime\t0 1')" "$FSTAB_OUT"
check "fstab swap line"          grep -qF "$(printf 'UUID=uuid-/dev/fakeswap\tnone\t\tswap\tsw\t0 0')" "$FSTAB_OUT"
check "fstab tmpfs /tmp"         grep -qF "$(printf 'tmpfs\t/tmp\ttmpfs\tdefaults,nosuid,nodev\t0 0')" "$FSTAB_OUT"

fstab_for btrfs
check "fstab root btrfs passno 0" grep -qF "$(printf 'UUID=uuid-/dev/fakepart\t/\t\tbtrfs\tdefaults,noatime\t0 0')" "$FSTAB_OUT"
check "no swap line when unset"   bash -c "! grep -q fakeswap '$FSTAB_OUT'"

fstab_for xfs /dev/fakeswap
check "fstab root xfs passno 0"  grep -qF "$(printf 'UUID=uuid-/dev/fakepart\t/\t\txfs\tdefaults,noatime\t0 0')" "$FSTAB_OUT"

fstab_for f2fs /dev/fakeswap
check "fstab root f2fs passno 0" grep -qF "$(printf 'UUID=uuid-/dev/fakepart\t/\t\tf2fs\tdefaults,noatime\t0 0')" "$FSTAB_OUT"

echo
if [ "$fail" = 0 ]; then echo "FS MATRIX TESTS PASSED"; else echo "FS MATRIX FAILURES"; fi
exit "$fail"
