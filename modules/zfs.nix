{ config, lib, ... }:

let
  cfg = config.boot.zfs;
in
{
  config = lib.mkIf cfg.enabled {
    boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

    services.zfs.autoScrub.enable = true;
  };
}
