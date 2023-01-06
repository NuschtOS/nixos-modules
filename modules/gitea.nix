{ config, lib, libS, ... }:

let
  cfg = config.services.gitea;
in
{
  options = {
    services.gitea.recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
  };

  config = lib.mkIf cfg.enable {
    services.gitea.settings = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
      "update_checker".ENABLED = false;
      other.SHOW_FOOTER_VERSION = false;
      session.COOKIE_SECURE = lib.mkForce true;
      time.DEFAULT_UI_LOCATION = config.time.timeZone;
    });
  };
}
