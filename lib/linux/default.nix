/* mkLinuxSandbox — wraps a binary in a bubblewrap (bwrap) container.

     Bubblewrap creates a lightweight Linux namespace sandbox. It builds an
     entirely new mount tree from scratch — nothing is visible unless
     explicitly mounted in. The sandbox also unshares all namespaces (PID,
     user, IPC, UTS, cgroup) except network.

     ## Filesystem layout inside the sandbox

       Read-only bind mounts:
         /nix/store/<hash>-... — only the closure of allowedPackages
                   and pkg, not the entire nix store. Exception: when
                   shellHook is set, the entire /nix/store is bind-mounted
                   so that hook-provided store paths (e.g. from a direnv
                   devShell) are accessible.
         /etc/passwd   — user identity for programs that need it
         /etc/resolv.conf — DNS resolution
         /etc/ssl/certs   — TLS certificate verification
       Kernel filesystems:
         /proc   — mounted as a new procfs (only shows sandbox PIDs)
         /dev    — minimal devtmpfs (null, zero, urandom, etc.)
       Ephemeral tmpfs (empty, writable, lost on exit):
         /tmp    — scratch space
         $HOME   — prevents accidental reads of dotfiles; agent state
                    dirs are bind-mounted back on top of this
       Read-only bind mounts:
         $REPO_ROOT  — the git repo root, so git commands and reads of
                       files outside CWD work. CWD and GIT_DIR are
                       mounted rw on top of this.
       Read-write bind mounts:
         $CWD        — the project directory (always)
         stateDirs   — each path gets a --bind (e.g., ~/.config/claude)
         stateFiles  — each path gets a --bind (e.g., specific rc files)
         $GIT_DIR    — the .git dir, auto-detected. Needed when CWD is a
                       worktree and .git/common is outside CWD.
       Symlinks:
         /bin/sh -> bash — many scripts assume /bin/sh exists

     ## Key bwrap flags

       --unshare-all  Unshare every namespace type (mount, PID, user, IPC,
                      UTS, cgroup). The process is fully isolated.
       --share-net    Re-share the network namespace (undoes the network
                      part of --unshare-all). Required for API calls.
       --die-with-parent  Kill the sandbox if the parent shell exits, so
                          orphaned sandboxes don't accumulate.
       --setenv       Set environment variables inside the sandbox. PATH
                      is explicitly constructed from allowedPackages, so
                      only those binaries are callable. When shellHook is
                      set, hook-exported PATH entries are prepended.

     ## shellHook

       The optional shellHook argument is a bash script fragment that runs
       *outside* the sandbox before it is set up. Its exports are injected
       into the sandbox via --setenv. The primary use case is running
       direnv to activate the project's devShell, giving the agent exactly
       the tools declared in the project's flake.nix:

         shellHook = ''
           eval "$(direnv export bash)"
         '';

       Notes:
         - The hook runs with the host PATH, not the sandbox PATH.
         - PATH changes made by the hook are prepended to the sandbox PATH
           (allowedPackages PATH is always appended so the agent's required
           tools are never lost).
         - When shellHook is set, /nix/store is bind-mounted as a whole
           (read-only) rather than per-closure-path, so store paths added
           to PATH by the hook are accessible inside the sandbox.
         - direnv must have been allowed (direnv allow) for the .envrc
           to load without prompting.
         - The vars HOME, TERM, SHELL, SSL_CERT_DIR, NIX_SSL_CERT_FILE,
           and TMPDIR are never taken from the hook; the sandbox always
           manages those itself.
         - extraEnv entries are applied after hook exports, so explicit
           extraEnv takes precedence over hook-provided values for the
           same key.

     ## Debugging tips

       "No such file or directory":
         The binary is trying to access a path that isn't mounted.
         Run the wrapper with `strace -f -e trace=openat` to find the
         path, then add it to stateDirs/stateFiles.

       "Operation not permitted" on /proc or /dev:
         Unprivileged user namespaces may be disabled on the host.
         Check: sysctl kernel.unprivileged_userns_clone (needs to be 1).

       Git operations fail:
         If CWD is a git worktree, the real .git/common dir lives
         elsewhere. The wrapper auto-detects this with git rev-parse
         --git-common-dir, but it fails silently if git isn't available
         outside the sandbox. Check that $GIT_BIND is non-empty.

       DNS/TLS failures:
         Ensure /etc/resolv.conf and /etc/ssl/certs exist on the host.
         NixOS symlinks these — if the target is outside /etc, you may
         need to bind-mount the real paths.
*/
{ pkgs, shared }:
{ pkg, binName, outName, allowedPackages, stateDirs ? [ ], stateFiles ? [ ]
, extraEnv ? { }, restrictNetwork ? false, allowedDomains ? [ ]
, shellHook ? "" }:
let
  bashWrapper = shared.bashWrapper;
  envWrapper = pkgs.runCommand "env-wrapper" { } ''
    mkdir -p $out/bin
    cat > $out/bin/env <<'EOF'
    #!${pkgs.bashInteractive}/bin/bash
    exec ${pkgs.coreutils}/bin/env "$@"
    EOF
    chmod +x $out/bin/env
  '';
  implicitPackages = [ pkgs.cacert bashWrapper envWrapper ];
  pathStr = pkgs.lib.makeBinPath (allowedPackages ++ implicitPackages);
  mkDirsStr = builtins.concatStringsSep "\n"
    (map (dir: ''
      if [ -e "${dir}" ] && [ ! -d "${dir}" ]; then
        :
      else
        mkdir -p "${dir}"
      fi
    '') stateDirs);
  mkFilesStr = builtins.concatStringsSep "\n"
    (map (file: ''
      if [ -e "${file}" ] && [ -d "${file}" ]; then
        :
      else
        touch "${file}"
      fi
    '') stateFiles);
  bindDirsStr = builtins.concatStringsSep " "
    (map (dir: ''--bind "${dir}" "${dir}"'') stateDirs);
  # Adds each stateDir to the BOUND_PREFIXES shell array at runtime
  stateDirsBoundPrefixBashStr = builtins.concatStringsSep "\n"
    (map (dir: ''BOUND_PREFIXES+=("${dir}")'') stateDirs);

  symlinkHelpers = import ./symlink-helpers.nix { pkgs = pkgs; };

  symlinkResolutionBashStr = ''
    # Complete the set of already-bound path prefixes
    ${stateDirsBoundPrefixBashStr}
    BOUND_PREFIXES+=("$CWD")
    BOUND_PREFIXES+=("/etc/resolv.conf" "/etc/passwd" "/etc/ssl/certs" "/etc/static" "/etc/pki")
    [[ -n "$REPO_ROOT" ]] && BOUND_PREFIXES+=("$REPO_ROOT")
    [[ -n "$GIT_DIR" ]] && BOUND_PREFIXES+=("$GIT_DIR")

    ${symlinkHelpers.isAlreadyBoundBashStr}
    ${symlinkHelpers.addSymlinkTargetBashStr}
    ${symlinkHelpers.followSymlinkChainBashStr}

    # Resolve stateFile symlinks — bind resolved targets, not the symlink paths
    STATE_FILE_BINDS=""
    ${builtins.concatStringsSep "\n"
    (map symlinkHelpers.mkResolveFileBashStr stateFiles)}

    # Scan stateDirs for internal symlinks and bind their resolved targets
    ${builtins.concatStringsSep "\n"
    (map symlinkHelpers.mkScanDirBashStr stateDirs)}
  '';

  extraEnvStr = builtins.concatStringsSep " "
    (map (name: "--setenv ${name} ${builtins.toJSON extraEnv.${name}}")
      (builtins.attrNames extraEnv));

  conditionalNetworkingParams = import ./networking.nix {
    pkgs = pkgs; shared = shared; restrictNetwork = restrictNetwork; allowedDomains = allowedDomains;
  };

  # cacert and bashWrapper are always included: cacert so SSL/TLS
  # verification works, bashWrapper so the hardcoded SHELL and
  # /bin/sh symlink targets are always reachable in the store closure.
  # bashWrapper forces --norc --noprofile on every bash invocation so
  # that the sandboxed process cannot source /etc/bashrc or /etc/profile.
  closurePathsFile =
    pkgs.writeClosure (allowedPackages ++ implicitPackages ++ [ pkg ]);

  gitDetectionBashStr = ''
    GIT_BIND=""
    REPO_BIND=""
    if GIT_DIR=$(${pkgs.git}/bin/git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
      GIT_BIND="--bind $GIT_DIR $GIT_DIR"
      REPO_ROOT=$(dirname "$GIT_DIR")
      REPO_BIND="--ro-bind $REPO_ROOT $REPO_ROOT"
    fi
  '';

  # When shellHook is set, bind the entire /nix/store read-only so that
  # store paths added to PATH by the hook (e.g. from a direnv devShell)
  # are accessible inside the sandbox. The BOUND_PREFIXES array gets a
  # single "/nix/store" entry so the symlink resolver knows the whole
  # store is already covered.
  #
  # When shellHook is not set, only the pre-computed closure of
  # allowedPackages + pkg is bind-mounted (tighter security surface).
  nixStoreSetupBashStr = if shellHook != "" then ''
    # shellHook active: bind the entire nix store so hook-provided store
    # paths (e.g. from a direnv devShell) are accessible inside the sandbox.
    CLOSURE_BINDS=""
    BOUND_PREFIXES=()
    BOUND_PREFIXES+=("/nix/store")
  '' else ''
    # Build per-path ro-bind flags for the nix store closure
    CLOSURE_BINDS=""
    BOUND_PREFIXES=()
    while IFS= read -r storePath; do
      CLOSURE_BINDS="$CLOSURE_BINDS --ro-bind $storePath $storePath"
      BOUND_PREFIXES+=("$storePath")
    done < ${closurePathsFile}
  '';

  nixStoreBwrapStr = if shellHook != "" then
    "--ro-bind /nix/store /nix/store \\"
  else
    "--tmpfs /nix/store \\\n      \$CLOSURE_BINDS \\";

  # When shellHook is provided: source it outside the sandbox, snapshot the
  # environment before and after, then collect any new or changed exports.
  # Those exports are injected into the sandbox via --setenv. PATH changes
  # are handled separately: hook-provided PATH entries are prepended to the
  # static sandbox PATH (allowedPackages), so both the devShell tools and
  # the agent's own tools are always reachable.
  #
  # Vars that the sandbox manages itself (HOME, TERM, SHELL, PATH,
  # SSL_CERT_DIR, TMPDIR, etc.) are never taken from the hook.
  # extraEnv entries are applied after hook exports, so explicit config
  # always takes precedence over hook-provided values for the same key.
  shellHookBashStr = if shellHook != ""
    then
      let hookFile = pkgs.writeText "sandbox-shell-hook" shellHook;
      in ''
        # Source the shellHook and collect env vars it exports.
        _PRE_HOOK_PATH="$PATH"
        declare -A _PRE_HOOK_ENV
        while IFS= read -r -d "" _hook_entry; do
          _hook_k="''${_hook_entry%%=*}"
          _PRE_HOOK_ENV["$_hook_k"]="''${_hook_entry#*=}"
        done < <(env -0)

        # shellcheck source=/dev/null
        source "${hookFile}"

        _HOOK_EXTRA_ENVS=()
        _SANDBOX_PATH="${pathStr}"
        while IFS= read -r -d "" _hook_entry; do
          _hook_k="''${_hook_entry%%=*}"
          _hook_v="''${_hook_entry#*=}"
          # Skip vars the sandbox manages explicitly, and bash internals
          case "$_hook_k" in
            HOME|TERM|SHELL|PATH|SSL_CERT_DIR|NIX_SSL_CERT_FILE|TMPDIR) continue ;;
            SHLVL|_|OLDPWD|PWD|BASH_VERSINFO|BASH_VERSION|PPID|EUID|UID) continue ;;
            GROUPS|BASHOPTS|SHELLOPTS|IFS) continue ;;
          esac
          # Skip unchanged vars (only pass what the hook actually set)
          if [[ "''${_PRE_HOOK_ENV[''${_hook_k}]+set}" = "set" ]] && \
             [[ "''${_PRE_HOOK_ENV[''${_hook_k}]}" = "$_hook_v" ]]; then
            continue
          fi
          _HOOK_EXTRA_ENVS+=(--setenv "$_hook_k" "$_hook_v")
        done < <(env -0)

        # If the hook modified PATH, prepend its additions to the sandbox PATH
        # so devShell tools are available alongside allowedPackages binaries.
        if [[ "$PATH" != "$_PRE_HOOK_PATH" ]]; then
          _SANDBOX_PATH="$PATH:${pathStr}"
        fi
      ''
    else ''
      _HOOK_EXTRA_ENVS=()
      _SANDBOX_PATH="${pathStr}"
    '';

in pkgs.writeTextFile {
  name = outName;
  executable = true;
  destination = "/bin/${outName}";
  text = ''
    #!${pkgs.bashInteractive}/bin/bash
    CWD=$(pwd)
    ${conditionalNetworkingParams.warnIgnoredDomainsBashStr}
    ${mkDirsStr}
    ${mkFilesStr}
    ${gitDetectionBashStr}
    ${shellHookBashStr}
    ${nixStoreSetupBashStr}
    ${symlinkResolutionBashStr}
    ${conditionalNetworkingParams.proxyStartupBashStr}
    ${conditionalNetworkingParams.bashTrapCleanupStr}
    ${conditionalNetworkingParams.sandboxExecBashStr}${pkgs.bubblewrap}/bin/bwrap \
      ${conditionalNetworkingParams.etcResolvBind} \
      ${nixStoreBwrapStr}
      --ro-bind /etc/passwd /etc/passwd \
      --ro-bind-try /etc/ssl/certs /etc/ssl/certs \
      --ro-bind-try /etc/static /etc/static \
      --ro-bind-try /etc/pki /etc/pki \
      --proc /proc \
      --dev /dev \
      --tmpfs /tmp \
      --tmpfs "$HOME" \
      $REPO_BIND \
      --bind "$CWD" "$CWD" \
      ${bindDirsStr} \
      $STATE_FILE_BINDS \
      $SYMLINK_PARENT_DIRS \
      $readonlyStateFileSymlinks \
      $readWriteStateFileSymlinks \
      $GIT_BIND \
      --dir /usr \
      --dir /usr/bin \
      --symlink ${envWrapper}/bin/env /usr/bin/env \
      --symlink ${bashWrapper}/bin/bash /bin/sh \
      --unshare-all \
      --uid "$(id -u)" \
      --gid "$(id -g)" \
      --share-net \
      --die-with-parent \
      --chdir "$CWD" \
      --clearenv \
      --setenv HOME "$HOME" \
      --setenv TERM "$TERM" \
      --setenv SHELL "${bashWrapper}/bin/bash" \
      --setenv PATH "$_SANDBOX_PATH" \
      --setenv SSL_CERT_DIR "${pkgs.cacert}/etc/ssl/certs" \
      --setenv TMPDIR /tmp \
      ${conditionalNetworkingParams.sslCertEnvBubblewrapStr} \
      ${conditionalNetworkingParams.caCertBubblewrapStr} \
      ${conditionalNetworkingParams.proxyEnvBubblewrapStr} \
      ${extraEnvStr} \
      "''${_HOOK_EXTRA_ENVS[@]}" \
      ${pkg}/bin/${binName} "$@"
  '';
}
