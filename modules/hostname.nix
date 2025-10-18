# Originally based on srvos which is licensed under MIT
# https://github.com/nix-community/srvos/blob/main/nixos/common/detect-hostname-change.nix
{ config, lib, libS, ... }:

{
  options = {
    networking.detectHostnameChange = libS.mkOpinionatedOption "warn if the hostname changes between deploys";
  };

  config = lib.mkIf config.networking.detectHostnameChange {
    assertions = [
      {
        assertion = config.networking.hostName != "";
        message = "networking.detectHostnameChange requires networking.hostName to be set.";
      }
    ];

    system.preSwitchChecks.detectHostnameChange = ''
      detectHostnameChange() {
        actual=$(< /proc/sys/kernel/hostname)

        # Ignore if the system is getting installed
        # https://github.com/nix-community/nixos-images/blob/2fc023e024c0a5e8e98ae94363dbf2962da10886/nix/installer.nix#L12-L13
        if [[ ! -e /run/booted-system || "$actual" == "nixos-installer" ]]; then
          return
        fi

        desired=${config.networking.hostName}

        if [[ "$actual" = "$desired" ]]; then
          return
        fi

        # Useful for automation
        if [[ "''${EXPECTED_HOSTNAME:-}" = "$desired" ]]; then
          return
        fi

        echo >&2 "WARNING: machine hostname change detected from '$actual' to '$desired'"
        echo >&2
        echo >&2 "Are you deploying on the right host?"
        echo >&2
        echo >&2 "Type YES to continue:"
        read -r reply
        if [[ $reply != YES ]]; then
          echo "aborting"
          exit 1
        fi
      }
      detectHostnameChange
    '';
  };
}
