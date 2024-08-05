{ config, lib, ... }:

let
  cfg = config.services.mailman;
in
{
  options = {
    services.mailman = {
      enablePostgres = lib.mkEnableOption "configure postgres as a database backend";

      openidConnect = {
        enable = lib.mkEnableOption "login only via OpenID Connect";
        clientSecretFile = lib.mkOption {
          type = lib.types.str;
          description = "Path of the file containing the client id";
        };
      };
    };
  };

  config.environment.etc = lib.mkIf (cfg.enable && cfg.openidConnect.enable) {
    "mailman3/settings.py".text = lib.mkAfter /* python */ ''
      INSTALLED_APPS.append('allauth.socialaccount.providers.openid_connect')

      with open('${cfg.openidConnect.clientSecretFile}') as f:
        SOCIALACCOUNT_PROVIDERS = {
          "openid_connect": {
            "APPS": [{
              "provider_id": "dex",
              "name": "${config.services.portunus.webDomain}",
              "client_id": "mailman",
              "secret": f.read(),
              "settings": {
                "server_url": "${config.services.dex.settings.issuer}",
              },
            }],
          }
        }
    '';
  };

  config.services.mailman = lib.mkIf (cfg.enable && cfg.enablePostgres) {
    settings.database = {
      class = "mailman.database.postgresql.PostgreSQLDatabase";
      url = "postgresql://mailman@/mailman?host=/run/postgresql";
    };
    webSettings = {
      DATABASES.default = {
        ENGINE = "django.db.backends.postgresql";
        NAME = "mailman-web";
        USER = "mailman-web";
      };
    };
  };

  config.services.postgresql = lib.mkIf (cfg.enable && cfg.enablePostgres) {
    ensureDatabases = [ "mailman" "mailman-web" ];
    ensureUsers = [ {
      name = "mailman";
      ensureDBOwnership = true;
    } {
      name = "mailman-web";
      ensureDBOwnership = true;
    } ];
  };

  config.services.portunus.dex = lib.mkIf cfg.openidConnect.enable {
    enable = true;
    oidcClients = [{
      callbackURL = "https://${lib.elemAt cfg.webHosts 0}/accounts/oidc/dex/login/callback/";
      id = "mailman";
    }];
  };
}
