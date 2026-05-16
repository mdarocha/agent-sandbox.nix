{ pkgs }:
let
  shared = import ./lib/shared.nix { pkgs = pkgs; };
  mkLinuxSandbox = import ./lib/linux { pkgs = pkgs; shared = shared; };
  mkDarwinSandbox = import ./lib/darwin { pkgs = pkgs; shared = shared; };
in {
  mkSandbox = if pkgs.stdenv.isDarwin then mkDarwinSandbox else mkLinuxSandbox;
}
