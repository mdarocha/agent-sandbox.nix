let
  pkgs = import <nixpkgs> { };
  sandbox = import ../../default.nix { pkgs = pkgs; };
  nonClosurePkg = pkgs.hello;
in sandbox.mkSandbox {
  pkg = pkgs.bashInteractive;
  binName = "bash";
  outName = "sandboxed-bash-nix-support";
  allowedPackages = [ pkgs.coreutils ];
  allowNix = true;
  env = {
    NIX_PATH = "nixpkgs=${pkgs.path}";
    NON_CLOSURE_STORE_PATH = "${nonClosurePkg}";
  };
}
