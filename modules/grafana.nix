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
      # no analytics, sorry, not sorry
      analytics = {
        # TODO: drop after https://github.com/NixOS/nixpkgs/pull/240323 is merged
        check_for_updates = false;
        feedback_links_enabled = false;
        reporting_enabled = false;
      };
      security = {
        cookie_secure = true;
        content_security_policy = true;
        strict_transport_security = true;
      };
      server = {
        enable_gzip = true;
        root_url = "https://${cfg.settings.server.domain}";
      };
    });
  };
}
