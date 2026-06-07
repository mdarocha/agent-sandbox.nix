#!/usr/bin/env bash
# Test: /private/var/folders (per-user temp/cache tree) is not reachable
# from inside the sandbox. Regression for SANDBOX-FINDINGS.md §1 — that
# subtree holds 0400/0600 host-user secrets (age keys, PATs, etc.) and
# the sandbox runs as the host UID, so it must not be in the allow set.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/basic-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/user-folders-denied.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

# Resolve the host's per-user temp/cache dirs OUTSIDE the sandbox. The
# sandboxed getconf returns the same string (confstr is a libc query, not
# a filesystem op), but we want the real path for the assertions.
USER_TMP=$(getconf DARWIN_USER_TEMP_DIR)
USER_CACHE=$(getconf DARWIN_USER_CACHE_DIR)

echo "=== /private/var/folders denied (Darwin) ==="
echo "USER_TMP=$USER_TMP"
echo "USER_CACHE=$USER_CACHE"
echo

expect_fail "cannot stat DARWIN_USER_TEMP_DIR" "test -d '$USER_TMP'"
expect_fail "cannot stat DARWIN_USER_CACHE_DIR" "test -d '$USER_CACHE'"
expect_fail "cannot list DARWIN_USER_TEMP_DIR" "ls '$USER_TMP/'"
expect_fail "cannot list DARWIN_USER_CACHE_DIR" "ls '$USER_CACHE/'"
expect_fail "cannot stat /private/var/folders" "test -d /private/var/folders"
expect_fail "cannot enumerate /private/var/folders" "ls /private/var/folders/"

# Sanity: legitimate temp use via /tmp still works.
expect_ok "can write to /tmp" "touch /tmp/sandbox-user-folders-test && rm /tmp/sandbox-user-folders-test"

print_results
exit_status
