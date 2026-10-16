#!/usr/bin/env bash
# dry_b.sh — UEFI + LUKS2 + hyprland + greetd.
# Mirrors run_auto(); UEFI is forced to yes because the sandbox has no EFI
# firmware, and the target block-device guard is relaxed in the /tmp/drysrc
# copy only (containers cannot create device nodes) — everything else is the
# real code. Needs /tmp/stubbin (tests/mkstubs.sh).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
cd /tmp/drysrc || exit 1
export VOIDC_DIR=/tmp/drysrc VOIDC_VERSION=test LOGFILE=/tmp/dry_b.log
export STUB_LOG=/tmp/stub_b.log STUB_MISSING="hyprlock"
: >"$STUB_LOG"; : >"$LOGFILE"
export PATH=/tmp/stubbin:$PATH
rm -f /etc/xbps.d/30-repository-desktop.conf /etc/xbps.d/20-repository-nonfree.conf \
      /etc/xbps.d/20-repository-multilib.conf
rm -f /tmp/fakedisk; : >/tmp/fakedisk
bash "$SELF/mkskel.sh" /tmp/drytarget_b >/dev/null

. lib/common.sh
. lib/detect.sh
. lib/desktop.sh
. lib/install.sh
. lib/partition.sh
. lib/configure.sh
. lib/boot.sh
. lib/rice.sh
. lib/rice-wayland.sh
. lib/auto.sh

NO_DIALOG=yes
TARGET=/tmp/drytarget_b; export TARGET
DISK=/tmp/fakedisk
HOSTNAME=voidtest
USERNAME=void
ROOT_PASS=rootpass
USER_PASS=userpass
TIMEZONE=UTC; KEYMAP=us; LOCALE=en_US.UTF-8
DESKTOP=hyprland; SESSION=wayland
EXTRAS="audio networking fonts nonfree"
GPU_DRIVER=auto
LOGIN_MANAGER=greetd
LUKS=yes; LUKS_PASSWORD=testpass
SWAP_MB=auto
AUTOSTART_DESKTOP=no
MIRROR="https://repo-default.voidlinux.org"
DOTFILES_URL=""; RUN_DOTFILES_INSTALL=no

detect_environment
UEFI=yes   # sandbox has no EFI firmware; simulate UEFI hardware
auto_defaults
auto_validate

say "DRY-B: $DISK -> $FILESYSTEM desktop=$DESKTOP uefi=$UEFI luks=$LUKS swap=${SWAP_MB}MB"
enable_host_extra_repo
resolve_pkgs
partition_disk
format_partitions
mount_target
prepare_target
install_packages
mount_chroot
write_fstab
configure_system
finalize_system
install_bootloader
desktop_setup
run "Saving install log" cp "$LOGFILE" "$TARGET/var/log/voidc-install.log"
disable_host_extra_repo
for f in 30-repository-desktop.conf 20-repository-nonfree.conf 20-repository-multilib.conf; do
  if [ -e "/etc/xbps.d/$f" ]; then echo "HOST REPO LEAK: /etc/xbps.d/$f" >&2; exit 1; fi
done
sync
echo "DRY_B_REACHED_END"
