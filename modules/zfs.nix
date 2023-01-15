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
      # TODO: reactivate when this no longer points to 6.0 which has the following bug:
      # https://lists.fedoraproject.org/archives/list/devel@lists.fedoraproject.org/thread/7VPNMC77YC3SI5LFYKUA4B5MTFPLTLVB/
      # https://lore.kernel.org/stable/CAFsF8vL4CGFzWMb38_XviiEgxoKX0GYup=JiUFXUOmagdk9CRg@mail.gmail.com/
      # kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
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
