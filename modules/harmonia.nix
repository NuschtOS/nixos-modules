{ config, lib, libS, ... }:

let
  cfg = config.services.harmonia.cache;
in
{
  options = {
    services.harmonia.cache = {
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

  imports = [
    (lib.mkRenamedOptionModule ["services" "harmonia" "configureNginx"] ["services" "harmonia" "cache" "configureNginx"])
    (lib.mkRenamedOptionModule ["services" "harmonia" "domain"] ["services" "harmonia" "cache" "domain"])
    (lib.mkRenamedOptionModule ["services" "harmonia" "port"] ["services" "harmonia" "cache" "port"])
    (lib.mkRenamedOptionModule ["services" "harmonia" "recommendedDefaults"] ["services" "harmonia" "cache" "recommendedDefaults"])
  ];

  config = lib.mkIf cfg.enable {
    services = {
      harmonia = let
        settings = lib.mkIf cfg.recommendedDefaults {
          bind = "[::]:${toString cfg.port}";
          priority = 50; # prefer cache.nixos.org
        };
      in if cfg?cache then {
        cache = { inherit settings; };
      } else {
        inherit settings;
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
