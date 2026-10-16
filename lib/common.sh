#!/usr/bin/env bash
# voidc — common helpers: logging, dialog UI, command runners, utilities.
# Sourced by voidc and lib/*.sh. Interactive UI needs `dialog` (present on Void live ISO).

: "${LOGFILE:=/tmp/voidc.log}"
: "${TARGET:=/mnt}"
: "${VOIDC_VERSION:=0.0.0}"

# ------------------------------------------------------------------ logging --
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()     { printf '%s [info] %s\n' "$(_ts)" "$*" >>"$LOGFILE"; }
verb()    { printf '%s [step] %s\n' "$(_ts)" "$*" >>"$LOGFILE"; }
warnlog() { printf '%s [warn] %s\n' "$(_ts)" "$*" >>"$LOGFILE"; }

say()  { printf '\n\033[1;34m==>\033[0m \033[1m%s\033[0m\n' "$*" >&2; log "$*"; }
note() { printf '    %s\n' "$*" >&2; }

die() {
  printf '\n\033[1;31m!! %s\033[0m\n   Log: %s\n' "$*" "$LOGFILE" >&2
  log "FATAL: $*"
  exit 1
}

# --------------------------------------------------------------- cmd runner --
# run <description> <cmd...>  — abort on failure.
run() {
  local desc="$1"; shift
  verb "$desc :: $*"
  if ! "$@" >>"$LOGFILE" 2>&1; then
    die "Command failed: $desc ($*) — see $LOGFILE"
  fi
}

# try <cmd...> — best effort, never aborts.
try() { verb "try: $*"; "$@" >>"$LOGFILE" 2>&1 || warnlog "ignored failure: $*"; }

# chroot helpers (chroot root is $TARGET)
chroot_run() {
  local cmd="$1"
  verb "chroot: $cmd"
  chroot "$TARGET" /bin/sh -c "$cmd" >>"$LOGFILE" 2>&1 || die "chroot command failed: $cmd"
}
chroot_try() {
  local cmd="$1"
  verb "chroot(try): $cmd"
  chroot "$TARGET" /bin/sh -c "$cmd" >>"$LOGFILE" 2>&1 || warnlog "chroot ignored failure: $cmd"
}

# --------------------------------------------------------------- utilities ---
# part_dev /dev/sda 1 -> /dev/sda1 ; /dev/nvme0n1 2 -> /dev/nvme0n1p2
part_dev() {
  local disk="$1" n="$2"
  case "$disk" in
    *[0-9]) printf '%sp%s\n' "$disk" "$n" ;;
    *)      printf '%s%s\n'  "$disk" "$n" ;;
  esac
}

uuid_of() { blkid -s UUID -o value "$1" 2>/dev/null; }

pkg_exists_remote() { xbps-query -R "$1" >/dev/null 2>&1; }

enable_service() { # enable_service <svc> ; symlink into target runit default dir
  local svc="$1" root="${2:-$TARGET}"
  if [ -d "$root/etc/sv/$svc" ]; then
    ln -sfn "/etc/sv/$svc" "$root/etc/runit/runsvdir/default/$svc"
    verb "enabled service: $svc"
    return 0
  fi
  warnlog "service not found (skipped): $svc"
  return 1
}

first_service() { # first_service svc1 svc2 ... -> prints first existing name
  local s
  for s in "$@"; do
    [ -d "$TARGET/etc/sv/$s" ] && { printf '%s\n' "$s"; return 0; }
  done
  return 1
}

# ------------------------------------------------------------------ dialog ---
DLG_OPTS=(--backtitle "voidc $VOIDC_VERSION — fast Void installer" --title " Void Custom Installer " --colors)

ui_msg()   { dialog "${DLG_OPTS[@]}" --clear --msgbox "$@"; }
ui_yesno() { dialog "${DLG_OPTS[@]}" --clear --yesno "$@"; }
ui_input() { dialog "${DLG_OPTS[@]}" --clear --stdout --inputbox "$@"; }
ui_pass()  { dialog "${DLG_OPTS[@]}" --clear --stdout --insecure --passwordbox "$@"; }
ui_menu()  { dialog "${DLG_OPTS[@]}" --clear --stdout --menu "$@"; }
ui_check() { dialog "${DLG_OPTS[@]}" --clear --stdout --checklist "$@"; }

# ui_gauge_run <title> <initial text> <logfile> <cmd...>
# Runs cmd in background while a pulsing gauge shows recent log output.
# In unattended mode (NO_DIALOG=yes) the command runs directly.
ui_gauge_run() {
  local title="$1" text="$2" lf="$3"; shift 3
  if [ "${NO_DIALOG:-no}" = yes ]; then
    say "$text"
    "$@" >>"$lf" 2>&1 || die "$title failed — see $lf"
    return 0
  fi
  "$@" >>"$lf" 2>&1 &
  local pid=$! pct=0 last=""
  {
    while kill -0 "$pid" 2>/dev/null; do
      pct=$(( pct + 3 )); [ "$pct" -gt 97 ] && pct=3
      last="$(tail -n 1 "$lf" 2>/dev/null | tr -d '\r' | cut -c1-64)"
      printf 'XXX\n%d\n%s\n%s\nXXX\n' "$pct" "$text" "$last"
      sleep 0.5
    done
    printf 'XXX\n100\n%s\n%s\nXXX\n' "$text" "done"
  } | dialog "${DLG_OPTS[@]}" --title "$title" --gauge "$text" 11 78 0
  wait "$pid"
}

# ---------------------------------------------------------------- passwords --
# ask_password_twice <prompt> : echoes password on success, returns 1 on cancel
ask_password_twice() {
  local p1 p2
  p1="$(ui_pass "$1 (min 4 chars):" 10 60)" || return 1
  if [ "${#p1}" -lt 4 ]; then ui_msg "Password too short (min 4 characters)." 8 50; return 1; fi
  p2="$(ui_pass "$1 (repeat):" 10 60)" || return 1
  if [ "$p1" != "$p2" ]; then ui_msg "Passwords do not match." 8 50; return 1; fi
  printf '%s' "$p1"
}

# ------------------------------------------------------------------ cleanup --
UNMOUNT_DONE=no
unmount_all() {
  [ "$UNMOUNT_DONE" = yes ] && return 0
  UNMOUNT_DONE=yes
  verb "unmounting $TARGET"
  if [ -n "${SWAPDEV:-}" ] && [ -e "$SWAPDEV" ]; then swapoff "$SWAPDEV" >>"$LOGFILE" 2>&1 || true; fi
  umount -R "$TARGET" >>"$LOGFILE" 2>&1 || true
  if [ -n "${LUKSDEV:-}" ]; then cryptsetup close "${CRYPT_NAME:-cryptroot}" >>"$LOGFILE" 2>&1 || true; fi
}

# -------------------------------------------------------------------- misc ---
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

in_list() { # in_list <needle> <haystack words...> — hmm: use: in_list needle "a b c"
  local needle="$1" hay="$2"
  case " $hay " in *" $needle "*) return 0;; esac
  return 1
}
