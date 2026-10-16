#!/usr/bin/env bash
# voidc — partitioning / LUKS / filesystems / mounting / fstab.
# Consumes: DISK UEFI FILESYSTEM LUKS LUKS_PASSWORD SWAP_MB TARGET
# Produces: ESPDEV BOOTDEV SWAPDEV ROOTDEV LUKSDEV ROOTDEV_FS CRYPT_NAME

ESP_MB=512
BOOT_MB=1024
CRYPT_NAME="${CRYPT_NAME:-cryptroot}"

disk_is_busy() {
  local mounts
  mounts="$(lsblk -pno MOUNTPOINTS "$1" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$mounts" ]
}

# ---------------------------------------------------------------- auto GPT --
partition_disk() {
  need_cmd parted
  [ -b "$DISK" ] || die "Not a block device: $DISK"
  if disk_is_busy "$DISK"; then
    die "$DISK (or a partition on it) is mounted/in use — unmount it first."
  fi

  local start=1 part=0 swap_end
  local -a parts=()

  run "Wiping disk signatures" wipefs -a "$DISK"
  run "Creating GPT on $DISK" parted -s "$DISK" mklabel gpt

  if [ "$UEFI" = yes ]; then
    part=$((part+1)); parts+=("$part")
    run "Creating EFI system partition" parted -s "$DISK" mkpart ESP fat32 "${start}MiB" "$((start+ESP_MB))MiB"
    try parted -s "$DISK" set "$part" esp on
    ESPDEV="$(part_dev "$DISK" "$part")"; ESP_PARTN="$part"
    start=$((start+ESP_MB))
  else
    part=$((part+1))
    run "Creating BIOS boot partition" parted -s "$DISK" mkpart BIOS-BOOT ext4 "${start}MiB" "$((start+1))MiB"
    try parted -s "$DISK" set "$part" bios_grub on
    start=$((start+1))
  fi

  part=$((part+1))
  run "Creating /boot partition" parted -s "$DISK" mkpart boot ext4 "${start}MiB" "$((start+BOOT_MB))MiB"
  BOOTDEV="$(part_dev "$DISK" "$part")"
  start=$((start+BOOT_MB))

  if [ "${SWAP_MB:-0}" -gt 0 ]; then
    part=$((part+1))
    swap_end=$((start+SWAP_MB))
    run "Creating swap partition" parted -s "$DISK" mkpart swap linux-swap "${start}MiB" "${swap_end}MiB"
    SWAPDEV="$(part_dev "$DISK" "$part")"
    start=$swap_end
  fi

  part=$((part+1))
  run "Creating root partition" parted -s "$DISK" mkpart root ext4 "${start}MiB" 100%
  ROOTDEV="$(part_dev "$DISK" "$part")"
  LUKSDEV="$ROOTDEV"

  run "Re-reading partition table" partprobe "$DISK"
  try udevadm settle
}

# ------------------------------------------------------------- formatting ----
# fs_mkfs_cmd <fs> -> mkfs tool name; fs_mkfs_pkg <fs> -> package providing it
fs_mkfs_cmd() {
  case "$1" in
    ext4)  echo mkfs.ext4 ;;
    btrfs) echo mkfs.btrfs ;;
    xfs)   echo mkfs.xfs ;;
    f2fs)  echo mkfs.f2fs ;;
    *) return 1 ;;
  esac
}

fs_mkfs_pkg() {
  case "$1" in
    ext4)  echo e2fsprogs ;;
    btrfs) echo btrfs-progs ;;
    xfs)   echo xfsprogs ;;
    f2fs)  echo f2fs-tools ;;
    *) return 1 ;;
  esac
}

mkfs_root() {
  local tool pkg
  tool="$(fs_mkfs_cmd "$FILESYSTEM")" || die "Unsupported filesystem: $FILESYSTEM"
  if ! command -v "$tool" >/dev/null 2>&1; then
    pkg="$(fs_mkfs_pkg "$FILESYSTEM")"
    die "$tool not found on this live system — run 'xbps-install -Sy $pkg' first (or pick another filesystem)."
  fi
  case "$FILESYSTEM" in
    ext4)  run "Creating ext4 on $ROOTDEV_FS"   mkfs.ext4 -q -L voidroot "$ROOTDEV_FS" ;;
    btrfs) run "Creating btrfs on $ROOTDEV_FS"  mkfs.btrfs -f -L voidroot "$ROOTDEV_FS" ;;
    xfs)   run "Creating xfs on $ROOTDEV_FS"    mkfs.xfs -f -i sparse=0 -L voidroot "$ROOTDEV_FS" ;;
    f2fs)  run "Creating f2fs on $ROOTDEV_FS"   mkfs.f2fs -f -l voidroot "$ROOTDEV_FS" ;;
  esac
}

format_partitions() {
  if [ -n "${ESPDEV:-}" ]; then
    run "Creating FAT32 on $ESPDEV" mkfs.vfat -F32 -n EFI "$ESPDEV"
  fi
  if [ -n "${BOOTDEV:-}" ]; then
    run "Creating ext4 on $BOOTDEV" mkfs.ext4 -q -L boot "$BOOTDEV"
  fi
  if [ -n "${SWAPDEV:-}" ]; then
    run "Creating swap on $SWAPDEV" mkswap -L swap "$SWAPDEV"
  fi

  if [ "$LUKS" = yes ]; then
    [ -n "${LUKS_PASSWORD:-}" ] || die "LUKS enabled but no passphrase set."
    verb "LuksFormat $LUKSDEV (luks2)"
    printf '%s' "$LUKS_PASSWORD" | cryptsetup luksFormat --type luks2 --batch-mode --key-file - "$LUKSDEV" >>"$LOGFILE" 2>&1 \
      || die "cryptsetup luksFormat failed on $LUKSDEV (see $LOGFILE)"
    printf '%s' "$LUKS_PASSWORD" | cryptsetup open --key-file - "$LUKSDEV" "$CRYPT_NAME" >>"$LOGFILE" 2>&1 \
      || die "cryptsetup open failed on $LUKSDEV"
    ROOTDEV_FS="/dev/mapper/$CRYPT_NAME"
  else
    ROOTDEV_FS="$ROOTDEV"
  fi

  mkfs_root
}

# ---------------------------------------------------------------- mounting ---
mount_target() {
  run "Mounting root on $TARGET" mkdir -p "$TARGET"
  run "Mounting $ROOTDEV_FS at $TARGET" mount "$ROOTDEV_FS" "$TARGET"
  if [ -n "${BOOTDEV:-}" ]; then
    run "Mounting /boot" mkdir -p "$TARGET/boot"
    run "Mounting $BOOTDEV at $TARGET/boot" mount "$BOOTDEV" "$TARGET/boot"
  fi
  if [ -n "${ESPDEV:-}" ]; then
    run "Preparing /boot/efi" mkdir -p "$TARGET/boot/efi"
    run "Mounting $ESPDEV at $TARGET/boot/efi" mount "$ESPDEV" "$TARGET/boot/efi"
  fi
  if [ -n "${SWAPDEV:-}" ]; then
    run "Enabling swap on $SWAPDEV" swapon "$SWAPDEV"
  fi
}

# ------------------------------------------------------------------- fstab --
write_fstab() {
  local opts=defaults,noatime rootpass=1
  case "$FILESYSTEM" in btrfs|xfs|f2fs) rootpass=0 ;; esac   # no fsck pass needed
  local fstab="$TARGET/etc/fstab"
  [ -d "$TARGET/etc" ] || die "Target system not installed yet (no /etc)."
  : >"$fstab"

  {
    printf '# /etc/fstab — generated by voidc\n'
    printf 'UUID=%s\t/\t\t%s\t%s\t0 %s\n' "$(uuid_of "$ROOTDEV_FS")" "$FILESYSTEM" "$opts" "$rootpass"
    [ -n "${BOOTDEV:-}" ] && printf 'UUID=%s\t/boot\t\text4\t%s\t0 2\n' "$(uuid_of "$BOOTDEV")" "$opts"
    [ -n "${ESPDEV:-}"  ] && printf 'UUID=%s\t/boot/efi\tvfat\tdefaults,umask=0077\t0 2\n' "$(uuid_of "$ESPDEV")"
    [ -n "${SWAPDEV:-}" ] && printf 'UUID=%s\tnone\t\tswap\tsw\t0 0\n' "$(uuid_of "$SWAPDEV")"
    printf 'tmpfs\t/tmp\ttmpfs\tdefaults,nosuid,nodev\t0 0\n'
  } >>"$fstab"

  verb "wrote fstab:"; cat "$fstab" >>"$LOGFILE"
}
