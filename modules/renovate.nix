{ config, lib, libS, ... }:

let
  cfg = config.services.renovate;
in
{
  options = {
    services.renovate = {
      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services.renovate.settings = lib.mkIf cfg.recommendedDefaults {
      cachePrivatePackages = true;
      configMigration = true;
      optimizeForDisabled = true;
      persistRepoData = true;
      repositoryCache = "enabled";
    };
  };
}
