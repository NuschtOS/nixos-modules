{ config, lib, libS, options, pkgs, ... }:

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

    virtualisation = {
      containers.storage.settings = lib.recursiveUpdate options.virtualisation.containers.storage.settings.default {
        # fixes: Error: 'overlay' is not supported over zfs, a mount_program is required: backing file system is unsupported for this graph driver
        storage.options.mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs";
      };
    };
  };
}
