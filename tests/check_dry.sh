#!/usr/bin/env bash
# check_dry.sh — assertions over the two dry-run results.
# Expectations adapt to the running machine (uname -m + musl loader), matching
# what lib/detect.sh computes when xbps-uhelper is unavailable/stubbed.
ARCH="$(uname -m)"
LIBC=glibc
if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
  LIBC=musl
  case "$ARCH" in *musl*) ;; *) ARCH="${ARCH}-musl" ;; esac
fi
case "$ARCH" in
  x86_64)      REPO_SEG="" ;;
  x86_64-musl) REPO_SEG="musl" ;;
  *)           REPO_SEG="${ARCH%%-musl}" ;;
esac
MAIN_PATH="current"; [ -n "$REPO_SEG" ] && MAIN_PATH="current/$REPO_SEG"
EXTRA_ARCH="${ARCH%-musl}"
case "$ARCH" in
  aarch64*) GRUB_TGT="arm64-efi";  GRUB_PKG="grub-arm64-efi" ;;
  *)        GRUB_TGT="x86_64-efi"; GRUB_PKG="grub-x86_64-efi" ;;
esac

fail=0
A=/tmp/drytarget
B=/tmp/drytarget_b
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
check_line() { # <desc> <file> <expected line>
  local d="$1" f="$2" want="$3" got
  got="$(cat "$f" 2>/dev/null)"
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (got: $got)"; fi
}

echo "== scenario A (BIOS + i3 + greetd + autostart) =="
check "hostname"                 grep -qx "voidtest" "$A/etc/hostname"
check "sudoers wheel"            grep -q "%wheel" "$A/etc/sudoers.d/10-wheel"
check "bash_profile autostart"   grep -q "exec startx" "$A/home/void/.bash_profile"
check "fstab root UUID+ext4"     grep -q "^UUID=aaaaaaaa" "$A/etc/fstab"
check "fstab ext4"               grep -q "ext4" "$A/etc/fstab"
check "fstab /boot"              grep -q "/boot" "$A/etc/fstab"
check "fstab swap"               grep -q "swap" "$A/etc/fstab"
check "fstab no efi (BIOS)"      bash -c "! grep -q efi '$A/etc/fstab'"
check_line "main repo conf" "$A/etc/xbps.d/00-repository-main.conf" \
  "repository=https://repo-default.voidlinux.org/$MAIN_PATH"
check "nonfree repo conf"        grep -q "nonfree" "$A/etc/xbps.d/20-repository-nonfree.conf"
if [ "$ARCH" = x86_64 ]; then
  check "multilib repo conf"     grep -q "multilib" "$A/etc/xbps.d/20-repository-multilib.conf"
else
  check "multilib skipped ($ARCH)" bash -c "! test -e '$A/etc/xbps.d/20-repository-multilib.conf'"
fi
check "no desktop extra conf"    bash -c "! test -e '$A/etc/xbps.d/30-repository-desktop.conf'"
check "locale.conf"              grep -q "LANG=en_US.UTF-8" "$A/etc/locale.conf"
check "rc.conf keymap"           grep -q 'KEYMAP="us"' "$A/etc/rc.conf"
check "X keyboard conf"          test -s "$A/etc/X11/xorg.conf.d/00-keyboard.conf"
check "pipewire drop-in 1"       test -L "$A/etc/pipewire/pipewire.conf.d/10-wireplumber.conf"
check "pipewire drop-in 2"       test -L "$A/etc/pipewire/pipewire.conf.d/20-pipewire-pulse.conf"
check "xdg autostart"            test -L "$A/etc/xdg/autostart/pipewire.desktop"
check "svc dbus enabled"         test -L "$A/etc/runit/runsvdir/default/dbus"
check "svc elogind enabled"      test -L "$A/etc/runit/runsvdir/default/elogind"
check "svc NetworkManager"       test -L "$A/etc/runit/runsvdir/default/NetworkManager"
check "svc sshd"                 test -L "$A/etc/runit/runsvdir/default/sshd"
check "svc bluetoothd"           test -L "$A/etc/runit/runsvdir/default/bluetoothd"
check "svc cupsd"                test -L "$A/etc/runit/runsvdir/default/cupsd"
check "svc chronyd"              test -L "$A/etc/runit/runsvdir/default/chronyd"
check "svc rtkit"                test -L "$A/etc/runit/runsvdir/default/rtkit"
check "svc greetd"               test -L "$A/etc/runit/runsvdir/default/greetd"
check "greetd wrapper (startx)"  grep -q "dbus-run-session -- startx" "$A/usr/local/bin/voidc-session"
check "greetd config.toml"       grep -q "voidc-session" "$A/etc/greetd/config.toml"
check "i3 config has pipewire"   grep -q "pipewire" "$A/home/void/.config/i3/config"
check "i3 .xinitrc"              grep -q "exec dbus-run-session -- i3" "$A/home/void/.xinitrc"
check "wallpaper decoded"        test -s "$A/home/void/Pictures/wall.png"
check "install log copied"       test -s "$A/var/log/voidc-install.log"
check "log: i3-gaps fallback"    grep -q "i3-gaps' missing -> using 'i3'" /tmp/dry_a.log
check "log: matugen pkg skipped" grep -q "skipped: matugen" /tmp/dry_a.log
check "log: polkit-gnome skipped" grep -q "skipped: polkit-gnome" /tmp/dry_a.log
if [ "$ARCH" = x86_64 ]; then
  check "matugen fallback installed" test -x "$A/usr/local/bin/matugen"
else
  check "matugen fallback skipped (no $ARCH asset)" \
    grep -q "could not resolve a matugen release asset" /tmp/dry_a.log
fi
check "stub: wipefs"             grep -q "wipefs -a /tmp/fakedisk" /tmp/stub_a.log
check "stub: gpt label"          grep -q "mklabel gpt" /tmp/stub_a.log
check "stub: bios_grub"          grep -q "bios_grub" /tmp/stub_a.log
check "stub: no ESP (BIOS)"      bash -c "! grep -q 'mkpart ESP' /tmp/stub_a.log"
check "stub: mkswap"             grep -q "mkswap" /tmp/stub_a.log
check "stub: no cryptsetup"      bash -c "! grep -q cryptsetup /tmp/stub_a.log"
check "stub: mkfs.ext4 boot"     grep -q "mkfs.ext4 -q -L boot" /tmp/stub_a.log
check "stub: mkfs.ext4 root"     grep -q "mkfs.ext4 -q -L voidroot /tmp/fakedisk4" /tmp/stub_a.log
check "stub: mount root"         grep -q "mount /tmp/fakedisk4 /tmp/drytarget" /tmp/stub_a.log
check "stub: mount /boot"        grep -q "mount /tmp/fakedisk2 /tmp/drytarget/boot" /tmp/stub_a.log
check "no EFI grub pkg (BIOS)"   bash -c "! grep -qE 'grub-(x86_64-efi|arm64-efi)' /tmp/stub_a.log"
check "chroot: useradd"          grep -q "useradd" /tmp/stub_a.log
check "chroot: grub i386-pc"     grep -q "grub-install --target=i386-pc" /tmp/stub_a.log
check "chroot: xbps-reconfigure" grep -q "xbps-reconfigure -fa" /tmp/stub_a.log
check "xbps-install transaction" grep -q "xbps-install -Sy -y -r /tmp/drytarget" /tmp/stub_a.log

echo "== scenario B (UEFI + LUKS2 + hyprland + greetd) =="
check "fstab root ext4"          grep -q "^UUID=aaaaaaaa" "$B/etc/fstab"
check "fstab /boot/efi vfat"     grep -q "/boot/efi" "$B/etc/fstab"
check "fstab vfat"               grep -q "vfat" "$B/etc/fstab"
check "fstab no swap (LUKS)"     bash -c "! grep -q swap '$B/etc/fstab'"
check "grub rd.luks.uuid"        grep -q "rd.luks.uuid=aaaaaaaa-bbbb" "$B/etc/default/grub"
check "grub timeout"             grep -q "GRUB_TIMEOUT=5" "$B/etc/default/grub"
check "dracut crypt conf"        grep -q "crypt" "$B/etc/dracut.conf.d/10-voidc-crypt.conf"
check "target extra repo conf"   grep -q "hyprland-void/repository-$EXTRA_ARCH-$LIBC" "$B/etc/xbps.d/30-repository-desktop.conf"
check "host extra repo removed"  bash -c "! test -e /etc/xbps.d/30-repository-desktop.conf"
check "hyprland conf pipewire"   grep -q "exec-once = pipewire" "$B/home/void/.config/hypr/hyprland.conf"
check "hyprpaper conf"           test -s "$B/home/void/.config/hypr/hyprpaper.conf"
check "waybar config"            test -s "$B/home/void/.config/waybar/config"
check "greetd wrapper (Hyprland)" grep -q "dbus-run-session -- Hyprland" "$B/usr/local/bin/voidc-session"
check "install log copied"       test -s "$B/var/log/voidc-install.log"
check "log: hyprlock skipped"    grep -q "skipped: hyprlock" /tmp/dry_b.log
check "log: matugen via repo"    grep -q "matugen already installed (repo)" /tmp/dry_b.log
check "stub: ESP mkpart"         grep -q "mkpart ESP" /tmp/stub_b.log
check "stub: esp flag"           grep -q "set 1 esp on" /tmp/stub_b.log
check "stub: mkfs.vfat"          grep -q "mkfs.vfat -F32" /tmp/stub_b.log
check "stub: luksFormat luks2"   grep -q "luksFormat --type luks2" /tmp/stub_b.log
check "stub: cryptsetup open"    grep -q "cryptsetup open" /tmp/stub_b.log
check "stub: mkfs mapper root"   grep -q "mkfs.ext4 -q -L voidroot /dev/mapper/cryptroot" /tmp/stub_b.log
check "stub: mount mapper"       grep -q "mount /dev/mapper/cryptroot /tmp/drytarget_b" /tmp/stub_b.log
check "stub: no mkswap (LUKS)"   bash -c "! grep -q mkswap /tmp/stub_b.log"
check "stub: efivarfs mount"     grep -q "efivarfs" /tmp/stub_b.log
check "pkg: $GRUB_PKG"           grep -q "$GRUB_PKG" /tmp/stub_b.log
check "chroot: grub $GRUB_TGT"   grep -q "grub-install --target=$GRUB_TGT" /tmp/stub_b.log
if [ "$ARCH" != x86_64 ]; then
  check "no x86_64-efi hardcode" bash -c "! grep -q 'target=x86_64-efi' /tmp/stub_b.log"
fi
check "chroot: xbps-reconfigure" grep -q "xbps-reconfigure -fa" /tmp/stub_b.log
check "xbps-install transaction" grep -q "xbps-install -Sy -y -r /tmp/drytarget_b" /tmp/stub_b.log

echo
if [ "$fail" = 0 ]; then echo "ALL DRY-RUN ASSERTIONS PASSED"; else echo "DRY-RUN FAILURES PRESENT"; fi
exit "$fail"
