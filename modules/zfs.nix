{ config, lib, libS, pkgs, ... }:

let
  cfg = config.boot.zfs;
in
{
  options = {
    boot.zfs = {
      recommendedDefaults = libS.mkOpinionatedOption "enable recommended ZFS settings";
    };
  };

  imports = [
    (lib.mkRemovedOptionModule ["boot" "zfs" "latestCompatibleKernel"] ''
      latestCompatibleKernel has been removed because zfs.passthru.latestCompatibleLinuxPackages has been effectively removed.
      Consider using <https://github.com/nix-community/srvos/blob/main/nixos/mixins/latest-zfs-kernel.nix> instead.
    '')
  ];

  config = lib.mkIf cfg.enabled {
    services.zfs = lib.mkIf cfg.recommendedDefaults {
      autoScrub.enable = true;
      trim.enable = true;
    };

    virtualisation.containers.storage.settings = lib.mkIf cfg.recommendedDefaults {
      # fixes: Error: 'overlay' is not supported over zfs, a mount_program is required: backing file system is unsupported for this graph driver
      storage.options.mount_program = lib.getExe pkgs.fuse-overlayfs;
    };
  };
}
