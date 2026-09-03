#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/space-paths-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-space-paths"

run() { "$SHELL" --norc --noprofile -c "$@" >/dev/null 2>&1; }
run_output() { "$SHELL" --norc --noprofile -c "$@" 2>/dev/null; }

TESTDIR_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)/.tmp-test"
mkdir -p "$TESTDIR_ROOT"
TESTDIR=$(mktemp -d "$TESTDIR_ROOT/space paths.XXXXXX")
trap 'rm -rf "$TESTDIR" "$HOME/.test state dir" "$HOME/.test state file" "$HOME/.test space ro dir" "$HOME/.test space ro file"' EXIT
cd "$TESTDIR"

mkdir -p "$HOME/.test state dir"
touch "$HOME/.test state file"
mkdir -p "$HOME/.test space ro dir"
echo "ro-dir-content" > "$HOME/.test space ro dir/contents.txt"
echo "ro-file-content" > "$HOME/.test space ro file"

git init -q .
git -C "$TESTDIR" config user.email test@example.com
git -C "$TESTDIR" config user.name test

echo "=== Space-in-path binds (shared) ==="
echo

expect_ok "CWD with a space in the path is bound read-write" "touch '$TESTDIR/marker' && rm '$TESTDIR/marker'"
expect_ok "git repo rooted at a spacey CWD is usable" "git -C '$TESTDIR' status"

expect_ok "rwDir at a spacey path is writable" "echo written > \"\$HOME/.test state dir/f\" && cat \"\$HOME/.test state dir/f\""
content=$(run_output "cat \"\$HOME/.test state dir/f\"")
if [ "$content" = "written" ]; then
	echo "PASS: rwDir spacey-path content is correct"
	PASS=$((PASS + 1))
else
	echo "FAIL: rwDir spacey-path content is wrong (got '$content', expected 'written')"
	FAIL=$((FAIL + 1))
fi

expect_ok "rwFile at a spacey path is writable" "echo written > \"\$HOME/.test state file\""

expect_ok "roDir at a spacey path is readable" "cat \"\$HOME/.test space ro dir/contents.txt\" > /dev/null"
expect_fail "roDir at a spacey path rejects writes" "echo modified > \"\$HOME/.test space ro dir/contents.txt\""

expect_ok "roFile at a spacey path is readable" "cat \"\$HOME/.test space ro file\" > /dev/null"
expect_fail "roFile at a spacey path rejects writes" "echo modified > \"\$HOME/.test space ro file\""

print_results
exit_status
