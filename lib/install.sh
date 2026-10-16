#!/usr/bin/env bash
# voidc — target preparation and package installation (single transaction).
# Consumes: TARGET MIRROR LIBC UEFI UCODE DESKTOP EXTRAS LUKS FILESYSTEM

# Fallback map: if key is missing from the repos, use value instead.
declare -A PKG_FALLBACK=(
  [i3-gaps]=i3
  [waybar]=Waybar
  [amd-ucode]=linux-firmware-amd
  [pipewire-pulse]=pipewire
  [vsv]=runit
)

# Extra repos (nonfree, multilib and third-party ones like Hyprland's) are
# enabled on the live system before the package check and the install
# transaction, and written into the target. Every file added here is removed
# again when the install finishes — or when it aborts.
DESKTOP_EXTRA_CONF="30-repository-desktop.conf"
HOST_REPO_FILES=""
# live-system repo conf directory (overridable so unit tests can run unprivileged)
HOST_XBPS_DIR="${HOST_XBPS_DIR:-/etc/xbps.d}"

host_repo_add() { # host_repo_add <filename> <url>
  mkdir -p "$HOST_XBPS_DIR"
  printf 'repository=%s\n' "$2" >"$HOST_XBPS_DIR/$1"
  HOST_REPO_FILES+=" $1"
}

enable_host_extra_repo() {
  local base_url url
  base_url="$(repo_url "$MIRROR")"
  if in_list nonfree "$EXTRAS"; then
    host_repo_add 20-repository-nonfree.conf "$base_url/nonfree"
    verb "nonfree repository enabled on live system"
  fi
  if in_list multilib "$EXTRAS" && [ "${XBPS_ARCH:-x86_64}" = x86_64 ]; then
    host_repo_add 20-repository-multilib.conf "$base_url/multilib"
    verb "multilib repository enabled on live system"
  fi
  if url="$(desktop_extra_repo_url)"; then
    host_repo_add "$DESKTOP_EXTRA_CONF" "$url"
    verb "extra repository enabled on live system: $url"
    # early, actionable warning if the third-party repo is unreachable
    if command -v curl >/dev/null 2>&1 && \
       ! curl -fsI -m 10 "$url/${XBPS_ARCH:-x86_64}-repodata" >>"$LOGFILE" 2>&1; then
      note "Warning: $url looks unreachable — packages from it may be skipped."
      warnlog "extra repository unreachable: $url/${XBPS_ARCH:-x86_64}-repodata"
    fi
  fi
}

disable_host_extra_repo() {
  local f
  for f in ${HOST_REPO_FILES:-}; do rm -f "$HOST_XBPS_DIR/$f"; done
  HOST_REPO_FILES=""
}

prepare_target() {
  run "Creating target directories" mkdir -p "$TARGET/etc/xbps.d" "$TARGET/var/db/xbps" "$TARGET/dev" "$TARGET/proc" "$TARGET/sys" "$TARGET/run"

  # repository configuration (host confs added earlier — nonfree, multilib,
  # desktop extra repo — are copied along; skip live-media/local repos)
  local f base
  for f in /etc/xbps.d/*.conf; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"
    [ "$base" = "00-repository-main.conf" ] && continue
    grep -vE '^[[:space:]]*repository=.*(localhost|127\.0\.0\.1|file:)' "$f" \
      >"$TARGET/etc/xbps.d/$base" 2>/dev/null || true
    [ -s "$TARGET/etc/xbps.d/$base" ] || rm -f "$TARGET/etc/xbps.d/$base"
  done

  local base_url; base_url="$(repo_url "$MIRROR")"
  printf 'repository=%s\n' "$base_url" >"$TARGET/etc/xbps.d/00-repository-main.conf"

  if in_list nonfree "$EXTRAS"; then
    printf 'repository=%s/nonfree\n' "$base_url" >"$TARGET/etc/xbps.d/20-repository-nonfree.conf"
  fi
  if in_list multilib "$EXTRAS" && [ "${XBPS_ARCH:-x86_64}" = x86_64 ]; then
    printf 'repository=%s/multilib\n' "$base_url" >"$TARGET/etc/xbps.d/20-repository-multilib.conf"
  fi

  local extra_url
  if extra_url="$(desktop_extra_repo_url)"; then
    printf 'repository=%s\n' "$extra_url" >"$TARGET/etc/xbps.d/$DESKTOP_EXTRA_CONF"
    verb "extra repository in target: $extra_url"
  fi

  # repository signing keys (xbps imports them on first sync too; copying the
  # live ones is belt & braces, same as the official void-installer does)
  if [ -d /var/db/xbps/keys ]; then
    mkdir -p "$TARGET/var/db/xbps/keys"
    cp -a /var/db/xbps/keys/. "$TARGET/var/db/xbps/keys/" 2>/dev/null || true
    verb "repo keys copied into target"
  fi

  # DNS for chroot configuration stage
  run "Copying resolv.conf" cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"
  verb "target prepared (mirror: $base_url)"
}

extras_pkgs() {
  local out=""
  in_list audio     "$EXTRAS" && out+=" pipewire wireplumber alsa-utils rtkit pavucontrol"
  in_list networking "$EXTRAS" && out+=" NetworkManager network-manager-applet"
  in_list bluetooth "$EXTRAS" && out+=" bluez blueman"
  in_list printing  "$EXTRAS" && out+=" cups cups-filters"
  in_list fonts     "$EXTRAS" && out+=" dejavu-fonts-ttf noto-fonts-emoji nerd-fonts-ttf font-awesome"
  in_list ssh       "$EXTRAS" && out+=" openssh"
  out+=" chrony ca-certificates linux-firmware"
  printf '%s\n' "$out"
}

build_pkg_list() {
  local out="base-system sudo dbus elogind polkit"
  out+=" $(desktop_pkgs)"
  out+=" $(desktop_dm_pkgs)"
  out+=" $(gpu_pkgs)"
  out+=" $(extras_pkgs)"
  out+=" ${UCODE[*]:-}"

  if [ "$UEFI" = yes ]; then
    local efi_grub="grub-x86_64-efi"
    case "$(efi_target)" in
      i386-efi) efi_grub="grub-i386-efi" ;;
    esac
    out+=" grub $efi_grub efibootmgr"
  else
    out+=" grub"
  fi
  [ "$LUKS" = yes ] && out+=" cryptsetup"

  printf '%s\n' "$out" | tr -s ' ' '\n' | sed '/^$/d' | sort -u | tr '\n' ' '
}

# resolve_pkgs — sync remote index, drop missing packages, apply fallbacks.
# Sets global PKGS (space separated) and PKGS_SKIPPED.
resolve_pkgs() {
  local requested
  requested="$(build_pkg_list)"
  verb "requested packages: $requested"

  say "Syncing package index"
  run "Syncing xbps index" xbps-install -S

  local pkg
  PKGS=""; PKGS_SKIPPED=""
  for pkg in $requested; do
    if pkg_exists_remote "$pkg"; then
      PKGS+="$pkg "
    elif [ -n "${PKG_FALLBACK[$pkg]:-}" ] && pkg_exists_remote "${PKG_FALLBACK[$pkg]}"; then
      warnlog "package '$pkg' missing -> using '${PKG_FALLBACK[$pkg]}'"
      PKGS+="${PKG_FALLBACK[$pkg]} "
    else
      warnlog "package not in repositories, skipped: $pkg"
      PKGS_SKIPPED+="$pkg "
    fi
  done

  # packages the installed system cannot boot without: never skip silently
  local c critical="base-system grub"
  [ "$UEFI" = yes ] && critical+=" efibootmgr"
  [ "$LUKS" = yes ] && critical+=" cryptsetup"
  for c in $critical; do
    case " $PKGS_SKIPPED " in
      *" $c "*) die "Critical package '$c' is missing from the repositories — install aborted." ;;
    esac
  done

  # dedup (fallbacks may duplicate)
  PKGS="$(printf '%s\n' $PKGS | sort -u | tr '\n' ' ')"
  verb "resolved packages: $PKGS"
  [ -n "$PKGS_SKIPPED" ] && verb "skipped packages: $PKGS_SKIPPED"
}

install_packages() {
  # shellcheck disable=SC2086
  ui_gauge_run " Installing packages " "Downloading and installing ($(printf '%s\n' $PKGS | wc -l) packages)..." "$LOGFILE" \
    xbps-install -Sy -y -r "$TARGET" $PKGS \
    || die "Package installation failed — see $LOGFILE"

  [ -x "$TARGET/usr/bin/xbps-install" ] || [ -x "$TARGET/usr/bin/xbps-query" ] \
    || die "Base system does not look installed under $TARGET."

  # base-files' INSTALL script fixes ownership/permissions for -r installs
  # (the official void-installer does the same before entering the chroot)
  try xbps-reconfigure -r "$TARGET" -f base-files

  verb "package installation complete"
}
