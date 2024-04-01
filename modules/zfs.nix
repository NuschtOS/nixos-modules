{ config, lib, libS, options, pkgs, ... }:

let
  cfg = config.boot.zfs;
in
{
  options = {
    boot.zfs = {
      recommendedDefaults = libS.mkOpinionatedOption "enable recommended ZFS settings";
      latestCompatibleKernel = libS.mkOpinionatedOption "use the latest ZFS compatible kernel";
    };
  };

  config = lib.mkIf cfg.enabled {
    boot.kernelPackages = lib.mkIf cfg.latestCompatibleKernel (lib.mkDefault config.boot.zfs.package.latestCompatibleLinuxPackages);

    services.zfs = lib.mkIf cfg.recommendedDefaults {
      autoScrub.enable = true;
      trim.enable = true;
    };

    virtualisation.containers.storage.settings = lib.mkIf cfg.recommendedDefaults (lib.recursiveUpdate options.virtualisation.containers.storage.settings.default {
      # fixes: Error: 'overlay' is not supported over zfs, a mount_program is required: backing file system is unsupported for this graph driver
      storage.options.mount_program = lib.getExe pkgs.fuse-overlayfs;
    });
  };
}
