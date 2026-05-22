# Example: a dev shell with a sandboxed Claude Code binary.
# Copy this into your project and adjust as needed.
#
# Usage:
#   export CLAUDE_CODE_OAUTH_TOKEN="<your_token_here>"
#   nix-shell shells/claude.shell.nix
let
  pkgs = import <nixpkgs> { config.allowUnfree = true; };
  agent-sandbox =
    import (fetchTarball "https://github.com/archie-judd/agent-sandbox.nix/archive/main.tar.gz")
      {
        pkgs = pkgs;
      };
  claude-sandboxed = agent-sandbox.mkSandbox {
    pkg = pkgs.claude-code;
    binName = "claude";
    outName = "claude-sandboxed";
    allowedPackages = agent-sandbox.commonTools;
    rwDirs = [ "$HOME/.claude" ];
    # Bind your host gitconfig read-only for git identity (recommended).
    # Set user.name / user.email on the host first, then uncomment:
    # roFiles = [ "$HOME/.config/git/config" ];
    # (Alternative: set GIT_AUTHOR_* / GIT_COMMITTER_* in env. See README.)
    env = {
      # Pass secrets as shell variable references (e.g. "$TOKEN"), not
      # via builtins.getEnv, so they expand at runtime and stay out of
      # the /nix/store.
      CLAUDE_CODE_OAUTH_TOKEN = "$CLAUDE_CODE_OAUTH_TOKEN";
      GITHUB_TOKEN = "$GITHUB_TOKEN";
      CLAUDE_CONFIG_DIR = "$HOME/.claude";
    };
    allowedDomains = {
      "anthropic.com" = "*";
      "claude.com" = "*";
      "raw.githubusercontent.com" = [
        "GET"
        "HEAD"
      ];
      "api.github.com" = [
        "GET"
        "HEAD"
      ];
    };
    # Optional: run a script before the sandbox starts to inject env vars.
    # Primary use case — activate the project's devShell so its tools are
    # available inside the sandbox alongside allowedPackages:
    #
    #   shellHook = ''
    #     eval "$(direnv export bash)"
    #   '';
    #
    # Requires: direnv allow has been run for the project's .envrc.
    # When shellHook is set, /nix/store is fully bind-mounted (read-only)
    # so devShell store paths are accessible inside the sandbox.
  };
in
pkgs.mkShell { packages = [ claude-sandboxed ]; }
