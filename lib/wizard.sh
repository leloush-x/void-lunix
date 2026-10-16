#!/usr/bin/env bash
# voidc — interactive wizard (dialog TUI).

WIZ_HEADER="Void Custom Installer v$VOIDC_VERSION
=====================================
Fast, clean text-based installer for Void Linux.

- GPT partitioning (UEFI + BIOS), optional LUKS
- Single-transaction package install
- X11 + Wayland: i3, bspwm, dwm, sway, niri, Hyprland, XFCE, KDE, ...
- Ricing-ready: polybar, rofi, picom, dunst, alacritty, matugen"

wizard_abort() {
  local rc=$?
  printf '\n\033[1;33mInstallation cancelled.\033[0m\n' >&2
  if declare -F disable_host_extra_repo >/dev/null; then disable_host_extra_repo; fi
  exit "$rc"
}

wizard_preflight() {
  [ "$(id -u)" -eq 0 ] || die "Run as root (live ISO is root)."
  need_cmd xbps-install
  need_cmd dialog
  need_cmd parted
  need_cmd mkfs.ext4
  need_cmd mkfs.vfat

  if findmnt -rn "$TARGET" >/dev/null 2>&1; then
    if ui_yesno "Something is already mounted at $TARGET.\n\nUnmount it and continue?" 9 60; then
      try umount -R "$TARGET"
    else
      die "Aborted: $TARGET is busy."
    fi
  fi
  detect_environment
}

step_welcome() {
  ui_msg "$WIZ_HEADER" 18 62
}

step_disk() {
  local disks choice
  disks="$(list_disks)"
  [ -n "$disks" ] || die "No installable disks found."

  local -a menu=()
  while read -r name size model; do
    [ -n "$name" ] || continue
    menu+=("$name" "${size:-?} ${model:-}")
  done <<<"$disks"

  choice="$(ui_menu "Select the disk to install on.\n\nALL DATA ON THIS DISK WILL BE ERASED." 20 74 8 "${menu[@]}")" \
    || wizard_abort
  DISK="$choice"

  local answer
  answer="$(ui_input "Type the disk name to confirm erasing $DISK:" 9 60 "")" || wizard_abort
  [ "$answer" = "$DISK" ] || die "Confirmation failed (got '$answer', expected '$DISK')."
}

step_filesystem() {
  # offer only filesystems whose mkfs tool exists on the live system
  local -a menu=()
  command -v mkfs.ext4  >/dev/null 2>&1 && menu+=("ext4"  "Battle-tested, safe default")
  command -v mkfs.btrfs >/dev/null 2>&1 && menu+=("btrfs" "Snapshots, compression")
  command -v mkfs.xfs   >/dev/null 2>&1 && menu+=("xfs"   "XFS — mature, high throughput")
  command -v mkfs.f2fs  >/dev/null 2>&1 && menu+=("f2fs"  "Flash-friendly — SSD/eMMC/SD")
  [ "${#menu[@]}" -gt 0 ] || die "No mkfs tool found on this live system (need at least e2fsprogs)."
  FILESYSTEM="$(ui_menu "Root filesystem:" 14 64 4 "${menu[@]}")" || wizard_abort
}

step_swap() {
  local auto_mb=$(( RAM_MB < 4096 ? RAM_MB : 4096 ))
  [ "$auto_mb" -gt 8192 ] && auto_mb=8192
  local choice
  choice="$(ui_menu "Swap partition size? (RAM: ${RAM_MB} MiB)" 15 60 5 \
    "auto" "Auto: ${auto_mb} MiB" \
    "none" "No swap partition" \
    "2048" "2 GiB" \
    "4096" "4 GiB" \
    "8192" "8 GiB")" || wizard_abort
  case "$choice" in
    none) SWAP_MB=0 ;;
    auto) SWAP_MB=$auto_mb ;;
    *)    SWAP_MB="$choice" ;;
  esac
}

step_luks() {
  LUKS=no
  if ui_yesno "Encrypt the root filesystem with LUKS?\n\nYou will type this passphrase at every boot." 10 62; then
    LUKS=yes
    # re-prompt on ESC/short/mismatch (same loop as the login passwords):
    # an empty passphrase here would silently skip encryption
    LUKS_PASSWORD=""
    while [ -z "$LUKS_PASSWORD" ]; do
      LUKS_PASSWORD="$(ask_password_twice "LUKS passphrase" || true)"
    done
    if [ "$SWAP_MB" -gt 0 ]; then
      ui_msg "Swap will be skipped (encrypted root + plain swap is not offered)." 8 60
      SWAP_MB=0
    fi
  fi
}

# ---------------------------------------------------------------- identity ---
# Each field re-prompts on invalid input and can be changed later from the
# review menu in step_identity.
ask_hostname() {
  local v
  while :; do
    v="$(ui_input "Hostname (lowercase letters, digits, dashes):" 9 64 "${HOSTNAME:-void}")" || wizard_abort
    if printf '%s' "$v" | grep -qE '^[a-z0-9][a-z0-9-]*$'; then HOSTNAME="$v"; return 0; fi
    ui_msg "Invalid hostname: '$v'\n\nUse lowercase letters, digits and dashes,\nand start with a letter or digit." 10 62
  done
}

ask_username() {
  local v
  while :; do
    v="$(ui_input "Username:" 9 60 "${USERNAME:-void}")" || wizard_abort
    if printf '%s' "$v" | grep -qE '^[a-z_][a-z0-9_-]*$'; then USERNAME="$v"; return 0; fi
    ui_msg "Invalid username: '$v'\n\nUse lowercase letters, digits, '_' and '-',\nstarting with a letter or '_'." 10 62
  done
}

ask_timezone() {
  local v
  while :; do
    v="$(ui_input "Timezone (e.g. Europe/Berlin, UTC):" 9 60 "${TIMEZONE:-UTC}")" || wizard_abort
    if [ -f "/usr/share/zoneinfo/$v" ]; then TIMEZONE="$v"; return 0; fi
    ui_msg "Unknown timezone: '$v'.\n\nExamples: UTC, Europe/Berlin, America/New_York\n(full list in /usr/share/zoneinfo)." 11 66
  done
}

ask_keymap() {
  KEYMAP="$(ui_input "Console/X keyboard layout (e.g. us, de, fr, tr):" 9 64 "${KEYMAP:-us}")" || wizard_abort
  [ -n "$KEYMAP" ] || KEYMAP="us"
}

ask_locale() {
  LOCALE="$(ui_menu "System locale:" 12 60 2 \
    "en_US.UTF-8" "English (US)" \
    "C.UTF-8"     "Minimal, no translation")" || wizard_abort
}

ask_passwords() {
  # ESC in a password box re-prompts; Ctrl-C cancels the installer.
  ROOT_PASS=""
  while [ -z "$ROOT_PASS" ]; do
    ROOT_PASS="$(ask_password_twice "Root password" || true)"
  done
  if ui_yesno "Use the same password for user '$USERNAME'?" 8 64; then
    USER_PASS="$ROOT_PASS"
  else
    USER_PASS=""
    while [ -z "$USER_PASS" ]; do
      USER_PASS="$(ask_password_twice "Password for $USERNAME" || true)"
    done
  fi
}

step_identity() {
  ask_hostname
  ask_username
  ask_passwords
  ask_timezone
  ask_keymap
  ask_locale

  # review loop — re-type any of it before continuing
  local choice
  while :; do
    choice="$(ui_menu "Review your account settings:" 18 74 8 \
      "hostname"  "Hostname:  $HOSTNAME" \
      "username"  "Username:  $USERNAME" \
      "passwords" "Passwords: root + $USERNAME" \
      "timezone"  "Timezone:  $TIMEZONE" \
      "keymap"    "Keymap:    $KEYMAP" \
      "locale"    "Locale:    $LOCALE" \
      "done"      "Continue ->")" || wizard_abort
    case "$choice" in
      hostname)  ask_hostname ;;
      username)  ask_username ;;
      passwords) ask_passwords ;;
      timezone)  ask_timezone ;;
      keymap)    ask_keymap ;;
      locale)    ask_locale ;;
      done)      break ;;
    esac
  done
}

step_session() {
  SESSION="$(ui_menu "Which session stack?" 15 70 3 \
    "any"     "Show everything (X11 + Wayland)" \
    "x11"     "X11 only — i3, bspwm, Xfce, KDE, ..." \
    "wayland" "Wayland only — Hyprland, Sway, River, ...")" || wizard_abort
}

step_desktop() {
  local -a menu=()
  local entry tag desc
  for entry in \
    "i3|i3 + polybar/rofi/picom/dunst — ricing preset (recommended)" \
    "bspwm|bspwm + sxhkd — ricing preset" \
    "dwm|suckless dwm + dmenu" \
    "openbox|Openbox + tint2" \
    "awesome|AwesomeWM (Lua)" \
    "qtile|Qtile (Python)" \
    "xfce|Xfce 4 (lightweight full DE)" \
    "lxqt|LXQt (Qt, light)" \
    "mate|MATE" \
    "cinnamon|Cinnamon" \
    "budgie|Budgie" \
    "kde|KDE Plasma" \
    "gnome|GNOME" \
    "hyprland|Hyprland — Wayland tiling (community repo)" \
    "niri|niri — scrolling Wayland preset (recommended)" \
    "sway|Sway — i3-like Wayland preset" \
    "river|River (Wayland, minimal)" \
    "wayfire|Wayfire (Wayland, desktop-like)" \
    "labwc|Labwc (Wayland, Openbox-like)" \
    "none|Base system only (configure later)" \
    "custom|Custom package list"
  do
    tag="${entry%%|*}"; desc="${entry#*|}"
    desktop_allowed "$tag" && menu+=("$tag" "$desc")
  done

  DESKTOP="$(ui_menu "Choose your desktop / window manager (stack: $SESSION):" 22 78 18 "${menu[@]}")" || wizard_abort
  if [ "$DESKTOP" = custom ]; then
    # consumed by desktop.sh (build_pkg_list)
    # shellcheck disable=SC2034
    CUSTOM_PKGS="$(ui_input "Space-separated package list:" 10 74 "xorg xinit i3 alacritty")" || wizard_abort
  fi
  if [ "$DESKTOP" = hyprland ]; then
    ui_msg "Hyprland is not packaged in Void — voidc installs it from\nthe community repository (github.com/Makrennel/hyprland-void):\n\n  $(desktop_extra_repo_url)\n\nThe repo is enabled on the live system and in the target,\nthen hyprland, hyprpaper, hypridle, hyprlock and\nxdg-desktop-portal-hyprland are installed normally.\n\nThird-party software — continue only if you trust it." 19 78
  fi
}

step_extras() {
  local -a items=(
    audio     "PipeWire audio (wireplumber + pulse server)" on
    networking "NetworkManager + applet" on
    fonts     "Fonts (DejaVu, emoji, nerd)" on
    nonfree   "Enable nonfree repo (firmware/drivers)" on
    bluetooth "Bluetooth (bluez + blueman)" off
    printing  "Printing (CUPS)" off
    ssh       "SSH server" off
  )
  [ "$XBPS_ARCH" = x86_64 ] && items+=(multilib "Enable multilib repo (32-bit support)" off)

  local sel
  sel="$(ui_check "Extra options:" 18 74 9 "${items[@]}")" || wizard_abort
  EXTRAS=" $(printf '%s' "$sel" | tr -d '"') "

  # autostart on tty1 (X11 via startx, Wayland via compositor)
  AUTOSTART_DESKTOP=no
  if [ "$DESKTOP" != none ] && ui_yesno "Auto-start $DESKTOP on tty1 login?" 8 60; then
    AUTOSTART_DESKTOP=yes
  fi

  # consumed by rice.sh (clone_dotfiles)
  # shellcheck disable=SC2034
  DOTFILES_URL=""
  if ui_yesno "Clone a dotfiles repo into ~/.dotfiles?" 8 60; then
    # consumed by rice.sh (clone_dotfiles)
    # shellcheck disable=SC2034
    DOTFILES_URL="$(ui_input "Git URL of your dotfiles repo:" 9 74 "https://github.com/user/dotfiles")" || wizard_abort
    # shellcheck disable=SC2034
    ui_yesno "Run the dotfiles install script too?" 8 60 && RUN_DOTFILES_INSTALL=yes || RUN_DOTFILES_INSTALL=no
  fi
}

step_advanced() {
  GPU_DRIVER="$(ui_menu "GPU drivers (advanced):" 16 74 5 \
    "auto"   "Mesa only — safe default for Intel/AMD" \
    "intel"  "Intel: VA-API + Vulkan drivers" \
    "amd"    "AMD: VA-API + Vulkan (RADV)" \
    "nvidia" "NVIDIA proprietary (enables nonfree repo)" \
    "none"   "Install nothing extra")" || wizard_abort
  if [ "$GPU_DRIVER" = nvidia ] && ! in_list nonfree "$EXTRAS"; then
    EXTRAS+=" nonfree"
    [ "${NO_DIALOG:-no}" = yes ] || ui_msg "nonfree repo enabled automatically for NVIDIA." 8 60
  fi

  # consumed by configure.sh (display manager setup)
  # shellcheck disable=SC2034
  LOGIN_MANAGER="$(ui_menu "Login manager (advanced):" 17 76 6 \
    "auto"    "Per desktop (DEs get their DM, WMs start from tty)" \
    "none"    "No display manager (startx / start manually)" \
    "lightdm" "LightDM (X11, lightweight)" \
    "sddm"    "SDDM (Qt, X11 + Wayland sessions)" \
    "gdm"     "GDM (GNOME, X11 + Wayland)" \
    "greetd"  "greetd + tuigreet (text greeter, Wayland-friendly)")" || wizard_abort
}

step_mirror() {
  local choice
  choice="$(ui_menu "Package mirror:" 13 66 3 \
    "auto"    "Test and use the fastest mirror" \
    "default" "repo-default.voidlinux.org" \
    "custom"  "Enter a mirror URL")" || wizard_abort
  case "$choice" in
    auto)
      ui_msg "Testing mirror speeds — this takes a few seconds..." 8 60
      MIRROR="$(pick_fastest_mirror)"
      [ -n "$MIRROR" ] || { MIRROR="$DEFAULT_MIRROR"; ui_msg "No mirror responded, using default." 8 60; }
      ;;
    default) MIRROR="$DEFAULT_MIRROR" ;;
    custom)
      MIRROR="$(ui_input "Mirror base URL:" 9 74 "$DEFAULT_MIRROR")" || wizard_abort
      MIRROR="${MIRROR%/}"
      ;;
  esac
}

wizard_summary() {
  local luks_txt="no" swap_txt="none"
  [ "$LUKS" = yes ] && luks_txt="yes (LUKS2)"
  [ "$SWAP_MB" -gt 0 ] && swap_txt="${SWAP_MB} MiB"
  local dm_txt; dm_txt="$(effective_dm)"
  [ -n "$dm_txt" ] || dm_txt="none (tty)"
  local desk_txt="$DESKTOP"
  [ "$DESKTOP" = hyprland ] && desk_txt="$DESKTOP (community repo)"
  ui_msg "Installation summary
------------------------------------------
Disk:       $DISK  [$([ "$UEFI" = yes ] && echo UEFI || echo BIOS)]
Filesystem: $FILESYSTEM   Swap: $swap_txt
Encryption: $luks_txt
Mirror:     $MIRROR

Hostname:   $HOSTNAME
User:       $USERNAME   (wheel/sudo)
Timezone:   $TIMEZONE    Locale: $LOCALE    Keymap: $KEYMAP

Session:    $SESSION stack
Desktop:    $desk_txt
Login:      $dm_txt   GPU: $GPU_DRIVER
Extras:    $EXTRAS

$DISK WILL BE COMPLETELY ERASED." 27 78
  ui_yesno "Start the installation now?" 8 50 || die "Aborted before installation."
}

wizard_run_install() {
  say "=== installation started ==="
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
  run "Saving install log" cp "$LOGFILE" "$TARGET/var/log/voidc-install.log"
  disable_host_extra_repo
  say "=== installation finished ==="
}

wizard_finish() {
  sync
  local msg
  msg="Installation complete!

Bootloader: $([ "$UEFI" = yes ] && echo 'GRUB (UEFI)' || echo 'GRUB (BIOS)')
Desktop:    $DESKTOP
User:       $USERNAME
Log:        /var/log/voidc-install.log

"
  if desktop_uses_startx; then
    msg+="Log in as $USERNAME and run:  startx\n"
    [ "$AUTOSTART_DESKTOP" = yes ] && msg+="(X starts automatically on tty1)\n"
  elif desktop_uses_wayland; then
    msg+="Log in as $USERNAME and run:  dbus-run-session -- $(desktop_session_cmd)\n"
    [ "$AUTOSTART_DESKTOP" = yes ] && msg+="(Wayland session starts automatically on tty1)\n"
  fi
  local dm; dm="$(effective_dm)"
  [ -n "$dm" ] && msg+="Display manager: $dm\n"
  ui_msg "$msg" 16 64

  if ui_yesno "Unmount everything and reboot now?" 8 60; then
    unmount_all
    printf '\033[1;32mRebooting...\033[0m\n'
    reboot
  else
    ui_msg "Target left mounted at $TARGET.\nYou can chroot with:  chroot $TARGET /bin/bash" 9 64
  fi
}

run_wizard() {
  trap wizard_abort INT
  wizard_preflight
  step_welcome
  step_session
  step_disk
  step_filesystem
  step_swap
  step_luks
  step_identity
  step_desktop
  step_extras
  step_advanced
  step_mirror
  wizard_summary
  if ! ( wizard_run_install ); then
    ui_msg "INSTALLATION FAILED.

Last log lines:
$(tail -n 6 "$LOGFILE" 2>/dev/null | cut -c1-70)

Full log: $LOGFILE
Target may be left mounted — inspect with: mount | grep $TARGET" 20 76
    exit 1
  fi
  wizard_finish
}
