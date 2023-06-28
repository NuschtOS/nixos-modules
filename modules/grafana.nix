{ config, lib, libS, ... }:

let
  cfg = config.services.grafana;
  opt = options.services.grafana;
in
{
  options = {
    services.grafana.recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.settings.security.secret_key == opt.settings.security.secret_key.default;
        message = "services.grafana.settings.security.secret_key must be changed from it's default value!";
      }
    ];

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
