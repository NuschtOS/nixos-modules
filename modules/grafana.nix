{ config, lib, libS, ... }:

let
  cfg = config.services.grafana;
in
{
  options = {
    services.grafana.recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
  };

  config = lib.mkIf cfg.enable {
    services.grafana.settings = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
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
        root_url = "https://${cfg.settings.server.domain}";
      };
    });
  };
}
