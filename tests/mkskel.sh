#!/usr/bin/env bash
# mkskel.sh <target-dir> — minimal "already installed target" skeleton.
set -eu
T="$1"
rm -rf "$T"
mkdir -p "$T"/var/log "$T"/var/db/xbps "$T"/etc/xbps.d \
         "$T"/etc/runit/runsvdir/default \
         "$T"/etc/sv/dbus "$T"/etc/sv/elogind "$T"/etc/sv/NetworkManager \
         "$T"/etc/sv/sshd "$T"/etc/sv/bluetoothd "$T"/etc/sv/cupsd \
         "$T"/etc/sv/chronyd "$T"/etc/sv/rtkit "$T"/etc/sv/greetd \
         "$T"/usr/bin "$T"/usr/share/zoneinfo "$T"/boot/grub "$T"/home/void \
         "$T"/etc/default "$T"/usr/share/examples/wireplumber \
         "$T"/usr/share/examples/pipewire "$T"/usr/share/applications
touch "$T/usr/bin/xbps-install"; chmod 0755 "$T/usr/bin/xbps-install"
if [ -f /usr/share/zoneinfo/UTC ]; then
  cp /usr/share/zoneinfo/UTC "$T/usr/share/zoneinfo/UTC"
else
  touch "$T/usr/share/zoneinfo/UTC"
fi
printf '#en_US.UTF-8 UTF-8\n' >"$T/etc/default/libc-locales"
cat >"$T/etc/group" <<'EOF'
root:x:0:
wheel:x:10:
floppy:x:11:
cdrom:x:24:
audio:x:28:
kvm:x:97:
video:x:986:
EOF
cat >"$T/etc/rc.conf" <<'EOF'
# voidc dry-run skeleton
KEYMAP="us"
HARDWARECLOCK="UTC"
TIMEZONE="UTC"
EOF
cat >"$T/etc/default/grub" <<'EOF'
#GRUB_TIMEOUT=5
GRUB_CMDLINE_LINUX_DEFAULT="loglevel=4"
EOF
printf 'menuentry dryrun {}\n' >"$T/boot/grub/grub.cfg"
touch "$T/usr/share/examples/wireplumber/10-wireplumber.conf" \
      "$T/usr/share/examples/pipewire/20-pipewire-pulse.conf" \
      "$T/usr/share/applications/pipewire.desktop"
echo "skeleton ready: $T"
