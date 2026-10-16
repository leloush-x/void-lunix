#!/usr/bin/env bash
# voidc — environment detection: firmware, libc, CPU, RAM, disks, mirrors.

# GRUB EFI target for the current machine: detection result when available,
# otherwise derived from the arch (used when UEFI is forced in tests).
efi_target() {
  if [ -n "${EFI_TARGET:-}" ]; then
    printf '%s\n' "$EFI_TARGET"
    return
  fi
  printf 'x86_64-efi\n'
}

detect_environment() {
  # firmware
  UEFI=no
  [ -d /sys/firmware/efi ] && UEFI=yes

  # arch + libc via xbps (falls back to uname, then to the musl loader)
  local arch from_xbps=yes
  arch="$(xbps-uhelper arch 2>/dev/null)" || from_xbps=no
  if [ -z "$arch" ]; then arch="$(uname -m)"; from_xbps=no; fi
  if [ "$from_xbps" = no ]; then
    case "$arch" in
      *musl*) ;;
      *) ls /lib/ld-musl-*.so.1 >/dev/null 2>&1 && arch="${arch}-musl" ;;
    esac
  fi
  XBPS_ARCH="$arch"
  LIBC=glibc
  case "$arch" in *musl*) LIBC=musl ;; esac
  case "$arch" in
    x86_64*) ;;
    *) die "Unsupported architecture: $arch — voidc supports x86_64 only." ;;
  esac

  # UEFI: GRUB target triple. 32-bit x86 UEFI firmware is real (tablets,
  # older Macs) and needs --target=i386-efi + grub-i386-efi.
  EFI_TARGET=""
  if [ "$UEFI" = yes ]; then
    EFI_TARGET="x86_64-efi"
    if [ -r /sys/firmware/efi/fw_platform_size ] && \
       [ "$(cat /sys/firmware/efi/fw_platform_size 2>/dev/null)" = 32 ]; then
      EFI_TARGET="i386-efi"
    fi
  fi

  # cpu microcode
  UCODE=()
  if grep -qm1 'GenuineIntel' /proc/cpuinfo; then UCODE=(intel-ucode); fi
  if grep -qm1 'AuthenticAMD' /proc/cpuinfo; then UCODE=(linux-firmware-amd); fi

  # ram
  RAM_MB="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
  [ -n "$RAM_MB" ] || RAM_MB=4096

  # repository path segment: x86_64 is flat (/current), x86_64-musl lives
  # under /current/musl
  case "$arch" in
    x86_64-musl) REPO_SEG="musl" ;;
    *)           REPO_SEG="" ;;
  esac

  verb "detected: uefi=$UEFI${EFI_TARGET:+ ($EFI_TARGET)} arch=$arch libc=$LIBC ram=${RAM_MB}MB ucode=${UCODE[*]:-none}"
}

# list_disks -> lines "NAME SIZE MODEL"
list_disks() {
  lsblk -dpno NAME,SIZE,MODEL 2>/dev/null \
    | grep -vE '/dev/(loop|zram|sr|ram|fd)' \
    | grep -vE '^[[:space:]]*$'
}

# repo_url <base> -> full repository URL for this system's libc
repo_url() {
  local base="${1%/}"
  if [ -n "$REPO_SEG" ]; then printf '%s/current/%s\n' "$base" "$REPO_SEG"
  else printf '%s/current\n' "$base"; fi
}

# fallback mirror, also used when auto-detection fails offline (auto.sh,
# wizard.sh read this)
# shellcheck disable=SC2034
DEFAULT_MIRROR="https://repo-default.voidlinux.org"
TEST_MIRRORS="https://repo-default.voidlinux.org https://repo-fastly.voidlinux.org https://repo-fi.voidlinux.org https://repo-de.voidlinux.org"

# pick_fastest_mirror -> prints the fastest base URL (or nothing when offline)
pick_fastest_mirror() {
  command -v curl >/dev/null 2>&1 || return 1
  local url t best="" best_t=""
  # repodata is named after the full arch: x86_64-repodata, x86_64-musl-repodata ...
  local probe="${XBPS_ARCH:-x86_64}-repodata"
  for url in $TEST_MIRRORS; do
    printf '    testing %s ... ' "$url" >&2
    t="$(curl -sf -m 6 -r 0-200000 -o /dev/null -w '%{time_total}' \
          "$(repo_url "$url")/$probe" 2>/dev/null)" || { echo "unreachable" >&2; continue; }
    [ -n "$t" ] || { echo "unreachable" >&2; continue; }
    printf '%ss\n' "$t" >&2
    if [ -z "$best_t" ] || awk "BEGIN{exit !($t < $best_t)}"; then best="$url"; best_t="$t"; fi
  done
  printf '%s' "$best"
}

# mirror_reachable <base> -> 0/1
mirror_reachable() {
  command -v curl >/dev/null 2>&1 || return 0   # no curl: assume yes, xbps will complain otherwise
  curl -sf -m 8 -r 0-0 -o /dev/null "$(repo_url "$1")/${XBPS_ARCH:-x86_64}-repodata" >/dev/null 2>&1
}
