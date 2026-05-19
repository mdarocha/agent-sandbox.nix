# Test fixture: stateDir points to a file path
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-state-dir-file-path";
  allowedPackages = [ pkgs.coreutils ];
  stateDirs = [ "$HOME/.tmp-agent-sandbox-state-dir-file" ];
}