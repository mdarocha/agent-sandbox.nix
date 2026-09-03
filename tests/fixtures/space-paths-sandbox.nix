# Test fixture: rwDir / rwFile / roDir / roFile declared at paths containing
# spaces, to catch the bind builders regressing to unquoted string
# concatenation (word-split on the space, corrupting the bwrap args).
let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-space-paths";
  allowedPackages = [ pkgs.coreutils pkgs.git ];
  rwDirs = [ "$HOME/.test state dir" ];
  rwFiles = [ "$HOME/.test state file" ];
  roDirs = [ "$HOME/.test space ro dir" ];
  roFiles = [ "$HOME/.test space ro file" ];
}
