#!/usr/bin/env bash
# mkstubs.sh — external-command stubs for the voidc pipeline dry run.
set -eu
D=/tmp/stubbin
rm -rf "$D"; mkdir -p "$D"

generic() {
  cat >"$D/$1" <<'EOF'
#!/bin/sh
echo "$(basename "$0") $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
exit 0
EOF
  chmod 0755 "$D/$1"
}

for n in parted wipefs partprobe udevadm mkfs.vfat mkfs.ext4 mkfs.btrfs \
         mkfs.xfs mkfs.f2fs \
         mkswap cryptsetup swapon swapoff mount umount modprobe efibootmgr \
         grub-install grub-mkconfig hwclock; do generic "$n"; done

# lsblk: report nothing (no mounts, no disks)
printf '#!/bin/sh\necho "lsblk $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"\nexit 0\n' >"$D/lsblk"
chmod 0755 "$D/lsblk"

# mountpoint: pretend nothing is mounted (drives the efivarfs attempt)
printf '#!/bin/sh\necho "mountpoint $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"\nexit 1\n' >"$D/mountpoint"
chmod 0755 "$D/mountpoint"

# blkid: fixed UUID
cat >"$D/blkid" <<'EOF'
#!/bin/sh
echo "blkid $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
echo "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
exit 0
EOF
chmod 0755 "$D/blkid"

# xbps-uhelper: report the pinned test arch (x86_64 / x86_64-musl)
cat >"$D/xbps-uhelper" <<'EOF'
#!/bin/sh
echo "xbps-uhelper $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
printf '%s\n' "${TEST_ARCH:-x86_64}"
exit 0
EOF
chmod 0755 "$D/xbps-uhelper"

# xbps-query: exists unless the package is in $STUB_MISSING
cat >"$D/xbps-query" <<'EOF'
#!/bin/sh
echo "xbps-query $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
for a in "$@"; do
  case " ${STUB_MISSING:-} " in *" $a "*) exit 1;; esac
done
exit 0
EOF
chmod 0755 "$D/xbps-query"

# xbps-install: succeed and mark the target as installed
cat >"$D/xbps-install" <<'EOF'
#!/bin/sh
echo "xbps-install $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
if [ -n "${TARGET:-}" ]; then
  mkdir -p "$TARGET/usr/bin"
  : >"$TARGET/usr/bin/xbps-install"
fi
exit 0
EOF
chmod 0755 "$D/xbps-install"

generic xbps-reconfigure

# chroot: log the chrooted command, succeed (never reads stdin)
cat >"$D/chroot" <<'EOF'
#!/bin/sh
echo "CHROOT $*" >> "${STUB_LOG:-/tmp/stub_calls.log}"
exit 0
EOF
chmod 0755 "$D/chroot"

echo "stubs ready in $D"
