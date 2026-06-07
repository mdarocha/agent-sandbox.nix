# Test fixture: restrictNetwork=true sandbox with a UNIX-socket-capable
# client (socat) in PATH. Used to assert that connect() to a UNIX-domain
# socket on the host is denied. See
# tests/darwin/test-unix-socket-egress-denied.sh.
#
# IMPORTANT: restrictNetwork=true is required for this test. With
# restrictNetwork=false the static profile contains (allow network*) which
# permits all socket ops, including AF_UNIX connect — so the regression
# would silently pass for the wrong reason.
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash";
  allowedPackages = [ pkgs.coreutils pkgs.socat ];
  restrictNetwork = true;
  allowedDomains = [ "anthropic.com" ];
}
