#!/usr/bin/env bash
# voidc — environment detection: firmware, libc, CPU, RAM, disks, mirrors.

detect_environment() {
  # firmware
  UEFI=no
  [ -d /sys/firmware/efi ] && UEFI=yes

  # arch + libc via xbps (falls back to uname)
  local arch
  arch="$(xbps-uhelper arch 2>/dev/null || uname -m)"
  XBPS_ARCH="$arch"
  LIBC=glibc
  case "$arch" in *musl*) LIBC=musl ;; esac

  # cpu microcode
  UCODE=()
  if grep -qm1 'GenuineIntel' /proc/cpuinfo; then UCODE=(intel-ucode); fi
  if grep -qm1 'AuthenticAMD' /proc/cpuinfo; then UCODE=(amd-ucode); fi

  # ram
  RAM_MB="$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"
  [ -n "$RAM_MB" ] || RAM_MB=4096

  # repo path segment (musl lives under /current/musl)
  if [ "$LIBC" = musl ]; then REPO_SEG="musl"; else REPO_SEG=""; fi

  verb "detected: uefi=$UEFI arch=$arch libc=$LIBC ram=${RAM_MB}MB ucode=${UCODE[*]:-none}"
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
  local probe="${XBPS_ARCH%%-*}-repodata"
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
  curl -sf -m 8 -r 0-0 -o /dev/null "$(repo_url "$1")/${XBPS_ARCH%%-*}-repodata" >/dev/null 2>&1
}
