#!/usr/bin/env bash
# run.sh — sandboxed end-to-end test of the voidc installer pipeline.
#
# No real disks/partitions/system changes: every system-mutating command
# (xbps-*, parted, cryptsetup, chroot, grub, ...) is stubbed in /tmp/stubbin
# and the installs run against throwaway targets under /tmp.
#
#   scenario A: voidc --auto   BIOS + ext4 + i3 + greetd + autostart + extras
#   scenario B: UEFI + LUKS2 + hyprland + greetd (mirrors run_auto())
#   then ~90 assertions + the matugen fallback unit test
#
# Sandbox relaxations (applied to the /tmp/drysrc copy only, never this repo):
#   * [ -b "$DISK" ] -> [ -e "$DISK" ] because containers cannot create
#     device nodes (/tmp/fakedisk is a plain file)
#   * scenario B forces UEFI=yes (no EFI firmware in a container)
#
# Note: enable_host_extra_repo() writes and removes
# /etc/xbps.d/30-repository-desktop.conf on the host — run in a disposable
# container/VM if that matters. Network is used for the mirror/repo probes and
# the matugen fallback; both degrade to warnings when offline.
set -eu
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(dirname "$SELF")"

echo "== sandbox copy -> /tmp/drysrc"
rm -rf /tmp/drysrc
cp -a "$ROOT" /tmp/drysrc
rm -rf /tmp/drysrc/.git
sed -i 's/\[ -b "\$DISK" \]/[ -e "$DISK" ]/' /tmp/drysrc/lib/auto.sh /tmp/drysrc/lib/partition.sh
grep -q '\[ -e "\$DISK" \]' /tmp/drysrc/lib/partition.sh || { echo "sandbox patch failed"; exit 1; }
# scenario A simulates BIOS on (possibly) aarch64 — skip the early firmware guard
sed -i 's/die "BIOS boot is not supported/warnlog "SKIPPED in sandbox: BIOS boot is not supported/' /tmp/drysrc/lib/detect.sh
grep -q 'warnlog "SKIPPED in sandbox: BIOS boot' /tmp/drysrc/lib/detect.sh || { echo "sandbox patch failed (firmware guard)"; exit 1; }

bash "$SELF/mkstubs.sh"

echo "== scenario A: BIOS + i3 (log: /tmp/dry_a.log)"
bash "$SELF/dry_a.sh" >/dev/null || { echo "SCENARIO A FAILED"; exit 1; }
echo "== scenario B: UEFI + LUKS2 + hyprland (log: /tmp/dry_b.log)"
bash "$SELF/dry_b.sh" >/dev/null || { echo "SCENARIO B FAILED"; exit 1; }

echo "== assertions"
bash "$SELF/check_dry.sh" || exit 1

echo "== matugen release-fallback unit test"
bash "$SELF/matugen-fallback.sh" || exit 1

echo
echo "ALL TESTS PASSED"
