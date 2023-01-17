{ config, lib, libS, ... }:

{
  options.nix = {
    deleteChannels = lib.mkEnableOption "" // { description = "Whether to delete all channels on a system switch."; };

    deleteUserProfiles = lib.mkEnableOption "" // { description = "Whether to delete all channels on a system switch."; };
  };

  config = {
    system.activationScripts = {
      deleteChannels = lib.mkIf config.nix.deleteChannels ''
        echo "Deleting all channels..."
        rm -rf /root/.nix-channels /home/*/.nix-channels /nix/var/nix/profiles/per-user/*/channels*
      '';

      deleteUserProfiles = lib.mkIf config.nix.deleteUserProfiles ''
        echo "Deleting all user profiles..."
        rm -rf /root/.nix-profile /home/*/.nix-profile /nix/var/nix/profiles/per-user/*/profile*
      '';
    };
  };
}
