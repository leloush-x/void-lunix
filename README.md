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
  - i3 / bspwm / dwm / openbox / sway / XFCE / KDE / GNOME / Cinnamon / MATE
  - Ricing-ready: polybar, rofi, picom, dunst, alacritty, matugen
```

## Features

- **Interactive TUI wizard** (dialog) — clean arrows/tab navigation, no raw questions.
- **Unattended mode** — one profile file, zero prompts (`--auto profiles/i3.conf`).
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
- **Ricing-ready i3**: generates a working i3 + polybar + rofi + picom + dunst +
  alacritty setup, a wallpaper, `.xinitrc`, and installs **matugen**
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

Then follow the wizard: disk → filesystem → swap → LUKS → hostname/user →
desktop → extras → mirror → summary → install. Reboot at the end.

## Unattended install

```sh
cp profiles/i3.conf my.conf
$EDITOR my.conf        # set DISK, passwords, etc.
./voidc --auto my.conf
```

See `profiles/i3.conf` for every supported key.

## Environment check (no changes)

```sh
./voidc --check
```

Prints firmware mode, libc, detected microcode, tool availability, disks,
target mount state and mirror reachability — handy before a real run.

## What the `i3` desktop gets you

Xorg, i3 (with gaps — `i3-gaps` was merged upstream), picom, alacritty,
rofi, polybar, dunst, feh, pamixer, NetworkManager + applet, PipeWire,
WirePlumber, plus fonts, xdg-utils, maim (screenshots), brightnessctl.

Generated per-user configs under `~/.config/` (all safe to replace with your
own dotfiles):

```
~/.xinitrc            exec dbus-run-session -- i3
~/.config/i3/config   Mod4, gaps, media keys, Catppuccin-ish colors
~/.config/polybar/    config.ini + launch.sh (no icon font required)
~/.config/rofi/       config.rasi (drun launcher)
~/.config/picom/      rounded corners, shadows, fading
~/.config/dunst/      matching notifications
~/.config/alacritty/  alacritty.toml
~/Pictures/wall.png   generated gradient wallpaper (feh --bg-fill)
```

Log in as your user and run `startx` (or enable auto-start on tty1 in the
wizard). Per-user PipeWire/WirePlumber services are enabled through runit
(`runsvdir-$USER`).

## Repository layout

```
voidc                 entry point (TUI + CLI)
lib/common.sh         logging, dialog UI, command runners
lib/detect.sh         firmware/libc/CPU/disk detection, mirror speed test
lib/partition.sh      GPT layout, LUKS, mkfs, mounts, fstab
lib/install.sh        repo config, package resolution, xbps transaction
lib/configure.sh      chroot config: locale, users, services, dracut
lib/boot.sh           GRUB (UEFI + BIOS)
lib/desktop.sh        WM/DE package sets
lib/rice.sh           generated configs, matugen, dotfiles, wallpaper
lib/wizard.sh         interactive flow
lib/auto.sh           unattended flow
profiles/i3.conf      example unattended profile
assets/wall.png.b64   embedded wallpaper
```

## Notes & caveats

- **i3-gaps** no longer exists as a package; duct taped via fallback to `i3`
  (upstream i3 has gaps built in since 4.22). The generated config uses
  `gaps`/`smart_gaps`, which work on both.
- **matugen** is not in the Void repos (yet): the installer downloads the
  latest prebuilt release binary to `/usr/local/bin`. For a musl system it
  picks the musl build. If GitHub is unreachable it's skipped gracefully.
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
