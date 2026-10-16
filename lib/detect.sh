#!/usr/bin/env bash
# voidc — environment detection: firmware, libc, CPU, RAM, disks, mirrors.

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

  # cpu microcode
  UCODE=()
  if grep -qm1 'GenuineIntel' /proc/cpuinfo; then UCODE=(intel-ucode); fi
  if grep -qm1 'AuthenticAMD' /proc/cpuinfo; then UCODE=(linux-firmware-amd); fi

  # ram
  RAM_MB="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
  [ -n "$RAM_MB" ] || RAM_MB=4096

  # repository path segment: x86_64 is flat (/current), x86_64-musl lives
  # under /current/musl, aarch64 (glibc and musl) under /current/aarch64
  case "$arch" in
    x86_64)      REPO_SEG="" ;;
    x86_64-musl) REPO_SEG="musl" ;;
    *)           REPO_SEG="${arch%%-musl}" ;;
  esac

  verb "detected: uefi=$UEFI arch=$arch libc=$LIBC ram=${RAM_MB}MB ucode=${UCODE[*]:-none}"
}

# check_firmware_support — legacy BIOS boot is x86-only (GRUB i386-pc).
# Fails early, before the disk is touched, instead of late at grub-install.
check_firmware_support() {
  [ "$UEFI" = no ] || return 0
  case "${XBPS_ARCH:-x86_64}" in
    x86_64*|i686*) return 0 ;;
  esac
  die "BIOS boot is not supported on ${XBPS_ARCH} — boot the installer in UEFI mode."
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
