{ config, lib, libS, pkgs, ... }:

let
  cfg = config.boot.initrd.network.ssh;
  initrdEd25519Key = "/etc/ssh/initrd/ssh_host_ed25519_key";
  initrdRsaKey = "/etc/ssh/initrd/ssh_host_rsa_key";
in
{
  options = {
    boot.initrd.network.ssh = {
      configureHostKeys = lib.mkEnableOption "configure before generate openssh host keys for the initrd";
      generateHostKeys = lib.mkEnableOption "generate openssh host keys for the initrd. This must be enabled before they can be configured";
      regenerateWeakRSAHostKey = libS.mkOpinionatedOption "regenerate weak (less than 4096 bits) RSA host keys" // {
        default = config.services.openssh.regenerateWeakRSAHostKey;
      };
    };
  };

  config = lib.mkIf config.boot.initrd.network.ssh.enable {
    boot.initrd.network.ssh.hostKeys = lib.mkIf cfg.configureHostKeys [
      initrdEd25519Key
      initrdRsaKey
    ];

    system.activationScripts.generateInitrdOpensshHostKeys = let
      sshKeygen = "${config.programs.ssh.package}/bin/ssh-keygen";
    in lib.optionalString cfg.generateHostKeys /* bash */ ''
      if [[ ! -e ${initrdEd25519Key} || ! -e ${initrdRsaKey} ]]; then
        echo "Generating OpenSSH initrd hostkeys..."
        mkdir -m700 -p /etc/ssh/initrd/
        ${sshKeygen} -t ed25519 -N "" -f ${initrdEd25519Key}
        ${sshKeygen} -t rsa -b 4096 -N "" -f ${initrdRsaKey}
      fi
    '' + lib.optionalString cfg.regenerateWeakRSAHostKey /* bash */ ''
      if [[ -e ${initrdRsaKey} && $(${sshKeygen} -l -f ${initrdRsaKey} | ${pkgs.gawk}/bin/awk '{print $1}') != 4096 ]]; then
        echo "Regenerating OpenSSH initrd RSA hostkey which had less than 4096 bits..."
        rm -f ${initrdRsaKey} ${initrdRsaKey}.pub
        ${sshKeygen} -t rsa -b 4096 -N "" -f ${initrdRsaKey}
      fi
    '';
  };
}
