#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib.sh"

NIX_SUPPORT=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/nix-support.nix")
NIX_SUPPORT_SHELL="$NIX_SUPPORT/bin/sandboxed-bash-nix-support"

BASIC=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/basic-sandbox.nix")
BASIC_SHELL="$BASIC/bin/sandboxed-bash"

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/nix-support-shared.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

echo "=== Nix support tests (shared) ==="
echo

run() { "$NIX_SUPPORT_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

expect_ok "nix-build succeeds with allowNix" \
    'nix-build -E "(import <nixpkgs> {}).hello" --no-out-link'

expect_ok "nix-shell succeeds with allowNix" \
    'nix-shell -p hello --run "hello"'

run() { "$BASIC_SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

expect_fail "nix-build unavailable without allowNix" \
    'nix-build -E "(import <nixpkgs> {}).hello" --no-out-link'

expect_fail "nix-shell unavailable without allowNix" \
    'nix-shell -p hello --run "hello"'

print_results
exit_status
