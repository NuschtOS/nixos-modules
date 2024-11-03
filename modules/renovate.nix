{ config, lib, libS, options, ... }:

let
  cfg = config.services.renovate;
in
{
  options.services.renovate = {
    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
  };

  config = lib.mkIf (cfg?enable && cfg.enable) {
    services = lib.optionalAttrs (options.services.renovate?settings) {
      renovate.settings = {
        cachePrivatePackages = true;
        configMigration = true;
        optimizeForDisabled = true;
        persistRepoData = true;
        repositoryCache = "enabled";
      };
    };
  };
}
