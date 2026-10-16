# voidc — Void Custom Installer (`void-lunix`)

A fast, clean, text-based installer for **Void Linux** — built to replace the
default `void-installer` with a better TUI, sane defaults, and a one-shot
package transaction.

```
 ============================
  Void Custom Installer v1.0
 ============================
  - GPT partitioning (UEFI + BIOS), optional LUKS
  - Single-transaction package install (fast)
  - X11 / Wayland session stacks
  - i3 bspwm dwm openbox awesome qtile xfce lxqt mate cinnamon budgie
  - KDE GNOME niri Sway River Wayfire Labwc
  - Ricing presets: polybar, Waybar, rofi, wofi, picom, dunst, mako, matugen
```

## Features

- **Interactive TUI wizard** (dialog) — clean arrows/tab navigation, no raw questions.
- **Unattended mode** — one profile file, zero prompts (`--auto profiles/i3.conf`).
- **Session stacks** — pick X11 / Wayland / any, and the desktop list adapts.
- **Advanced config** — GPU drivers (Intel/AMD/NVIDIA), login manager
  (auto / none / LightDM / SDDM / GDM / greetd+tuigreet).
- **Fast installs** — all packages in a *single* `xbps-install` transaction,
  automatic fastest-mirror detection, no needless reconfiguration passes.
- **Smarter package handling** — packages are checked against the repo index
  before install; missing ones are skipped with a warning and known renames
  (`i3-gaps` → `i3`) are applied automatically.
- **Automatic microcode + firmware** (intel/amd-ucode, linux-firmware).
- **Filesystems**: ext4 or btrfs, optional swap, optional **LUKS2** root.
- **Bootloader**: GRUB for UEFI and BIOS, generated for your layout.
- **User setup**: sudo/wheel user, services enabled (dbus, elogind,
  NetworkManager, per-user PipeWire via runit), keyboard for console + X.
- **Ricing presets**: i3 + polybar and niri/Sway + Waybar (plus rofi/wofi,
  picom, dunst/mako, alacritty/foot), a wallpaper, and **matugen**
  (repo → prebuilt release binary fallback).
- **Dotfiles**: optionally clone your dotfiles repo (and run its installer).

## Quick start (Void live ISO)

Boot the official Void live ISO (root shell on tty1), get online
(`dhcpcd` is already running; for Wi-Fi use `wpa_supplicant` or run the
default installer once to configure networking), then:

```sh
git clone https://github.com/leloush-x/void-lunix.git
cd void-lunix
./voidc
```

No git on the image? Use curl:

```sh
curl -fsSL https://github.com/leloush-x/void-lunix/archive/refs/heads/main.tar.gz | tar xz
cd void-lunix-main
./voidc
```

Then follow the wizard: session stack → disk → filesystem → swap → LUKS →
hostname/user → desktop → extras → advanced (GPU, login manager) → mirror →
summary → install. Reboot at the end.

## Unattended install

```sh
cp profiles/i3.conf my.conf        # or profiles/niri.conf (Wayland)
$EDITOR my.conf                    # set DISK, passwords, etc.
./voidc --auto my.conf
```

See `profiles/` for every supported key.

## Environment check (no changes)

```sh
./voidc --check
```

Prints firmware mode, libc, detected microcode, tool availability, disks,
target mount state and mirror reachability — handy before a real run.

## Ricing presets

The wizard generates working configs for the preset desktops (all safe to
replace with your own dotfiles).

**i3 / bspwm (X11)** — picom, alacritty, rofi, polybar, dunst, feh:

```
~/.xinitrc            exec dbus-run-session -- i3
~/.config/i3/config   Mod4, gaps, media keys, Catppuccin-ish colors
~/.config/bspwm/      bspwmrc + sxhkdrc
~/.config/polybar/    config.ini + launch.sh (no icon font required)
~/.config/rofi/       config.rasi (drun launcher)
~/.config/picom/      rounded corners, shadows, fading
~/.config/dunst/      matching notifications
~/.config/alacritty/  alacritty.toml
~/Pictures/wall.png   generated gradient wallpaper (feh --bg-fill)
```

**niri / sway (Wayland)** — swaybg, Waybar, wofi, mako, foot:

```
~/.config/niri/       config.kdl (binds, gaps, autostarts, screenshots)
~/.config/sway/       sway config (gaps, Waybar, swayidle/swaylock)
~/.config/waybar/     config + style.css (no icon font required)
~/.config/wofi/       config + style.css (drun launcher)
~/.config/mako/       matching notifications
~/Pictures/wall.png   generated gradient wallpaper
```

Log in as your user and run `startx` (X11) or `niri` / `sway` (Wayland),
or enable auto-start on tty1 / a display manager in the wizard. Per-user
PipeWire/WirePlumber services are enabled through runit (`runsvdir-$USER`).

## Repository layout

```
voidc                 entry point (TUI + CLI)
lib/common.sh         logging, dialog UI, command runners
lib/detect.sh         firmware/libc/CPU/disk detection, mirror speed test
lib/partition.sh      GPT layout, LUKS, mkfs, mounts, fstab
lib/install.sh        repo config, package resolution, xbps transaction
lib/configure.sh      chroot config: locale, users, services, dracut
lib/boot.sh           GRUB (UEFI + BIOS)
lib/desktop.sh        session stacks, WM/DE package sets, DMs, GPU drivers
lib/rice.sh           X11 rice: i3/bspwm presets, matugen, dotfiles, wallpaper
lib/rice-wayland.sh   Wayland rice: hyprland/sway presets, waybar/wofi/mako
lib/wizard.sh         interactive flow
lib/auto.sh           unattended flow
profiles/i3.conf      example unattended profile (X11)
profiles/niri.conf    example unattended profile (Wayland)
profiles/hyprland.conf source-build-only Hyprland profile (see caveats)
assets/wall.png.b64   embedded wallpaper
```

## Notes & caveats

- **i3-gaps** no longer exists as a package; duct taped via fallback to `i3`
  (upstream i3 has gaps built in since 4.22). The generated config uses
  `gaps`/`smart_gaps`, which work on both.
- **Hyprland is not packaged in Void** (verified against `void-packages` and
  the official package API — only `hyprpicker` exists). The wizard offers
  **niri** instead, which is the closest popular Wayland ricer on Void. The
  Hyprland config generator and `profiles/hyprland.conf` are kept for people
  who build the stack from source.
- **Package names are verified against the live Void index** before install
  (`Waybar` is capital-W in Void, for example) and missing packages are
  skipped with a warning — no half-broken transactions.
- **matugen** is not in the Void repos (yet): the installer downloads the
  latest prebuilt release binary to `/usr/local/bin`. For a musl system it
  picks the musl build. If GitHub is unreachable it's skipped gracefully.
- **NVIDIA**: choosing the NVIDIA driver enables the nonfree repo and installs
  `nvidia` + Vulkan; on Wayland/Hyprland you may need kernel params
  (`nvidia_drm.modeset=1 nvidia_drm.fbdev=1`) — see the Void docs.
- **greetd**: `tuigreet` reads available sessions (F3) and remembers your
  username; the cache directory is created automatically.
- **Wayland sessions** pull in XWayland so X11 apps keep working.
- **LUKS**: only the root filesystem is encrypted; `/boot` stays unencrypted
  (single passphrase prompt at boot). Swap is disabled when LUKS is on.
- **BIOS installs** create a 1 MiB `bios_grub` partition for GRUB.
- Target is mounted at `/mnt` by default (`--target` to change it).
- Full logs: `/tmp/voidc-*.log` on the live medium, copied to
  `/var/log/voidc-install.log` on the installed system.
- Unattended profiles contain plain-text passwords — keep them off any repo.

## Roadmap

- Manual partitioning (use your own partitions)
- WireGuard/SSH keys injection
- Remastering helper: bake voidc into a custom ISO

## License

MIT — see [LICENSE](LICENSE).
