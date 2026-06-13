#!/usr/bin/env bash
# Test: ancestor directory traversal for deeply nested rwDirs (Darwin-specific)
# Verifies that file-read-metadata is granted on intermediate directories
# between $HOME and a rwDir/rwFile target, so that symlink resolution
# from the sandbox HOME can reach the real path through seatbelt.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

echo "=== Deep rwDir ancestor traversal tests (Darwin) ==="
echo

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/deep-statedir-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-deep-statedir"

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/deep-statedir.XXXXXX")
trap 'rm -rf "$TESTDIR" "$HOME/.tmp-test-deep-statedir"' EXIT
cd "$TESTDIR"
git init -q

# Pre-create the rwDir / rwFile declared by deep-statedir-sandbox.nix. The
# wrapper no longer creates declared bind paths automatically.
mkdir -p "$HOME/.tmp-test-deep-statedir/a/b/c/data"
touch "$HOME/.tmp-test-deep-statedir/a/b/c/config.json"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

# The rwDir is "$HOME/.tmp-test-deep-statedir/a/b/c/data".
# Intermediate directories that need file-read-metadata for traversal:
#   $HOME/.tmp-test-deep-statedir
#   $HOME/.tmp-test-deep-statedir/a
#   $HOME/.tmp-test-deep-statedir/a/b
#   $HOME/.tmp-test-deep-statedir/a/b/c
# The sandbox HOME symlinks into the real HOME path, so the kernel must
# stat() each intermediate to follow the symlink chain.

INTERMEDIATE1="$HOME/.tmp-test-deep-statedir"
INTERMEDIATE2="$HOME/.tmp-test-deep-statedir/a"
INTERMEDIATE3="$HOME/.tmp-test-deep-statedir/a/b"
INTERMEDIATE4="$HOME/.tmp-test-deep-statedir/a/b/c"

# --- rwDir read/write through sandbox HOME symlink ---
expect_ok "can write to deep rwDir" \
	"echo test > \"\$HOME/.tmp-test-deep-statedir/a/b/c/data/test.txt\""
expect_ok "can read from deep rwDir" \
	"cat \"\$HOME/.tmp-test-deep-statedir/a/b/c/data/test.txt\" > /dev/null"
expect_ok "can remove from deep rwDir" \
	"rm \"\$HOME/.tmp-test-deep-statedir/a/b/c/data/test.txt\""

# --- rwFile read/write through sandbox HOME symlink ---
expect_ok "can write to deep rwFile" \
	"echo '{\"key\":\"val\"}' > \"\$HOME/.tmp-test-deep-statedir/a/b/c/config.json\""
expect_ok "can read from deep rwFile" \
	"cat \"\$HOME/.tmp-test-deep-statedir/a/b/c/config.json\" > /dev/null"

# --- Intermediate directory traversal (stat must succeed) ---
expect_ok "stat on 1st intermediate" \
	"test -d '$INTERMEDIATE1'"
expect_ok "stat on 2nd intermediate" \
	"test -d '$INTERMEDIATE2'"
expect_ok "stat on 3rd intermediate" \
	"test -d '$INTERMEDIATE3'"
expect_ok "stat on 4th intermediate" \
	"test -d '$INTERMEDIATE4'"

# --- Intermediate listing still denied (only metadata, not readdir) ---
expect_fail "cannot list contents of 1st intermediate" \
	"ls '$INTERMEDIATE1/'"

print_results
exit_status
