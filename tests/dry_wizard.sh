#!/usr/bin/env bash
# dry_wizard.sh — scripted run of the interactive wizard (the default `voidc`
# path, lib/wizard.sh) without a terminal: a fake `dialog` consumes one answer
# line per prompt from /tmp/wiz_answers.txt and logs every call to
# /tmp/wiz_dialogs.log; a fake lsblk (earlier in PATH) reports /tmp/fakedisk as
# the only disk. The wizard is therefore driven exactly as a user would:
# menus, typed hostname/user, password boxes, checklist, confirmations.
#
# Needs /tmp/stubbin (tests/mkstubs.sh) and the /tmp/drysrc sandbox copy
# (tests/run.sh prepares both; it also forces BIOS so the run is deterministic
# even on UEFI machines).
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"

export PATH=/tmp/wizbin:/tmp/stubbin:$PATH
export STUB_LOG=/tmp/stub_w.log STUB_MISSING="i3-gaps"
export WIZ_ANSWERS=/tmp/wiz_answers.txt WIZ_DLG_LOG=/tmp/wiz_dialogs.log
: >"$STUB_LOG"; : >"$WIZ_DLG_LOG"
rm -f /etc/xbps.d/30-repository-desktop.conf /tmp/dry_wizard.log
rm -f /tmp/dry_wizard.out /tmp/dry_wizard.err
rm -f /tmp/fakedisk; : >/tmp/fakedisk
bash "$SELF/mkskel.sh" /tmp/drytarget_w >/dev/null
# a real `useradd -m` would have created this (the chroot stub does not)
mkdir -p /tmp/drytarget_w/home/wizard

mkdir -p /tmp/wizbin
cat >/tmp/wizbin/lsblk <<'EOF'
#!/bin/sh
# list_disks asks for NAME,SIZE,MODEL — report one disk.
# disk_is_busy asks for MOUNTPOINTS — report nothing (not mounted).
for a in "$@"; do
  case "$a" in
    *MOUNTPOINTS*)    exit 0 ;;
    *NAME,SIZE,MODEL*) echo "/tmp/fakedisk 20G VoidVirtualDisk"; exit 0 ;;
  esac
done
exit 0
EOF
cat >/tmp/wizbin/dialog <<'EOF'
#!/usr/bin/env bash
# fake dialog — reads one answer line per prompt, logs every call.
# yesno: yes -> 0, no -> 1, other -> 255 (ESC/cancel)
# gauge: drains the progress pipe, exits 0
# input/password/menu/checklist: prints the answer line verbatim
set -u
ansf="${WIZ_ANSWERS:?WIZ_ANSWERS not set}"
logf="${WIZ_DLG_LOG:?WIZ_DLG_LOG not set}"
args=("$@")
op="" text=""
k=0
while [ "$k" -lt "$#" ]; do
  case "${args[$k]}" in
    --msgbox|--yesno|--inputbox|--passwordbox|--menu|--checklist|--gauge|--infobox)
      op="${args[$k]#--}"; text="${args[$((k+1))]:-}"; break ;;
  esac
  k=$((k+1))
done
[ -n "$op" ] || { echo "fake-dialog: no op in: $*" >&2; exit 2; }
short="$(printf '%s' "$text" | tr '\n' ' ' | cut -c1-50)"
if [ "$op" = gauge ] || [ "$op" = infobox ]; then
  printf '%s\t-\t%s\n' "$op" "$short" >>"$logf"
  cat >/dev/null 2>&1 || true
  exit 0
fi
if [ ! -s "$ansf" ]; then
  printf '%s\t(NO-ANSWER)\t%s\n' "$op" "$short" >>"$logf"
  echo "fake-dialog: answer queue EMPTY at op=$op ($short)" >&2
  exit 3
fi
ans="$(head -n1 "$ansf")"
tail -n +2 "$ansf" >"$ansf.tmp" && mv "$ansf.tmp" "$ansf"
printf '%s\t%s\t%s\n' "$op" "$ans" "$short" >>"$logf"
case "$op" in
  msgbox) exit 0 ;;
  yesno)
    case "$ans" in yes) exit 0 ;; no) exit 1 ;; *) exit 255 ;; esac ;;
  *)
    case "$ans" in @ESC) exit 255 ;; @EMPTY) exit 0 ;; *) printf '%s\n' "$ans"; exit 0 ;; esac ;;
esac
EOF
chmod 0755 /tmp/wizbin/dialog /tmp/wizbin/lsblk

# Answer queue — one line per dialog call, in wizard order:
#   welcome | session | disk | disk-confirm | filesystem | swap | LUKS? |
#   hostname | username | root-pass x2 | same-pass-for-user? | timezone |
#   keymap | locale | identity-review | desktop | extras-checklist |
#   autostart? | dotfiles? | GPU | login-manager | mirror | summary |
#   start? | [2 gauges: no answers] | complete | reboot? | unmount-note
cat >/tmp/wiz_answers.txt <<'EOF'
ok
any
/tmp/fakedisk
/tmp/fakedisk
ext4
4096
no
wizbox
wizard
wizpass
wizpass
yes
UTC
de
C.UTF-8
done
i3
"audio" "networking" "fonts" "nonfree" "ssh"
yes
no
auto
greetd
default
ok
yes
ok
no
ok
EOF

echo "== wizard: scripted TUI session (log: /tmp/dry_wizard.log)"
LOGFILE=/tmp/dry_wizard.log bash /tmp/drysrc/voidc --target /tmp/drytarget_w \
  >/tmp/dry_wizard.out 2>/tmp/dry_wizard.err
rc=$?
echo "DRY_WIZARD_EXIT=$rc"

# ------------------------------------------------------------ assertions ----
ARCH="$(uname -m)"
LIBC=glibc
if ls /lib/ld-musl-*.so.1 >/dev/null 2>&1; then
  LIBC=musl
  case "$ARCH" in *musl*) ;; *) ARCH="${ARCH}-musl" ;; esac
fi
case "$ARCH" in
  x86_64)      REPO_SEG="" ;;
  x86_64-musl) REPO_SEG="musl" ;;
  *)           REPO_SEG="${ARCH%%-musl}" ;;
esac
MAIN_PATH="current"; [ -n "$REPO_SEG" ] && MAIN_PATH="current/$REPO_SEG"
U=wizard
W=/tmp/drytarget_w

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
check_line() { # <desc> <file> <expected line>
  local d="$1" f="$2" want="$3" got
  got="$(cat "$f" 2>/dev/null)"
  if [ "$got" = "$want" ]; then ok "$d"; else bad "$d (got: $got)"; fi
}

echo "== wizard assertions (fake dialog) =="
check "wizard exit status"      test "$rc" -eq 0
check "answer queue drained"    bash -c "! test -s '$WIZ_ANSWERS'"
check "no desync in stderr"     bash -c "! grep -q 'answer queue EMPTY' /tmp/dry_wizard.err"
check "dialog calls == 30"      test "$(wc -l <"$WIZ_DLG_LOG")" -eq 30
check "2 gauges ran"            test "$(grep -c '^gauge' "$WIZ_DLG_LOG")" -eq 2
check "hostname typed"          grep -qx "wizbox" "$W/etc/hostname"
check "username typed"          grep -q "useradd.*$U" "$STUB_LOG"
check "chpasswd ran x2"         test "$(grep -c 'chpasswd' "$STUB_LOG")" -eq 2
check "log: password root"      grep -q "password set for root" /tmp/dry_wizard.log
check "log: password user"      grep -q "password set for $U" /tmp/dry_wizard.log
check "sudoers wheel"           grep -q "%wheel" "$W/etc/sudoers.d/10-wheel"
check "bash_profile autostart"  grep -q "exec startx" "$W/home/$U/.bash_profile"
check "fstab root UUID+ext4"    grep -q "^UUID=aaaaaaaa" "$W/etc/fstab"
check "fstab /boot"             grep -q "/boot" "$W/etc/fstab"
check "fstab swap"              grep -q "swap" "$W/etc/fstab"
check "fstab no efi (BIOS)"     bash -c "! grep -q efi '$W/etc/fstab'"
check_line "main repo conf" "$W/etc/xbps.d/00-repository-main.conf" \
  "repository=https://repo-default.voidlinux.org/$MAIN_PATH"
check "nonfree repo conf"       grep -q "nonfree" "$W/etc/xbps.d/20-repository-nonfree.conf"
check "no multilib (unchecked)" bash -c "! test -e '$W/etc/xbps.d/20-repository-multilib.conf'"
check "no desktop extra conf"   bash -c "! test -e '$W/etc/xbps.d/30-repository-desktop.conf'"
check "rc.conf keymap de"       grep -q 'KEYMAP="de"' "$W/etc/rc.conf"
check "rc.conf timezone"        grep -q 'TIMEZONE="UTC"' "$W/etc/rc.conf"
check "X keyboard de"           grep -q 'XkbLayout.*"de"' "$W/etc/X11/xorg.conf.d/00-keyboard.conf"
if [ "$LIBC" = glibc ]; then
  check "locale.conf C.UTF-8"   grep -q "LANG=C.UTF-8" "$W/etc/locale.conf"
else
  check "no locale.conf (musl)" bash -c "! test -e '$W/etc/locale.conf'"
fi
check "pipewire drop-in"        test -L "$W/etc/pipewire/pipewire.conf.d/10-wireplumber.conf"
check "svc dbus enabled"        test -L "$W/etc/runit/runsvdir/default/dbus"
check "svc elogind enabled"     test -L "$W/etc/runit/runsvdir/default/elogind"
check "svc NetworkManager"      test -L "$W/etc/runit/runsvdir/default/NetworkManager"
check "svc sshd"                test -L "$W/etc/runit/runsvdir/default/sshd"
check "svc chronyd"             test -L "$W/etc/runit/runsvdir/default/chronyd"
check "svc rtkit"               test -L "$W/etc/runit/runsvdir/default/rtkit"
check "svc greetd"              test -L "$W/etc/runit/runsvdir/default/greetd"
check "no bluetoothd (off)"     bash -c "! test -e '$W/etc/runit/runsvdir/default/bluetoothd'"
check "no cupsd (off)"          bash -c "! test -e '$W/etc/runit/runsvdir/default/cupsd'"
check "greetd wrapper startx"   grep -q "dbus-run-session -- startx" "$W/usr/local/bin/voidc-session"
check "greetd config.toml"      grep -q "voidc-session" "$W/etc/greetd/config.toml"
check "i3 config has pipewire"  grep -q "pipewire" "$W/home/$U/.config/i3/config"
check "i3 .xinitrc"             grep -q "exec dbus-run-session -- i3" "$W/home/$U/.xinitrc"
check "wallpaper decoded"       test -s "$W/home/$U/Pictures/wall.png"
check "install log copied"      test -s "$W/var/log/voidc-install.log"
check "no dotfiles (declined)"  bash -c "! test -e '$W/home/$U/.dotfiles'"
check "log: i3-gaps fallback"   grep -q "i3-gaps' missing -> using 'i3'" /tmp/dry_wizard.log
check "stub: wipefs"            grep -q "wipefs -a /tmp/fakedisk" "$STUB_LOG"
check "stub: bios_grub"         grep -q "bios_grub" "$STUB_LOG"
check "stub: no ESP (BIOS)"     bash -c "! grep -q 'mkpart ESP' '$STUB_LOG'"
check "stub: mkswap swap 4096"  grep -q "mkswap -L swap /tmp/fakedisk3" "$STUB_LOG"
check "stub: no cryptsetup"     bash -c "! grep -q cryptsetup '$STUB_LOG'"
check "stub: mkfs.ext4 root"    grep -q "mkfs.ext4 -q -L voidroot /tmp/fakedisk4" "$STUB_LOG"
check "stub: mount root"        grep -q "mount /tmp/fakedisk4 /tmp/drytarget_w" "$STUB_LOG"
check "stub: mount /boot"       grep -q "mount /tmp/fakedisk2 /tmp/drytarget_w/boot" "$STUB_LOG"
check "grub i386-pc"            grep -q "grub-install --target=i386-pc" "$STUB_LOG"
check "chroot: xbps-reconfigure" grep -q "xbps-reconfigure -fa" "$STUB_LOG"
xline="$(grep "xbps-install -Sy -y -r /tmp/drytarget_w" "$STUB_LOG" | head -n1)"
check "pkg: xorg"               bash -c "printf '%s\n' '$xline' | grep -qw xorg"
check "pkg: alacritty"          bash -c "printf '%s\n' '$xline' | grep -qw alacritty"
check "pkg: polybar"            bash -c "printf '%s\n' '$xline' | grep -qw polybar"
check "pkg: rofi"               bash -c "printf '%s\n' '$xline' | grep -qw rofi"
check "pkg: picom"              bash -c "printf '%s\n' '$xline' | grep -qw picom"
check "pkg: i3 (not i3-gaps)"   bash -c "printf '%s\n' '$xline' | grep -qw i3 && ! printf '%s\n' '$xline' | grep -qw i3-gaps"

echo
if [ "$fail" = 0 ]; then echo "WIZARD ASSERTIONS PASSED"; else echo "WIZARD FAILURES PRESENT"; fi
exit "$fail"
