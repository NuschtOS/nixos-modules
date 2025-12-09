{ config, lib, libS, ... }:

let
  cfg = config.services.vaultwarden;
in
{
  options = {
    services.vaultwarden = {
      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      vaultwarden.config = lib.mkMerge [
        (lib.mkIf cfg.recommendedDefaults {
          DATA_FOLDER = "/var/lib/vaultwarden"; # changes data directory
          LOG_LEVEL = "warn";
          SIGNUPS_VERIFY = true;
          TRASH_AUTO_DELETE_DAYS = 30;
        })
      ];
    };

    systemd.services.vaultwarden.serviceConfig = lib.mkIf cfg.recommendedDefaults {
      StateDirectory = lib.mkForce "vaultwarden"; # modules defaults to bitwarden_rs
    };
  };
}
