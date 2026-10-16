#!/usr/bin/env bash
# matugen-fallback.sh — unit test for the GitHub release fallback in
# lib/rice.sh (install_matugen). A fake curl serves canned release JSON and
# tarballs (no network) and the test checks the asset-selection logic:
#   * x86_64/glibc picks the plain x86_64 asset
#   * x86_64/musl prefers a musl asset when one exists
#   * x86_64/glibc prefers a non-musl asset when both exist
#   * glibc accepts a musl-only release as a last resort
#   * musl skips when the release has no musl build (a glibc binary cannot run)
set -u
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
W=/tmp/mgtest
rm -rf "$W"; mkdir -p "$W/bin"

export LOGFILE="$W/install.log"
export TARGET="$W/target"

# --- fake curl: API -> canned JSON; asset URL -> canned tarball --------------
cat >"$W/bin/curl" <<'EOS'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -*) shift ;;
    *)  url="$1"; shift ;;
  esac
done
case "$url" in
  *api.github.com*) cat "$MG_JSON" ;;
  *musl*)           cp "$MG_MUSL_TAR" "$out" ;;
  *)                cp "$MG_PLAIN_TAR" "$out" ;;
esac
EOS
chmod +x "$W/bin/curl"
export PATH="$W/bin:$PATH"

# --- canned tarballs containing a marker "binary" ----------------------------
mk_tar() { # <file> <marker>
  local d="$W/stage"
  rm -rf "$d"; mkdir -p "$d"
  printf '%s\n' "$2" >"$d/matugen"
  tar -czf "$W/$1" -C "$d" matugen
}
export MG_PLAIN_TAR="$W/plain.tar.gz" MG_MUSL_TAR="$W/musl.tar.gz"
mk_tar plain.tar.gz PLAIN-BUILD
mk_tar musl.tar.gz  MUSL-BUILD

# --- canned release JSONs ----------------------------------------------------
cat >"$W/x86-only.json" <<'EOS'
{"assets": [
 {"browser_download_url": "https://github.com/InioX/matugen/releases/download/v9/matugen-9-x86_64.tar.gz"},
 {"browser_download_url": "https://github.com/InioX/matugen/releases/download/v9/matugen-9-x86_64.tar.gz.sha256"}
]}
EOS
cat >"$W/x86-mixed.json" <<'EOS'
{"assets": [
 {"browser_download_url": "https://github.com/InioX/matugen/releases/download/v9/matugen-9-x86_64.tar.gz"},
 {"browser_download_url": "https://github.com/InioX/matugen/releases/download/v9/matugen-9-x86_64-unknown-linux-musl.tar.gz"}
]}
EOS
cat >"$W/musl-only.json" <<'EOS'
{"assets": [
 {"browser_download_url": "https://github.com/InioX/matugen/releases/download/v9/matugen-9-x86_64-unknown-linux-musl.tar.gz"}
]}
EOS

# xbps-query always reports "not in repos" -> forces the fallback path
xbps-query() { return 1; }
# shellcheck disable=SC1091
. "$ROOT/lib/common.sh"
# shellcheck disable=SC1091
. "$ROOT/lib/rice.sh"

fail=0
ok()  { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fail=1; }

run_case() { # <name> <arch> <libc> <json> <expect: marker|SKIP>
  local name="$1" arch="$2" libc="$3" json="$4" expect="$5" got
  rm -rf "$TARGET"; mkdir -p "$TARGET"
  : >"$LOGFILE"
  MG_JSON="$json" XBPS_ARCH="$arch" LIBC="$libc" install_matugen >/dev/null 2>&1 || true
  if [ "$expect" = SKIP ]; then
    if [ ! -e "$TARGET/usr/local/bin/matugen" ]; then
      ok "$name (skipped, as expected)"
    else
      bad "$name (unexpected binary installed)"
    fi
  else
    got="$(cat "$TARGET/usr/local/bin/matugen" 2>/dev/null)"
    if [ "$got" = "$expect" ]; then ok "$name ($expect)"; else bad "$name (expected $expect, got '$got')"; fi
  fi
}

echo "== matugen release-fallback selection =="
run_case "x86_64/glibc picks plain x86_64"  x86_64  glibc "$W/x86-only.json"   PLAIN-BUILD
run_case "x86_64/musl prefers musl build"   x86_64  musl  "$W/x86-mixed.json"  MUSL-BUILD
run_case "x86_64/musl skips without musl"   x86_64  musl  "$W/x86-only.json"   SKIP
run_case "x86_64/glibc prefers non-musl"    x86_64  glibc "$W/x86-mixed.json"  PLAIN-BUILD
run_case "glibc accepts musl-only release"  x86_64  glibc "$W/musl-only.json" MUSL-BUILD

echo
if [ "$fail" = 0 ]; then echo "MATUGEN FALLBACK TESTS PASSED"; else echo "MATUGEN FALLBACK FAILURES"; fi
exit "$fail"
