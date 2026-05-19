#!/usr/bin/env bash
# Regression test: stateDirs entry may resolve to an existing file path.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/../lib.sh"

SANDBOXED=$(nix-build --no-out-link "$SCRIPT_DIR/../fixtures/state-dir-file-path-sandbox.nix")
SHELL="$SANDBOXED/bin/sandboxed-bash-state-dir-file-path"

STATE_PATH="$HOME/.tmp-agent-sandbox-state-dir-file"
trap 'rm -f "$STATE_PATH"' EXIT
echo "registry=https://registry.npmjs.org/" > "$STATE_PATH"

echo "=== stateDir file-path regression test (Linux) ==="
echo

if OUT=$("$SHELL" --norc --noprofile -c "true" 2>&1 >/dev/null); then
  if echo "$OUT" | grep -q "Cannot create directory"; then
    echo "FAIL: startup does not emit directory-creation error for file stateDir"
    FAIL=$((FAIL + 1))
  else
    echo "PASS: startup tolerates file path in stateDirs without mkdir error"
    PASS=$((PASS + 1))
  fi
else
  echo "FAIL: sandbox failed to start"
  FAIL=$((FAIL + 1))
fi

print_results
exit_status