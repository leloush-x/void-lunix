# voidc tests

Sandboxed end-to-end verification of the installer pipeline. **No real disks,
partitions, packages or services are touched** — every system-mutating command
(`xbps-*`, `parted`, `cryptsetup`, `chroot`, `grub-*`, …) is replaced by a stub
in `/tmp/stubbin`, and the installs run against throwaway targets under `/tmp`.

## Run

```sh
tests/run.sh
```

Requirements: bash, coreutils, tar, curl. Network is optional — repo probes
and the matugen fallback degrade to warnings when offline.

## What is covered

- **Scenario A** (`dry_a.sh`) — the real `voidc --auto` entry point:
  BIOS + ext4 + i3 + greetd + autostart + extras (audio, networking,
  bluetooth, printing, fonts, ssh, nonfree, multilib). Verifies the partition
  calls, the single `xbps-install` transaction, target configuration
  (hostname, users/sudo, fstab, repo confs, locale, keymap, pipewire),
  GRUB BIOS, generated i3/polybar/rofi/picom configs, `.xinitrc`, wallpaper
  and the install-log copy.
- **Scenario B** (`dry_b.sh`) — UEFI + LUKS2 + Hyprland + greetd, mirroring
  `run_auto()`. Verifies ESP partitioning, `luksFormat`/`open`, mapper mount,
  arch-aware UEFI GRUB (`arm64-efi` on aarch64, `x86_64-efi` on x86_64),
  dracut crypt config, the greetd `dbus-run-session` wrapper,
  Hyprland/Waybar/Wofi configs, and the Hyprland community-repo
  enable/cleanup.
- **`check_dry.sh`** — ~90 assertions over the produced target filesystems,
  installer logs and stub-call logs. Arch/libc aware.
- **`matugen-fallback.sh`** — unit test for the GitHub release fallback
  (fake curl, no network): plain/musl asset preference and the no-asset skip.

## Sandbox relaxations (only applied to the `/tmp/drysrc` copy)

- `[ -b "$DISK" ]` → `[ -e "$DISK" ]` in `lib/auto.sh` / `lib/partition.sh`
  (containers cannot create block-device nodes; `/tmp/fakedisk` is a file).
- Scenario B forces `UEFI=yes` (no EFI firmware in a container).
- Scenario A simulates BIOS on whatever arch the host is — on aarch64 the
  early `check_firmware_support` guard is turned into a warning in the copy
  (BIOS GRUB is x86-only, so this scenario is a simulation there).

## Notes

- The dry runs call `enable_host_extra_repo()`, which writes **and removes**
  `/etc/xbps.d/30-repository-desktop.conf` on the running system.
- The `xbps-uhelper` stub fails on purpose, so arch/libc detection falls back
  to `uname -m` + the musl loader check — the same code path used on systems
  without xbps. Expectations adapt to `uname -m` and glibc/musl.
- Logs: `/tmp/dry_a.log`, `/tmp/dry_b.log`; stub calls: `/tmp/stub_a.log`,
  `/tmp/stub_b.log`.

## CI

GitHub Actions (`.github/workflows/tests.yml`) runs this suite on:

- `ubuntu-latest` (x86_64 · glibc)
- `ubuntu-24.04-arm` (aarch64 · glibc)
- `voidlinux/voidlinux-musl` container (x86_64 · musl) — the musl job clones
  with `git` because `actions/checkout`'s Node.js runtime does not run on musl.
