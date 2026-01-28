{ lib, ... }:

{
  options.opinionatedDefaults = lib.mkEnableOption "opinionated defaults. This option is *not* recommended to be set";

  imports = [
    (lib.mkRemovedOptionModule ["debugging" "enable"] "Because we never really used it.")
    (lib.mkRemovedOptionModule ["environment" "noGraphicsPackages"] "Maintaining it out of tree got unviable after the kernel started to depend on a graphics library through ~5 packages.")
    (lib.mkRemovedOptionModule ["networking" "recommendedTimeServers"] "Please configure timeservers manually.")
    (lib.mkRemovedOptionModule ["services" "chrony" "configureServer"] "Please open your firewall UDP/TCP ports 123 and configure timeservers manually.")
    (lib.mkRemovedOptionModule ["services" "chrony" "openFirewall"] "Please open your firewall UDP/TCP ports 123 manually.")
    (lib.mkRemovedOptionModule ["services" "haproxy" "compileWithAWSlc"] ''just set `services.haproxy.package = pkgs.haproxy.override { sslLibrary = "aws-lc"; };`'')
    (lib.mkRemovedOptionModule ["services" "haproxy" "recommendedDefaults"] "it wasn't used")
  ];
}
