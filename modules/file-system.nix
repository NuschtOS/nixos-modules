{ config, lib, ... }:

let
  cfg = config.fileSystem.checkIfDevicesExist;
  inherit (config.boot) zfs;
in
{
  options = {
    fileSystem.checkIfDevicesExist = lib.mkOption {
      type = lib.types.bool;
      default = config.opinionatedDefaults;
      description = ''
        Whether to check if all devices referenced under `fileSystems` exist before doing a switch.
      '';
    };
  };

  config = lib.mkIf cfg {
    system.preSwitchChecks."checkAllFileSystemDevicesExist" = /* bash */ ''
      # shellcheck disable=SC2030,SC2031
      PATH=$PATH:${lib.makeBinPath (lib.optional zfs.enabled zfs.package)}
    '' + lib.concatMapAttrsStringSep "\n"
      (mountPath: disk: let
        f = if disk.fsType or "" == "zfs" then
          {
            check = "zfs list -H -o name \"${disk.device}\" >/dev/null";
            dev = "ZFS dataset '${disk.device}'";
          }
        else
          {
            check = "[[ -e ${disk.device} ]]";
            dev = "'${disk.device}'";
          };
      in
        /* bash */ ''
          if ! ${f.check}; then
            echo
            echo
            echo "fileSystems.\"${mountPath}\" is supposed to be mounted from ${f.dev}, but it does not exist"
            echo
            echo
            exit 1
          fi
        ''
      ) (
        (lib.filterAttrs (n: v: lib.any (o: o == "nofail") v.options) config.fileSystems)
        // lib.pipe config.swapDevices [
          (lib.filter (s: lib.any (o: o == "nofail") s.options))
          (i: lib.genAttrs' i (s: lib.nameValuePair (lib.baseNameOf s.device) s))
        ]
        // config.boot.initrd.luks.devices
      );
  };
}
