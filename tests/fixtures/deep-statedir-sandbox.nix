# Test fixture: sandbox with a deeply nested stateDir.
# Exercises ancestor traversal between $HOME and the stateDir target,
# ensuring seatbelt grants file-read-metadata on intermediate directories
# so symlink resolution can reach the allowed path.
#
# STATE_BASE must be set to a temp directory before invoking the sandbox.
# The test script creates it and cleans it up.
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-deep-statedir";
  allowedPackages = [ pkgs.coreutils ];
  stateDirs = [ "$HOME/.tmp-test-deep-statedir/a/b/c/data" ];
  stateFiles = [ "$HOME/.tmp-test-deep-statedir/a/b/c/config.json" ];
}
