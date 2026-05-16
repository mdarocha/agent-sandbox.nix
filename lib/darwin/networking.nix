{ pkgs, shared, restrictNetwork, allowedDomains }:
let
  mkAllowlistFile = shared.mkAllowlistFile;
  hasAllowedDomains = shared.hasAllowedDomains;
  mkProxyStartupBashStr = shared.mkProxyStartupBashStr;
in
if restrictNetwork then
  let allowlistFileStr = mkAllowlistFile allowedDomains;
  in {
    warnIgnoredDomainsBashStr = "";
    proxyEnvInlineBashStr = ''
      HTTP_PROXY="http://127.0.0.1:$_PROXY_PORT" HTTPS_PROXY="http://127.0.0.1:$_PROXY_PORT" http_proxy="http://127.0.0.1:$_PROXY_PORT" https_proxy="http://127.0.0.1:$_PROXY_PORT"'';
    caCertEnvInlineBashStr = ''
      SSL_CERT_FILE="$_COMBINED_CA_BUNDLE" NIX_SSL_CERT_FILE="$_COMBINED_CA_BUNDLE" NODE_EXTRA_CA_CERTS="$_CA_CERT_FILE" REQUESTS_CA_BUNDLE="$_COMBINED_CA_BUNDLE"'';
    networkSeatbeltRulesStr = ''
      ;; Network — restricted to localhost only (proxy-based domain filtering)
      (allow network-outbound (remote ip "localhost:*"))
      (allow network-outbound (remote unix-socket))
      (allow network-bind (local ip "localhost:*"))
      (allow system-socket)
    '';
    proxyStartupBashStr =
      mkProxyStartupBashStr allowlistFileStr "127.0.0.1";
    bashTrapCleanupStr = ''
      trap 'kill $_PROXY_PID 2>/dev/null; rm -f "$_CA_CERT_FILE" "$_COMBINED_CA_BUNDLE"; rm -rf "$SANDBOX_HOME" "$SANDBOX_PROFILE"' EXIT'';
    sandboxExecBashStr = "";
  }
else {
  warnIgnoredDomainsBashStr =
    if (hasAllowedDomains allowedDomains) then ''
      echo "WARNING: allowedDomains is set but restrictNetwork is false — domains will be ignored" >&2
    '' else
      "";
  proxyEnvInlineBashStr = "";
  caCertEnvInlineBashStr = ''
    SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" NIX_SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"'';
  networkSeatbeltRulesStr = ''
    ;; Network
    (allow network*)
    (allow system-socket)
  '';
  proxyStartupBashStr = "";
  bashTrapCleanupStr = ''trap 'rm -rf "$SANDBOX_HOME" "$SANDBOX_PROFILE"' EXIT'';
  sandboxExecBashStr = "exec ";
}
