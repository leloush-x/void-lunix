#!/usr/bin/env bash
# Static analysis over the installer and the test scripts (ShellCheck).
# Fails on any warning-level finding (the repo is clean at shellcheck 0.10.0).
# Used by tests/run.sh when shellcheck is installed, and by CI explicitly.
set -u
SELF="$(cd -- "$(dirname -- "$0")" && pwd)"
ROOT="$(cd -- "$SELF/.." && pwd)"
command -v shellcheck >/dev/null 2>&1 || {
  echo "shellcheck not found in PATH (install it or run this in CI)" >&2
  exit 1
}
cd "$ROOT" || exit 1
shellcheck -S warning voidc lib/*.sh tests/*.sh || exit $?
echo "SHELLCHECK PASSED"
