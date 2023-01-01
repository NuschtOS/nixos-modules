{ config, lib, libS, ... }:

let
  cfg = config.services.nginx;
in
{
  options.services.nginx = {
    generateDhparams = lib.mkOption {
      type = lib.types.bool;
      default = config.opinionatedDefaults;
      description = lib.mdDoc "Wether to generate more secure, 2048 bits dhparams replacing the default 1024 bits.";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = config.opinionatedDefaults;
      description = lib.mdDoc "Wether to open the firewall port for the http (80) and https (443) default ports.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 80 443 ];

    services.nginx = lib.mkMerge [
      {
        sslDhparam = config.security.dhparams.params.nginx.path;
      }

      (lib.mkIf config.opinionatedDefaults (libS.modules.mkRecursiveDefault {
        recommendedBrotliSettings = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
        resolver.addresses = let
          isIPv6 = addr: builtins.match ".*:.*:.*" addr != null;
          escapeIPv6 = addr: if isIPv6 addr then
            "[${addr}]"
          else
            addr;
        in
          lib.optionals (config.networking.nameservers != [ ]) (map escapeIPv6 config.networking.nameservers);
      }))
    ];

    security.dhparams = {
      enable = cfg.generateDhparams;
      params.nginx = { };
    };
  };
}
