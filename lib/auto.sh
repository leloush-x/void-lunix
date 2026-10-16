#!/usr/bin/env bash
# voidc — unattended mode: run with  voidc --auto profiles/i3.conf
# The profile is a sourced shell file; see profiles/i3.conf for all keys.

auto_defaults() {
  : "${FILESYSTEM:=ext4}"
  : "${HOSTNAME:=void}"
  : "${TIMEZONE:=UTC}"
  : "${KEYMAP:=us}"
  : "${LOCALE:=en_US.UTF-8}"
  : "${SESSION:=any}"
  : "${DESKTOP:=i3}"
  : "${CUSTOM_PKGS:=}"
  : "${EXTRAS:=audio networking fonts nonfree}"
  : "${GPU_DRIVER:=auto}"
  : "${LOGIN_MANAGER:=auto}"
  : "${LUKS:=no}"
  : "${LUKS_PASSWORD:=}"
  : "${SWAP_MB:=auto}"
  : "${AUTOSTART_DESKTOP:=${AUTOSTART_X:-no}}"
  : "${MIRROR:=auto}"
  : "${DOTFILES_URL:=}"
  : "${RUN_DOTFILES_INSTALL:=no}"
  if [ "$XBPS_ARCH" = x86_64 ] && ! in_list multilib "$EXTRAS"; then
    EXTRAS+=" multilib"
  fi
  if desktop_needs_nonfree && ! in_list nonfree "$EXTRAS"; then
    EXTRAS+=" nonfree"
    warnlog "nvidia selected: nonfree repo enabled"
  fi
}

auto_validate() {
  check_firmware_support
  [ -n "${DISK:-}" ] || die "Profile error: DISK is required."
  [ -b "$DISK" ] || die "Not a block device: $DISK"
  case "$FILESYSTEM" in ext4|btrfs) ;; *) die "FILESYSTEM must be ext4 or btrfs";; esac
  printf '%s' "$HOSTNAME" | grep -qE '^[a-z0-9][a-z0-9-]*$' || die "Invalid HOSTNAME: $HOSTNAME"
  printf '%s' "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$' || die "Invalid USERNAME: $USERNAME"
  [ -n "${ROOT_PASS:-}" ] || die "Profile error: ROOT_PASS is required (unattended mode)."
  [ -n "${USER_PASS:-${ROOT_PASS:-}}" ] || die "Profile error: USER_PASS is required."
  USER_PASS="${USER_PASS:-$ROOT_PASS}"
  [ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "Unknown TIMEZONE: $TIMEZONE"
  [ "$LUKS" = yes ] && [ -z "$LUKS_PASSWORD" ] && die "LUKS=yes requires LUKS_PASSWORD."
  [ "$LUKS" = yes ] && [ "$SWAP_MB" != 0 ] && { SWAP_MB=0; warnlog "LUKS enabled: swap disabled."; }
  if [ "$SWAP_MB" = auto ]; then
    if [ "$RAM_MB" -lt 4096 ]; then SWAP_MB="$RAM_MB"; else SWAP_MB=4096; fi
  fi
  case "$DESKTOP" in
    none|i3|bspwm|dwm|openbox|awesome|qtile|xfce|lxqt|mate|cinnamon|budgie|kde|gnome|sway|niri|hyprland|river|wayfire|labwc|custom) ;;
    *) die "Unknown DESKTOP: $DESKTOP";;
  esac
  if [ "$DESKTOP" = hyprland ]; then
    warnlog "Hyprland: the third-party hyprland-void community repo will be enabled."
  fi
  case "$SESSION" in any|x11|wayland) ;; *) die "SESSION must be any|x11|wayland";; esac
  desktop_allowed "$DESKTOP" || die "DESKTOP=$DESKTOP is not available in SESSION=$SESSION (use SESSION=any)."
  case "$GPU_DRIVER" in auto|none|intel|amd|nvidia) ;; *) die "GPU_DRIVER must be auto|none|intel|amd|nvidia";; esac
  case "$LOGIN_MANAGER" in auto|none|lightdm|sddm|gdm|greetd) ;; *) die "LOGIN_MANAGER must be auto|none|lightdm|sddm|gdm|greetd";; esac
  [ "$DESKTOP" = custom ] && [ -z "$CUSTOM_PKGS" ] && die "DESKTOP=custom requires CUSTOM_PKGS."
}

auto_resolve_mirror() {
  case "$MIRROR" in
    auto)
      say "Testing mirrors"
      MIRROR="$(pick_fastest_mirror)"
      [ -n "$MIRROR" ] || MIRROR="$DEFAULT_MIRROR"
      ;;
    default) MIRROR="$DEFAULT_MIRROR" ;;
  esac
  MIRROR="${MIRROR%/}"
  say "Using mirror: $MIRROR"
}

run_auto() {
  local cfg="$1"
  [ -f "$cfg" ] || die "Profile not found: $cfg"

  NO_DIALOG=yes
  # shellcheck disable=SC1090
  . "$cfg"
  detect_environment
  auto_defaults
  auto_validate
  auto_resolve_mirror

  say "Unattended install: $DISK -> $FILESYSTEM, desktop=$DESKTOP"
  partition_disk
  format_partitions
  mount_target
  prepare_target
  resolve_pkgs
  install_packages
  mount_chroot
  write_fstab
  configure_system
  finalize_system
  install_bootloader
  desktop_setup
  run "Saving install log" cp "$LOGFILE" "$TARGET/var/log/voidc-install.log"
  disable_host_extra_repo
  sync

  say "Installation complete"
  note "Desktop: $DESKTOP ($SESSION stack)   User: $USERNAME"
  if desktop_uses_startx; then note "Log in and run: startx"
  elif desktop_uses_wayland; then note "Log in and run: dbus-run-session -- $(desktop_session_cmd)"
  fi
  note "Target mounted at $TARGET — reboot when ready (log: $LOGFILE)"
}
