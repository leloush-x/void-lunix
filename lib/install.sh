#!/usr/bin/env bash
# voidc — target preparation and package installation (single transaction).
# Consumes: TARGET MIRROR LIBC UEFI UCODE DESKTOP EXTRAS LUKS FILESYSTEM

# Fallback map: if key is missing from the repos, use value instead.
declare -A PKG_FALLBACK=(
  [i3-gaps]=i3
  [network-manager-applet]=network-manager-applet
  [pipewire-pulse]=pipewire
  [vsv]=runit
)

prepare_target() {
  run "Creating target directories" mkdir -p "$TARGET/etc/xbps.d" "$TARGET/var/db/xbps" "$TARGET/dev" "$TARGET/proc" "$TARGET/sys" "$TARGET/run"

  # repository configuration (skip lines pointing at live-media/local repos)
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
  if in_list multilib "$EXTRAS" && [ "$LIBC" = glibc ]; then
    printf 'repository=%s/multilib\n' "$base_url" >"$TARGET/etc/xbps.d/20-repository-multilib.conf"
  fi

  # DNS for chroot configuration stage
  run "Copying resolv.conf" cp -L /etc/resolv.conf "$TARGET/etc/resolv.conf"
  verb "target prepared (mirror: $base_url)"
}

extras_pkgs() {
  local out=""
  in_list audio     "$EXTRAS" && out+=" pipewire wireplumber pipewire-pulse alsa-utils rtkit pavucontrol"
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
  out+=" $(extras_pkgs)"
  out+=" ${UCODE[*]:-}"

  if [ "$UEFI" = yes ]; then
    out+=" grub-x86_64-efi efibootmgr"
  else
    out+=" grub-i386-pc"
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

  local pkg alt
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
  verb "package installation complete"
}
