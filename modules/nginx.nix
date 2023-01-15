{ config, lib, libS, ... }:

let
  cfg = config.services.nginx;
in
{
  options.services.nginx = {
    allRecommended = libS.mkOpinionatedOption "all recommended options";

    generateDhparams = libS.mkOpinionatedOption "generate more secure, 2048 bits dhparams replacing the default 1024 bits";

    openFirewall = libS.mkOpinionatedOption "open the firewall port for the http (80) and https (443) default ports";

    resolverAddrFromNameserver = libS.mkOpinionatedOption "set resolver address to environment.nameservers";

    rotateLogsFaster = libS.mkOpinionatedOption "keep logs only for 7 days and rotate them daily";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 80 443 ];

    services = {
      logrotate.settings.nginx = lib.mkIf cfg.rotateLogsFaster {
        frequency = "daily";
        rotate = 7;
      };

      nginx = lib.mkMerge [
        {
          resolver.addresses =
            let
              isIPv6 = addr: builtins.match ".*:.*:.*" addr != null;
              escapeIPv6 = addr:
                if isIPv6 addr then
                  "[${addr}]"
                else
                  addr;
            in
            lib.optionals (cfg.resolverAddrFromNameserver && config.networking.nameservers != [ ]) (map escapeIPv6 config.networking.nameservers);
          sslDhparam = lib.mkIf cfg.generateDhparams config.security.dhparams.params.nginx.path;
        }

        (lib.mkIf cfg.allRecommended (libS.modules.mkRecursiveDefault {
          recommendedBrotliSettings = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
        }))
      ];
    };

    security.dhparams = lib.mkIf cfg.generateDhparams {
      enable = cfg.generateDhparams;
      params.nginx = { };
    };
  };
}
