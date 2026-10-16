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
  UEFI GRUB (`x86_64-efi`), dracut crypt config, the greetd
  `dbus-run-session` wrapper, Hyprland/Waybar/Wofi configs, and the Hyprland
  community-repo enable/cleanup.
- **Scenario C** (`dry_wizard.sh`) — the interactive wizard (the default
  `voidc` path) driven without a terminal: a fake `dialog` in `/tmp/wizbin`
  consumes one answer line per prompt from `/tmp/wiz_answers.txt` and logs
  every call to `/tmp/wiz_dialogs.log` (so a wiring mistake shows up as a
  desynchronized queue). The scripted session types a hostname/user, both
  password boxes, picks i3, checks a subset of extras, and drives every menu
  and confirmation — verifying that the *typed* answers land in the target
  (hostname, chpasswd ×2, keymap `de`, locale, checklist services on/off),
  that exactly 30 dialogs and 2 gauges are used, and that the queue is
  drained (no prompt missed, none extra).
- **`check_dry.sh`** — ~100 assertions over the produced target filesystems,
  installer logs and stub-call logs (x86_64/musl aware).
- **`matugen-fallback.sh`** — unit test for the GitHub release fallback
  (fake curl, no network): plain/musl asset preference and the no-asset skip.
- **`fs-matrix.sh`** — unit test for the root-filesystem matrix: the exact
  mkfs command per filesystem (ext4/btrfs/xfs/f2fs), the missing-tool hint,
  and the generated fstab (root passno, tmpfs /tmp, swap line).

## Sandbox relaxations (only applied to the `/tmp/drysrc` copy)

- `[ -b "$DISK" ]` → `[ -e "$DISK" ]` in `lib/auto.sh` / `lib/partition.sh`
  (containers cannot create block-device nodes; `/tmp/fakedisk` is a file).
- `UEFI` detection is neutralized: scenario A always runs BIOS (CI runners
  boot UEFI) and scenario B sets `UEFI=yes` itself (no EFI firmware in a
  container).

## Notes

- The dry runs call `enable_host_extra_repo()`, which writes **and removes**
  `/etc/xbps.d/30-repository-desktop.conf` on the running system.
- The `xbps-uhelper` stub reports a pinned `TEST_ARCH` (x86_64, or
  x86_64-musl inside the musl container), so the whole suite is deterministic
  on any host.
- Logs: `/tmp/dry_a.log`, `/tmp/dry_b.log`, `/tmp/dry_wizard.log`; stub calls:
  `/tmp/stub_a.log`, `/tmp/stub_b.log`, `/tmp/stub_w.log`; wizard dialog
  calls: `/tmp/wiz_dialogs.log`.

## CI

GitHub Actions (`.github/workflows/tests.yml`) runs this suite on:

- `ubuntu-latest` (x86_64 · glibc)
- `voidlinux/voidlinux-musl` container (x86_64 · musl) — the musl job clones
  with `git` because `actions/checkout`'s Node.js runtime does not run on musl.
