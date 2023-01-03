{ config, lib, libS, ... }:

let
  cfg = config.boot.zfs;
in
{
  options = {
    boot.zfs.recommendedDefaults = libS.mkOpinionatedOption "enable recommended ZFS settings";
  };

  config = lib.mkIf (cfg.recommendedDefaults && cfg.enabled) {
    boot = {
      kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
      zfs.forceImportRoot = false;
    };

    services.zfs.autoScrub.enable = true;
  };
}
