#!/usr/bin/env bash
# voidc — desktop environments & window managers package sets.
# Consumes: DESKTOP (and CUSTOM_PKGS for deskop=custom)

# common X/desktop base shared by lightweight window managers
_x_base="xorg xinit dbus elogind polkit mesa-dri libva-utils xdg-user-dirs xdg-utils bash-completion unzip wget"

# the user's ricing stack (matugen handled separately: repo -> binary fallback)
_i3_extra="i3status picom alacritty rofi polybar dunst feh pamixer pavucontrol polkit-gnome lxappearance maim slop brightnessctl git curl"

desktop_pkgs() {
  case "$DESKTOP" in
    none) printf '\n' ;;
    i3)
      printf '%s\n' "$_x_base $_i3_extra i3-gaps" ;;
    bspwm)
      printf '%s\n' "$_x_base $_i3_extra bspwm sxhkd" ;;
    dwm)
      printf '%s\n' "$_x_base dwm dmenu alacritty picom feh" ;;
    openbox)
      printf '%s\n' "$_x_base openbox obconf tint2 alacritty rofi feh dunst picom" ;;
    sway)
      printf '%s\n' "sway swayidle swaylock waybar alacritty foot fuzzel mako wl-clipboard grim slurp brightnessctl xdg-desktop-portal-wlr mesa-dri pipewire wireplumber xdg-user-dirs git curl" ;;
    xfce)
      printf '%s\n' "$_x_base xfce4 xfce4-goodies thunar lightdm lightdm-gtk-greeter firefox-esr" ;;
    kde)
      printf '%s\n' "$_x_base plasma-desktop sddm konsole dolphin firefox-esr" ;;
    gnome)
      printf '%s\n' "$_x_base gnome gnome-terminal gdm firefox-esr" ;;
    cinnamon)
      printf '%s\n' "$_x_base cinnamon nemo lightdm lightdm-gtk-greeter firefox-esr" ;;
    mate)
      printf '%s\n' "$_x_base mate mate-extra lightdm lightdm-gtk-greeter firefox-esr" ;;
    custom)
      printf '%s\n' "$CUSTOM_PKGS" ;;
    *)
      printf '\n' ;;
  esac
}

# does this desktop use our generated rice configs?
desktop_uses_rice() {
  case "$DESKTOP" in i3|bspwm) return 0 ;; *) return 1 ;; esac
}

# does this desktop start via startx (no display manager)?
desktop_uses_startx() {
  case "$DESKTOP" in i3|bspwm|dwm|openbox) return 0 ;; *) return 1 ;; esac
}

# display manager service for DEs that need one
desktop_dm_service() {
  case "$DESKTOP" in
    xfce|cinnamon|mate) printf 'lightdm\n' ;;
    kde)  printf 'sddm\n' ;;
    gnome) printf 'gdm\n' ;;
  esac
}
