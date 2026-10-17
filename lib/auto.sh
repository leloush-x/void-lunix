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
  # multilib is needed for 32-bit apps and for nvidia-libs-32bit; auto-enable
  # it on glibc x86_64 unless the user opted out (EXTRAS already lists
  # multilib) or this is a minimal/server install with no 32-bit needs.
  if [ "$XBPS_ARCH" = x86_64 ] && \
     { [ "${DESKTOP:-none}" != none ] || [ "${GPU_DRIVER:-auto}" = nvidia ]; } && \
     ! in_list multilib "$EXTRAS"; then
    EXTRAS+=" multilib"
    warnlog "x86_64 glibc: multilib repo enabled automatically"
  fi
  if desktop_needs_nonfree && ! in_list nonfree "$EXTRAS"; then
    EXTRAS+=" nonfree"
    warnlog "nvidia selected: nonfree repo enabled"
  fi
}

# SWAP_MB: "auto" | 0 (off) | whole number of MiB, 64..65536.
# Anything else used to slip through and silently produce no swap partition.
validate_swap_mb() {
  local v="$1"
  [ "$v" = auto ] && return 0
  case "$v" in
    ''|*[!0-9]*) die "SWAP_MB must be 'auto', 0 or a whole number of MiB (got: '$v')."; return 1 ;;
  esac
  [ "$v" -eq 0 ] && return 0
  [ "$v" -ge 64 ] && [ "$v" -le 65536 ] && return 0
  die "SWAP_MB must be 0 (off) or 64-65536 MiB (got: $v)."
  return 1
}

auto_validate() {
  [ -n "${DISK:-}" ] || die "Profile error: DISK is required."
  [ -b "$DISK" ] || die "Not a block device: $DISK"
  case "$FILESYSTEM" in
    ext4|btrfs|xfs|f2fs) ;;
    *) die "FILESYSTEM must be ext4, btrfs, xfs or f2fs";;
  esac
  local fs_tool
  fs_tool="$(fs_mkfs_cmd "$FILESYSTEM")"
  command -v "$fs_tool" >/dev/null 2>&1 \
    || die "FILESYSTEM=$FILESYSTEM needs '$fs_tool' on this live system (xbps-install -Sy $(fs_mkfs_pkg "$FILESYSTEM"))."
  printf '%s' "$HOSTNAME" | grep -qE '^[a-z0-9][a-z0-9-]*$' || die "Invalid HOSTNAME: $HOSTNAME"
  printf '%s' "$USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$' || die "Invalid USERNAME: $USERNAME"
  [ -n "${ROOT_PASS:-}" ] || die "Profile error: ROOT_PASS is required (unattended mode)."
  [ -n "${USER_PASS:-${ROOT_PASS:-}}" ] || die "Profile error: USER_PASS is required."
  USER_PASS="${USER_PASS:-$ROOT_PASS}"
  [ -f "/usr/share/zoneinfo/$TIMEZONE" ] || die "Unknown TIMEZONE: $TIMEZONE"
  case "$TIMEZONE" in /*|*..*|*[!A-Za-z0-9._/-]*) die "Invalid TIMEZONE: $TIMEZONE." ;; esac
  [ "$LUKS" = yes ] && [ -z "$LUKS_PASSWORD" ] && die "LUKS=yes requires LUKS_PASSWORD."
  case "${LOCALE:-}" in ''|*[!A-Za-z0-9._-]*) die "Invalid LOCALE: ${LOCALE:-}." ;; esac
  case "${KEYMAP:-}" in ''|*[!A-Za-z0-9_-]*) die "Invalid KEYMAP: ${KEYMAP:-}." ;; esac
  case "${MIRROR:-}" in
    auto|default) ;;
    http://*|https://*) case "$MIRROR" in *[[:space:]]*) die "Invalid MIRROR: contains whitespace." ;; esac ;;
    *) die "MIRROR must be 'auto', 'default' or an http(s) URL: ${MIRROR:-}." ;;
  esac
  validate_swap_mb "$SWAP_MB"
  if [ "$DESKTOP" = custom ]; then
    [ -n "${CUSTOM_PKGS:-}" ] || die "DESKTOP=custom requires CUSTOM_PKGS."
    local cp
    for cp in $CUSTOM_PKGS; do
      printf '%s' "$cp" | grep -qE '^[a-z0-9][a-z0-9._+-]*$' || die "Invalid package name in CUSTOM_PKGS: $cp."
    done
  fi
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
  [ "$(id -u)" -eq 0 ] || die "Please run as root (or use sudo)."

  # read by the shared ui helpers (common.sh) and the wizard
  # shellcheck disable=SC2034
  NO_DIALOG=yes
  # shellcheck disable=SC1090
  . "$cfg"
  detect_environment
  auto_defaults
  auto_validate
  auto_resolve_mirror

  say "Unattended install: $DISK -> $FILESYSTEM, desktop=$DESKTOP"
  # extra repos on, then package check — BEFORE the disk is touched
  # (a missing critical package aborts with the disk still intact)
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
  run "Saving install log" install -m 0640 "$LOGFILE" "$TARGET/var/log/voidc-install.log"
  disable_host_extra_repo
  sync

  say "Installation complete"
  note "Desktop: $DESKTOP ($SESSION stack)   User: $USERNAME"
  if desktop_uses_startx; then note "Log in and run: startx"
  elif desktop_uses_wayland; then note "Log in and run: dbus-run-session -- $(desktop_session_cmd)"
  fi
  note "Target mounted at $TARGET — reboot when ready (log: $LOGFILE)"
}
