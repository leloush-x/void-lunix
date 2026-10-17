# voidc — Void Custom Installer (`void-lunix`)

A fast, clean, text-based installer for **Void Linux** — built to replace the
default `void-installer` with a better TUI, sane defaults, and a one-shot
package transaction.

```
 ============================
  Void Custom Installer v1.1.0
 ============================
  - GPT partitioning (UEFI + BIOS), optional LUKS
  - Single-transaction package install (fast)
  - X11 / Wayland session stacks
  - i3 bspwm dwm openbox awesome qtile xfce lxqt mate cinnamon budgie
  - KDE GNOME Hyprland niri Sway River Wayfire Labwc
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
  (with nonfree/multilib enabled first, so nothing is missed) before install;
  missing ones are skipped with a warning and known renames (`i3-gaps` → `i3`)
  are applied automatically. Critical packages (`base-system`, `grub`,
  `efibootmgr`, `cryptsetup`) hard-fail the install instead — before the disk
  is touched — rather than yield an unbootable system.
- **Automatic microcode + firmware** (intel/amd-ucode, linux-firmware).
- **Filesystems**: ext4, btrfs, XFS or F2FS, optional swap (auto/preset/custom
  size), optional **LUKS2** root.
- **Bootloader**: GRUB for UEFI and BIOS, generated for your layout.
- **User setup**: sudo/wheel user, services enabled (dbus, elogind,
  NetworkManager, rtkit), keyboard for console + X.
- **Audio** follows the official Void handbook: `pipewire` + `wireplumber`,
  with system config drop-ins that make `pipewire` launch the session manager
  and the PulseAudio server; every session starts it with a D-Bus session bus
  (greetd gets a `dbus-run-session` wrapper).
- **Ricing presets**: i3 + polybar and Hyprland/niri/Sway + Waybar (plus rofi/wofi,
  picom, dunst/mako, alacritty/foot), a wallpaper, and **matugen**
  (repo → prebuilt release binary fallback).
- **Startx-ready X sessions** — plain X desktops (dwm, openbox, awesome, qtile,
  …) get a generated `~/.xinitrc`, so `startx` and the greetd wrapper never
  drop you into the default twm/xterm session.
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
identity (hostname, user, passwords — all re-editable in a review step) →
desktop → extras → advanced (GPU, login manager) → mirror → summary →
install. Reboot at the end.

## Unattended install

```sh
cp profiles/i3.conf my.conf        # or profiles/niri.conf (Wayland)
$EDITOR my.conf                    # set DISK, passwords, etc.
./voidc --auto my.conf
```

See `profiles/` for every supported key.

> ⚠️ **Security — profiles are sourced as shell.** `voidc --auto foo.conf`
> runs `. foo.conf`, so only run profiles you trust: they can execute arbitrary
> commands as root. Leave `ROOT_PASS`/`USER_PASS`/`LUKS_PASSWORD` out of any
> profile you share, and never commit real passwords.

> **`--target` safety:** the target must be an absolute path under `/`; voidc
> refuses `/`, the running system (`/usr`, …) and any non-absolute path, so the
> default `/mnt` is always safe.

## Testing in a VM (recommended before real hardware)

The sandboxed suite (`tests/run.sh`) never touches a real disk, so the only
way to validate a full install is a VM. Minimum: 2 GiB RAM, 10 GiB disk,
UEFI or BIOS firmware.

```sh
# example with QEMU (UEFI)
qemu-img create -f qcow2 voidc.qcow2 12G
qemu-system-x86_64 -enable-kvm -m 2048 -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/ovmf/OVMF.fd \
  -cdrom void-live-x86_64-*.iso -drive file=voidc.qcow2,format=qcow2 \
  -boot d
```

Boot the live ISO, run `voidc --check`, then `voidc`. Logs land in
`/tmp/voidc-*.log` on the medium and `/var/log/voidc-install.log` in the
installed system. If the VM fails to boot, check Secure Boot (disable it),
the firmware mode (BIOS vs UEFI must match the install), and the LUKS
passphrase keyboard layout (the console defaults to US).

## Environment check (no changes)

```sh
./voidc --check
```

Prints firmware mode, libc, detected microcode, tool availability, disks,
target mount state and mirror reachability — handy before a real run.

## Tests (no disk changes)

```sh
tests/run.sh
```

Runs the whole install pipeline against stubbed system commands: scenario A
(BIOS + ext4 + i3 + greetd + extras), scenario B (UEFI + LUKS2 + Hyprland),
scenario C (the interactive wizard driven through a fake `dialog` with a
scripted answer queue — typed hostname/passwords, menus, checklist), scenario
D (a missing critical package must abort before the disk is touched) and
scenario E (NVIDIA: nonfree auto-enabled, driver in the transaction,
`nvidia_drm.modeset=1` on the GRUB cmdline), then ~248 assertions over the
produced target, installer logs and stub calls, plus unit tests (matugen
release fallback, filesystem matrix, `~/.xinitrc` generation, keymap → XKB
translation, the LUKS re-prompt loop, host repo URLs/cleanup), CLI smoke
tests (`--version`/`--help`/`--check`) and ShellCheck static analysis.
Details: `tests/README.md`.
CI runs it on x86_64 (glibc) and x86_64 (musl), with ShellCheck on both.

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

**Hyprland / niri / sway (Wayland)** — swaybg, Waybar, wofi, mako, foot:

```
~/.config/hypr/       hyprland.conf, hyprpaper, hypridle, hyprlock
~/.config/niri/       config.kdl (binds, gaps, autostarts, screenshots)
~/.config/sway/       sway config (gaps, Waybar, swayidle/swaylock)
~/.config/waybar/     config + style.css (no icon font required)
~/.config/wofi/       config + style.css (drun launcher)
~/.config/mako/       matching notifications
~/Pictures/wall.png   generated gradient wallpaper
```

Log in as your user and run `startx` (X11) or
`dbus-run-session -- Hyprland` / `niri` / `sway` (Wayland), or enable
auto-start on tty1 / a display manager in the wizard. Every generated session
starts PipeWire, and desktop environments pick it up from XDG autostart.

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
profiles/hyprland.conf example unattended profile (Hyprland, community repo)
assets/wall.png.b64   embedded wallpaper
tests/                sandboxed end-to-end dry run (tests/run.sh)
```

## Notes & caveats

- **i3-gaps** no longer exists as a package; duct taped via fallback to `i3`
  (upstream i3 has gaps built in since 4.22). The generated config uses
  `gaps`/`smart_gaps`, which work on both.
- **Hyprland** is not packaged in Void, so voidc installs it from the
  **hyprland-void** community repo (github.com/Makrennel/hyprland-void). When
  you pick Hyprland it enables that repo on the live system *and* in the
  installed system — with the right branch for your libc
  (x86_64 × glibc/musl) — so `hyprland`, `hyprpaper`, `hypridle`,
  `xdg-desktop-portal-hyprland` install normally; `hyprlock` is usually *not*
  available in the community repo and is skipped (install it later from the
  Void repos or build it). This is
  third-party software not shipped by Void: use it only if you trust it.
- **Hyprland seat errors**: if Hyprland reports a seat/DRM permission error,
  enable seatd (`ln -s /etc/sv/seatd /var/service`), start it and add your
  user to the `_seatd` group (per the hyprland-void README).
- **Package names are verified against the live Void index** before install
  (`Waybar` is capital-W in Void, for example) and missing packages are
  skipped with a warning — no half-broken transactions. The mirror probe and
  repo paths also handle the musl layout (`/current/musl`,
  `x86_64-musl-repodata`).
- **Bootloader is firmware-aware**: UEFI installs use `grub-x86_64-efi` and
  `--target=x86_64-efi` (or `grub-i386-efi` / `i386-efi` on 32-bit UEFI
  firmware); legacy BIOS uses GRUB i386-pc.
- **x86_64 only**: the architecture is checked up front; unsupported systems
  stop early with a clear message.
- **matugen** installs from the Void repos in the main transaction. If it is
  ever missing there, the installer falls back to the latest prebuilt GitHub
  release binary (`/usr/local/bin`) with arch/libc-aware asset matching, and
  skips it gracefully if neither source works.
- **NVIDIA**: choosing the NVIDIA driver enables the nonfree repo and installs
  `nvidia` + Vulkan (plus `nvidia-libs-32bit` via multilib on glibc). voidc
  adds `nvidia_drm.modeset=1` to the kernel command line automatically;
  `nvidia_drm.fbdev=1` can further help on some systems — see the Void docs.
- **greetd**: `tuigreet` reads available sessions (F3) and remembers your
  username; the cache directory is created automatically.
- **Wayland sessions** pull in XWayland so X11 apps keep working.
- **LUKS**: only the root filesystem is encrypted; `/boot` stays unencrypted
  (single passphrase prompt at boot). Swap is disabled when LUKS is on.
- **Swap**: `auto` = system RAM capped at 4 GiB; presets are 2/4/8 GiB or a
  typed custom size of 64-65536 MiB. Swap serves memory pressure only —
  suspend-to-disk is not configured (no `resume=` kernel parameter).
- **Unattended multilib** is auto-enabled on glibc x86_64 when a desktop or the
  NVIDIA driver is selected. (Profiles are sourced as shell — see
  [Unattended install](#unattended-install).)
- **BIOS installs** create a 1 MiB `bios_grub` partition for GRUB.
- **Every device is `wipefs`-cleaned** — the disk and each new partition —
  before formatting, so leftover RAID/LVM/LUKS signatures can't survive.
- Target is mounted at `/mnt` by default. `--target` must be an absolute path
  under `/`; voidc refuses `/`, `/usr` and other running-system directories.
- Full logs: `/tmp/voidc-*.log` on the live medium, copied to
  `/var/log/voidc-install.log` on the installed system.
- Unattended profiles contain plain-text passwords — keep them off any repo.

## Roadmap

- Manual partitioning (use your own partitions)
- WireGuard/SSH keys injection
- Remastering helper: bake voidc into a custom ISO

## License

MIT — see [LICENSE](LICENSE).
