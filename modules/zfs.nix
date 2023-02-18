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
      kernelPackages =
        let
          ver = config.boot.zfs.package.latestCompatibleLinuxPackages.kernel.version;
        in
        # 6.0 has a bug in the bind syscall and does not error correct when the port is already in use
          # https://lists.fedoraproject.org/archives/list/devel@lists.fedoraproject.org/thread/7VPNMC77YC3SI5LFYKUA4B5MTFPLTLVB/
          # https://lore.kernel.org/stable/CAFsF8vL4CGFzWMb38_XviiEgxoKX0GYup=JiUFXUOmagdk9CRg@mail.gmail.com/
        lib.mkIf (lib.versions.majorMinor ver != "6.0") config.boot.zfs.package.latestCompatibleLinuxPackages;
      zfs.forceImportRoot = false;
    };

    services.zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    virtualisation.containers.storage.settings = lib.recursiveUpdate options.virtualisation.containers.storage.settings.default {
      # fixes: Error: 'overlay' is not supported over zfs, a mount_program is required: backing file system is unsupported for this graph driver
      storage.options.mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs";
    };
  };
}
