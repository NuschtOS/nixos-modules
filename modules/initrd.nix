{ config, lib, libS, options, pkgs, ... }:

let
  cfg = config.boot.initrd;
  opt = options.boot.initrd;
  cfgn = config.boot.initrd.network;
  optn = options.boot.initrd.network;
  initrdEd25519Key = "/etc/ssh/initrd/ssh_host_ed25519_key";
  initrdRsaKey = "/etc/ssh/initrd/ssh_host_rsa_key";
in
{
  options = {
    boot.initrd = {
      luks.deterministicUnlock = libS.mkOpinionatedOption "unlock luks disks in deterministic order" // {
        default = config.opinionatedDefaults && config.boot.initrd.systemd.enable;
      };

      network = {
        checkKernelModules = {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = cfgn.ssh.enable;
            defaultText = lib.literalExpression "config.boot.initrd.network.ssh.enable";
            description = ''
              Whether to check if all interface related kernel modules are loaded in initrd.

              This can be used to make sure that you are not getting locked out when unlocking LUKS disks over the network in initrd.
            '';
          };
          skipModules = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Name of modules that are allowed to be missing.";
          };
        };

        ssh = {
          configureHostKeys = lib.mkEnableOption "" // { description = "Whether to configure before generate openssh host keys for the initrd"; };
          generateHostKeys = lib.mkEnableOption "" // { description = "Whether to generate openssh host keys for the initrd. This must be enabled before they can be configured"; };
          regenerateWeakRSAHostKey = libS.mkOpinionatedOption "regenerate weak (less than 4096 bits) RSA host keys" // {
            default = config.services.openssh.regenerateWeakRSAHostKey;
          };
        };
      };
    };
  };

  config = lib.mkIf cfgn.enable {
    assertions = [ {
      assertion = cfg.luks.deterministicUnlock -> cfg.systemd.enable;
      message = "${opt.luks.deterministicUnlock} requires ${opt.systemd.enable} to be true";
    } ];

    boot.initrd = {
      network.ssh.hostKeys = lib.mkIf cfgn.ssh.configureHostKeys [
        initrdEd25519Key
        initrdRsaKey
      ];

      systemd.contents."/etc/profile" = lib.mkIf (cfg.luks.devices != { }) {
        text = ''
          echo "If the boot process does not continue in 5 seconds, try running:"
          echo "  systemctl start default.target"
        ''
        + lib.concatMapAttrsStringSep "\n"
          (volume: disk: "systemd-cryptsetup attach ${volume} ${disk.device}")
          cfg.luks.devices;
      };
    };

    system = {
      activationScripts.generateInitrdOpensshHostKeys = let
        sshKeygen = lib.getExe' config.programs.ssh.package "ssh-keygen";
      in lib.mkIf (cfgn.ssh.generateHostKeys || cfgn.ssh.regenerateWeakRSAHostKey) {
        deps = [ "users" ]; # might not work if userborn is used...
        text = let
          id = toString config.ids.uids.root;
          rootUser = config.users.users.root;
        in lib.optionalString cfgn.ssh.generateHostKeys /* bash */ ''
          if [[ ! -e ${initrdEd25519Key} || ! -e ${initrdRsaKey} ]]; then
            echo "Generating OpenSSH initrd hostkeys..."
            mkdir -m700 -p /etc/ssh/initrd/
            # big hack but don't tell anyone
            # only here to satisfy ss-keygen
            # https://github.com/openssh/openssh-portable/blob/eddd1d2daa64a6ab1a915ca88436fa41aede44d4/ssh-keygen.c#L3337
            [ -e /etc/passwd ] || echo 'root:x:${id}:${id}:${rootUser.description}:${rootUser.home}:${rootUser.shell}' > /etc/passwd

            ${sshKeygen} -t ed25519 -N "" -f ${initrdEd25519Key}
            ${sshKeygen} -t rsa -b 4096 -N "" -f ${initrdRsaKey}
          fi
        '' + lib.optionalString cfgn.ssh.regenerateWeakRSAHostKey /* bash */ ''
          if [[ -e ${initrdRsaKey} && $(${sshKeygen} -l -f ${initrdRsaKey} | ${lib.getExe pkgs.gawk} '{print $1}') != 4096 ]]; then
            echo "Regenerating OpenSSH initrd RSA hostkey which had less than 4096 bits..."
            rm -f ${initrdRsaKey} ${initrdRsaKey}.pub
            ${sshKeygen} -t rsa -b 4096 -N "" -f ${initrdRsaKey}
          fi
        '';
      };

      preSwitchChecks."checkForNetworkKernelModules" = lib.mkIf cfgn.checkKernelModules.enable /* bash */ ''
        interfaces=$(ls /sys/class/net/)
        for interface in $interfaces; do
          # skip special devices like lo or virtual devices
          readlink -f "/sys/class/net/$interface/device/driver" >/dev/null || continue

          driver="$(basename "$(readlink -f "/sys/class/net/$interface/device/driver")")"

          if [[ "${toString cfgn.checkKernelModules.skipModules}" =~ $driver ]]; then
            continue
          fi

          if ! [[ "${toString config.boot.initrd.availableKernelModules}" =~ $driver ]]; then
            echo
            echo
            echo "  Kernel module \"$driver\" is missing in \"${opt.availableKernelModules}\"!"
            echo "  Unlock in initrd may fail because of this."
            echo "  Alternatively the \"${optn.checkKernelModules.skipModules}\" option can be used to skip the module."
            echo
            echo
            exit 1
          fi
        done
      '';
    };
  };
}
