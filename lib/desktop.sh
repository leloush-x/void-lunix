#!/usr/bin/env bash
# voidc — session stacks (X11/Wayland), WM/DE package sets, display managers, GPUs.
# Consumes: DESKTOP CUSTOM_PKGS SESSION/login type: LOGIN_MANAGER GPU_DRIVER

# classification
X11_ONLY="i3 bspwm dwm openbox awesome qtile xfce lxqt mate cinnamon budgie"
WAYLAND_ONLY="sway hyprland niri river wayfire labwc"
DUAL_STACK="kde gnome"

# shared package bases
_x_base="xorg xinit dbus elogind polkit mesa-dri xdg-user-dirs xdg-utils bash-completion unzip wget"
_wl_base="dbus elogind polkit mesa-dri xorg-server-xwayland xdg-user-dirs xdg-utils bash-completion unzip wget pipewire wireplumber"

# ricing stack for tiling WMs (matugen handled separately)
_rice_x="i3status picom alacritty rofi polybar dunst feh pamixer pavucontrol polkit-gnome lxappearance maim slop brightnessctl git curl"

desktop_pkgs() {
  case "$DESKTOP" in
    none)     printf '\n' ;;
    i3)       printf '%s\n' "$_x_base $_rice_x i3-gaps" ;;
    bspwm)    printf '%s\n' "$_x_base $_rice_x bspwm sxhkd" ;;
    dwm)      printf '%s\n' "$_x_base dwm dmenu alacritty picom feh" ;;
    openbox)  printf '%s\n' "$_x_base openbox obconf tint2 alacritty rofi feh dunst picom" ;;
    awesome)  printf '%s\n' "$_x_base awesome alacritty rofi picom feh" ;;
    qtile)    printf '%s\n' "$_x_base qtile alacritty rofi picom feh" ;;
    xfce)     printf '%s\n' "$_x_base xfce4 xfce4-goodies thunar firefox-esr" ;;
    lxqt)     printf '%s\n' "$_x_base lxqt-session lxqt-panel lxqt-config lxqt-runner lxqt-policykit pcmanfm-qt qterminal firefox-esr" ;;
    mate)     printf '%s\n' "$_x_base mate mate-extra firefox-esr" ;;
    cinnamon) printf '%s\n' "$_x_base cinnamon nemo firefox-esr" ;;
    budgie)   printf '%s\n' "$_x_base budgie-desktop gnome-terminal nautilus firefox-esr" ;;
    kde)      printf '%s\n' "$_x_base plasma-desktop konsole dolphin firefox-esr" ;;
    gnome)    printf '%s\n' "$_x_base gnome gnome-terminal firefox-esr" ;;
    sway)     printf '%s\n' "$_wl_base sway swaybg swayidle swaylock Waybar wofi mako foot wl-clipboard grim slurp brightnessctl xdg-desktop-portal-wlr" ;;
    niri)     printf '%s\n' "$_wl_base niri xwayland-satellite swayidle swaylock swaybg Waybar wofi mako foot wl-clipboard grim slurp brightnessctl xdg-desktop-portal-gtk" ;;
    hyprland) printf '%s\n' "$_wl_base hyprland hyprpaper hypridle hyprlock hyprpicker xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent Waybar wofi mako foot wl-clipboard grim slurp swaybg brightnessctl qt6ct" ;;
    river)    printf '%s\n' "$_wl_base river xdg-desktop-portal-wlr Waybar wofi mako foot wl-clipboard grim slurp swaybg brightnessctl polkit-gnome" ;;
    wayfire)  printf '%s\n' "$_wl_base wayfire wf-shell xdg-desktop-portal-wlr Waybar wofi mako foot wl-clipboard grim slurp swaybg brightnessctl polkit-gnome" ;;
    labwc)    printf '%s\n' "$_wl_base labwc xdg-desktop-portal-wlr Waybar wofi mako foot wl-clipboard grim slurp swaybg brightnessctl polkit-gnome" ;;
    custom)   printf '%s\n' "$CUSTOM_PKGS" ;;
    *)        printf '\n' ;;
  esac
}

# Extra third-party repository the selected desktop needs, if any.
# Hyprland is not packaged in Void; it ships via the hyprland-void community
# repo (github.com/Makrennel/hyprland-void), one branch per arch/libc.
# Prints the repository URL, or returns 1 when the desktop needs none.
desktop_extra_repo_url() {
  case "$DESKTOP" in
    hyprland)
      local arch="${XBPS_ARCH:-x86_64}" libc=glibc
      case "$arch" in *-musl) libc=musl; arch="${arch%-musl}" ;; esac
      printf 'https://raw.githubusercontent.com/Makrennel/hyprland-void/repository-%s-%s\n' "$arch" "$libc" ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------- properties ----
desktop_uses_rice() {
  case "$DESKTOP" in i3|bspwm|hyprland|sway|niri) return 0 ;; *) return 1 ;; esac
}
desktop_uses_startx() {
  case " $X11_ONLY " in *" $DESKTOP "*) return 0 ;; esac
  return 1
}
desktop_uses_wayland() {
  case " $WAYLAND_ONLY " in *" $DESKTOP "*) return 0 ;; esac
  return 1
}
desktop_allowed() { # desktop_allowed <tag> — filter for the chosen session stack
  local tag="$1" list=""
  case "$SESSION" in
    any) return 0 ;;
    x11)     list="$X11_ONLY $DUAL_STACK none custom" ;;
    wayland) list="$WAYLAND_ONLY $DUAL_STACK none custom" ;;
    *) return 0 ;;
  esac
  case " $list " in *" $tag "*) return 0 ;; esac
  return 1
}

# command a greeter/autostart should launch for each desktop
desktop_session_cmd() {
  case "$DESKTOP" in
    i3|bspwm|dwm|openbox|awesome|qtile) printf 'startx\n' ;;
    sway)     printf 'sway\n' ;;
    niri)     printf 'niri-session\n' ;;
    hyprland) printf 'Hyprland\n' ;;
    river)    printf 'river\n' ;;
    wayfire)  printf 'wayfire\n' ;;
    labwc)    printf 'labwc\n' ;;
    xfce)     printf 'startxfce4\n' ;;
    lxqt)     printf 'startlxqt\n' ;;
    mate)     printf 'mate-session\n' ;;
    cinnamon) printf 'cinnamon-session\n' ;;
    budgie)   printf 'budgie-desktop\n' ;;
    kde)      printf 'startplasma-x11\n' ;;
    gnome)    printf 'gnome-session\n' ;;
    *)        printf 'startx\n' ;;
  esac
}

# ------------------------------------------------------- display managers ----
# auto mapping: which DM a DE expects
desktop_dm_service() {
  case "$DESKTOP" in
    xfce|lxqt|mate|cinnamon|budgie) printf 'lightdm\n' ;;
    kde)  printf 'sddm\n' ;;
    gnome) printf 'gdm\n' ;;
    *) printf '\n' ;;
  esac
}

# the DM actually used, honoring LOGIN_MANAGER: auto|none|lightdm|sddm|gdm|greetd
effective_dm() {
  case "${LOGIN_MANAGER:-auto}" in
    auto)  desktop_dm_service ;;
    none)  printf '\n' ;;
    *)     printf '%s\n' "$LOGIN_MANAGER" ;;
  esac
}

desktop_dm_pkgs() {
  case "$(effective_dm)" in
    lightdm) printf 'lightdm lightdm-gtk-greeter\n' ;;
    sddm)    printf 'sddm\n' ;;
    gdm)     printf 'gdm\n' ;;
    greetd)  printf 'greetd tuigreet\n' ;;
    *)       printf '\n' ;;
  esac
}

# ------------------------------------------------------------------ GPUs -----
gpu_pkgs() {
  case "${GPU_DRIVER:-auto}" in
    auto|none) printf '\n' ;;
    intel)  printf 'mesa-vulkan-intel intel-media-driver\n' ;;
    amd)    printf 'mesa-vulkan-radeon mesa-vaapi\n' ;;
    nvidia) printf 'nvidia vulkan-loader vulkan-tools nvidia-libs-32bit\n' ;;
    *)      printf '\n' ;;
  esac
}

desktop_needs_nonfree() {
  [ "${GPU_DRIVER:-auto}" = nvidia ] && return 0
  return 1
}
