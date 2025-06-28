{ config, lib, libS, ... }:

let
  cfg = config.services.vaultwarden;
  usingPostgres = cfg.dbBackend == "postgresql";
in
{
  options = {
    services.vaultwarden = {
      configureNginx = libS.mkOpinionatedOption "configure nginx for the configured domain";

      domain = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = "The domain under which vaultwarden will be reachable.";
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = cfg.configureNginx -> cfg.domain != null;
      message = ''
        Setting services.vaultwarden.configureNginx to true requires configuring services.vaultwarden.domain!
      '';
    }];

    services = {
      nginx = lib.mkIf cfg.configureNginx {
        upstreams.vaultwarden.servers."127.0.0.1:${toString cfg.config.ROCKET_PORT}" = { };
        virtualHosts.${cfg.domain}.locations = {
          "/".proxyPass = "http://vaultwarden";
          "= /notifications/hub" = {
            proxyPass = "http://vaultwarden";
            proxyWebsockets = true;
          };
        };
      };

      postgresql = lib.mkIf usingPostgres {
        enable = true;
        ensureDatabases = [ "vaultwarden" ];
        ensureUsers = [{
          name = "vaultwarden";
          ensureDBOwnership = true;
        }];
      };

      vaultwarden.config = lib.mkMerge [
        {
          DATABASE_URL = lib.mkIf usingPostgres "postgresql:///vaultwarden?host=/run/postgresql";
          DOMAIN = lib.mkIf (cfg.domain != null) "https://${cfg.domain}";
        }
        (lib.mkIf cfg.recommendedDefaults {
          DATA_FOLDER = "/var/lib/vaultwarden"; # changes data directory
          ENABLE_WEBSOCKET = true;
          LOG_LEVEL = "warn";
          PASSWORD_ITERATIONS = 600000;
          ROCKET_ADDRESS = "127.0.0.1";
          ROCKET_PORT = lib.mkDefault 8222;
          SIGNUPS_VERIFY = true;
          TRASH_AUTO_DELETE_DAYS = 30;
        })
      ];
    };

    systemd.services.vaultwarden = let
      postgresqlTarget = if lib.hasAttr "postgresql" config.systemd.targets then "postgresql.target" else "postgresql.service";
    in {
      after = lib.mkIf usingPostgres [ postgresqlTarget ];
      requires = lib.mkIf usingPostgres [ postgresqlTarget ];
      serviceConfig = lib.mkIf cfg.recommendedDefaults {
        StateDirectory = lib.mkForce "vaultwarden"; # modules defaults to bitwarden_rs
      };
    };
  };
}
