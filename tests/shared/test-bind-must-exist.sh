#!/usr/bin/env bash
# Test: missing rwDirs / roDirs are warned and skipped; missing rwFiles / roFiles
# are still hard errors.
#
# Directories are optional on any given machine (cache dirs, tool-specific
# config dirs, etc.). A missing directory emits a WARN line but does not abort
# the sandbox launch. Files are precise targets; a missing file almost certainly
# means a typo, so it remains a hard error.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/bind-must-exist.nix")
SHELL_BIN="$SANDBOXED/bin/sandboxed-bash-bind-must-exist"

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/bind-must-exist.XXXXXX")
trap 'rm -rf "$TESTDIR"' EXIT
cd "$TESTDIR"

# HOME is overridden per-invocation so the existence of the declared
# rwDir/rwFile is entirely controlled by this test, independent of the
# host's real $HOME contents.
FAKE_HOME="$TESTDIR/home"
mkdir -p "$FAKE_HOME"

DIR_PATH="$FAKE_HOME/.agent-sandbox-bind-must-exist/dir"
FILE_PATH="$FAKE_HOME/.agent-sandbox-bind-must-exist/file"

echo "=== Bind paths must exist (shared) ==="
echo

# --- 1. Both missing: only rwFile error is fatal; rwDir gets a warning ---
capture env HOME="$FAKE_HOME" "$SHELL_BIN" -c 'echo unreachable'
assert_exit_code "both missing: launch fails (rwFile is missing)" 1
assert_stderr_contains "both missing: rwDir warning reported" \
	"$DIR_PATH: declared as rwDir but does not exist"
assert_stderr_contains "both missing: rwFile error reported" \
	"$FILE_PATH: declared as rwFile but does not exist"

# --- 2. Only rwDir missing: sandbox still launches (dir is optional) ---
mkdir -p "$(dirname "$FILE_PATH")"
touch "$FILE_PATH"
capture env HOME="$FAKE_HOME" "$SHELL_BIN" -c 'echo ok'
assert_exit_code "rwDir missing only: launch succeeds" 0
assert_stderr_contains "rwDir missing only: rwDir warning reported" \
	"$DIR_PATH: declared as rwDir but does not exist"
assert_output_equals "rwDir missing only: command runs in sandbox" "ok"

# --- 3. Only rwFile missing ---
rm -f "$FILE_PATH"
mkdir -p "$DIR_PATH"
capture env HOME="$FAKE_HOME" "$SHELL_BIN" -c 'echo unreachable'
assert_exit_code "rwFile missing only: launch fails" 1
assert_stderr_contains "rwFile missing only: rwFile error reported" \
	"$FILE_PATH: declared as rwFile but does not exist"
assert_stderr_not_contains "rwFile missing only: no rwDir error" \
	"declared as rwDir"

# --- 4. All present: launch succeeds ---
touch "$FILE_PATH"
capture env HOME="$FAKE_HOME" "$SHELL_BIN" -c 'echo ok'
assert_exit_code "all present: launch succeeds" 0
assert_output_equals "all present: command runs in sandbox" "ok"

print_results
exit_status
