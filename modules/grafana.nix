{ config, lib, libS, ... }:

let
  cfg = config.services.grafana;
in
{
  options = {
    services.grafana.recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
  };

  config = lib.mkIf cfg.enable {
    services.grafana.settings = lib.mkIf cfg.opinionatedDefaults (libS.modules.mkRecursiveDefault {
      analytics = {
        check_for_updates = false;
        reporting_enabled = false;
      };
      security = {
        cookie_secure = true;
        content_security_policy = true;
      };
      server = {
        enable_gzip = true;
        http_addr = "127.0.0.1";
        root_url = "https://${cfg.settings.server.domain}";
      };
    });
  };
}
