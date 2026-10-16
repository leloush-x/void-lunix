#!/usr/bin/env bash
# voidc — bootloader installation (GRUB, UEFI + BIOS).

install_bootloader() {
  local cmdline="loglevel=4"
  if [ "$LUKS" = yes ]; then
    local luks_uuid; luks_uuid="$(uuid_of "$LUKSDEV")"
    [ -n "$luks_uuid" ] || die "Could not read LUKS UUID from $LUKSDEV"
    cmdline+=" rd.luks.uuid=$luks_uuid"
  fi

  # kernel command line
  local grubdef="$TARGET/etc/default/grub"
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$grubdef"; then
    sed -i -E "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$cmdline\"|" "$grubdef"
  else
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$cmdline" >>"$grubdef"
  fi
  sed -i -E 's|^#?GRUB_TIMEOUT=.*|GRUB_TIMEOUT=5|' "$grubdef" || true
  verb "grub cmdline: $cmdline"

  if [ "$UEFI" = yes ]; then
    say "Installing GRUB (UEFI)"
    if ! chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi \
         --bootloader-id=void --recheck >>"$LOGFILE" 2>&1; then
      warnlog "standard grub-install failed, retrying with --removable"
      chroot "$TARGET" grub-install --target=x86_64-efi --efi-directory=/boot/efi \
        --removable --recheck >>"$LOGFILE" 2>&1 \
        || die "grub-install (UEFI) failed — see $LOGFILE"
    fi
  else
    say "Installing GRUB (BIOS)"
    chroot "$TARGET" grub-install --target=i386-pc --recheck "$DISK" >>"$LOGFILE" 2>&1 \
      || die "grub-install (BIOS) failed — see $LOGFILE"
  fi

  say "Generating grub.cfg"
  chroot "$TARGET" grub-mkconfig -o /boot/grub/grub.cfg >>"$LOGFILE" 2>&1 \
    || die "grub-mkconfig failed — see $LOGFILE"

  [ -s "$TARGET/boot/grub/grub.cfg" ] || die "grub.cfg was not generated."
  verb "bootloader installed"
}
