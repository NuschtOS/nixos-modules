{ config, lib, libS, ... }:

let
  cfg = config.services.renovate;
in
{
  options.services.renovate = lib.optionalAttrs (!lib.versionAtLeast lib.version "24.11") {
    # TODO: clean up when updating to 24.11
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      internal = !(lib.versionAtLeast lib.version "24.11");
    };
    settings = lib.mkOption {
      type = lib.types.freeformSetting;
      internal = !(lib.versionAtLeast lib.version "24.11");
    };
  } // {
    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
  };

  config = lib.mkIf cfg.enable {
    services.renovate.settings = {
      cachePrivatePackages = true;
      configMigration = true;
      optimizeForDisabled = true;
      persistRepoData = true;
      repositoryCache = "enabled";
    };
  };
}
