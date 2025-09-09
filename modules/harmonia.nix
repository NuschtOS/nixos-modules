{ config, lib, libS, ... }:

let
  cfg = config.services.harmonia;
in
{
  options = {
    services.harmonia = {
      configureNginx = lib.mkEnableOption "" // { description = "Whether to configure Nginx to serve Harmonia."; };

      domain = lib.mkOption {
        type = lib.types.str;
        description = "Domain under which harmonia should be available.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        description = "Port on which harmonia should internally listen on.";
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      harmonia.settings = lib.mkIf cfg.recommendedDefaults {
        bind = "[::]:${toString cfg.port}";
        priority = 50; # prefer cache.nixos.org
      };

      nginx = lib.mkIf cfg.configureNginx {
        enable = true;
        virtualHosts."${cfg.domain}".locations."/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
          # harmonia serves already compressed content and we want to preserve Content-Length
          extraConfig = /* nginx */ ''
            proxy_buffering off;
            brotli off;
            gzip off;
            zstd off;
          '';
        };
      };
    };
  };
}
