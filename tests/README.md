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
and the matugen fallback degrade to warnings when offline. ShellCheck is
optional locally (the step is skipped when it's not in `PATH`) and always
installed in CI.

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
- **Scenario D** (`dry_fail.sh`) — a critical package (`grub`) missing from
  the repositories must abort the install *before* the disk is touched:
  non-zero exit, a clear log message, no partitioning/transaction calls in the
  stub log, and the host repo conf added by `enable_host_extra_repo()` is
  cleaned up on the abort path.
- **Scenario E** (`dry_nvidia.sh`) — `GPU_DRIVER=nvidia` through the real
  `voidc --auto` pipeline: nonfree is auto-enabled (with a log line), the
  driver packages land in the single transaction, multilib is enabled on
  glibc only, and the generated GRUB cmdline contains
  `nvidia_drm.modeset=1`.
- **`check_dry.sh`** — ~120 assertions over the produced target filesystems,
  installer logs and stub-call logs (x86_64/musl aware), including per-device
  `wipefs` before every `mkfs`, the host repo conf lifecycle, and that the root
  account is never `passwd -l`-locked behind the set password.
- **`matugen-fallback.sh`** — unit test for the GitHub release fallback
  (fake curl, no network): plain/musl asset preference and the no-asset skip.
- **`fs-matrix.sh`** — unit test for the root-filesystem matrix: the exact
  mkfs command per filesystem (ext4/btrfs/xfs/f2fs), the missing-tool hint,
  and the generated fstab (root passno, tmpfs /tmp, swap line).
- **`xinitrc.sh`** — unit test for `~/.xinitrc` generation: every plain X
  desktop (dwm/openbox/awesome/qtile/xfce, no rice preset) gets a session
  file, Wayland desktops do not, and an existing `.xinitrc` (rice preset or
  user dotfiles) is never overwritten.
- **`units.sh`** — unit tests for: console keymap → XKB translation
  (`uk`→`gb`, `de-latin1`→`de`), the LUKS passphrase re-prompt loop (two
  cancels, then a real passphrase; swap disabled), swap allocation (wizard
  auto/preset/custom sizing with invalid-input re-prompts, and profile
  `SWAP_MB` validation `auto|0|64..65536`), the host repo conf lifecycle
  (nonfree/multilib URLs for glibc and musl, Hyprland repo conf, cleanup —
  confs go to a temp dir via `HOST_XBPS_DIR`), and every shipped profile
  (parses and declares `DISK`).
- **`smoke.sh`** — CLI surface: `--version`/`--help` exit 0 with the right
  output, unknown flags exit non-zero, and `--check` produces the environment
  report.
- **`shellcheck.sh`** — ShellCheck (warning level) over `voidc`, `lib/*.sh`
  and `tests/*.sh`; `run.sh` runs it automatically when ShellCheck is
  installed (CI always has it).

## Sandbox relaxations (only applied to the `/tmp/drysrc` copy)

- `[ -b "$DISK" ]` → `[ -e "$DISK" ]` in `lib/auto.sh` / `lib/partition.sh`
  (containers cannot create block-device nodes; `/tmp/fakedisk` is a file).
- `UEFI` detection is neutralized: scenario A always runs BIOS (CI runners
  boot UEFI) and scenario B sets `UEFI=yes` itself (no EFI firmware in a
  container).

## Notes

- The dry runs call `enable_host_extra_repo()`, which writes **and always
  removes** host repo confs in `/etc/xbps.d` (`30-repository-desktop.conf`,
  `20-repository-nonfree.conf`, `20-repository-multilib.conf`) — including on
  the abort path (scenario D).
- The `xbps-uhelper` stub reports a pinned `TEST_ARCH` (x86_64, or
  x86_64-musl inside the musl container), so the whole suite is deterministic
  on any host.
- Logs: `/tmp/dry_a.log`, `/tmp/dry_b.log`, `/tmp/dry_wizard.log`,
  `/tmp/dry_fail.log`, `/tmp/dry_e.log`; stub calls: `/tmp/stub_a.log`,
  `/tmp/stub_b.log`, `/tmp/stub_w.log`, `/tmp/stub_f.log`, `/tmp/stub_e.log`;
  wizard dialog calls: `/tmp/wiz_dialogs.log`.

## CI

GitHub Actions (`.github/workflows/tests.yml`) runs this suite on:

- `ubuntu-latest` (x86_64 · glibc)
- `voidlinux/voidlinux-musl` container (x86_64 · musl) — the musl job clones
  with `git` because `actions/checkout`'s Node.js runtime does not run on musl.

Both jobs run ShellCheck (preinstalled on the Ubuntu runner, installed via
`xbps` inside the musl container) before the sandbox suite.
