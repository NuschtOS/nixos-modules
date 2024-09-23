{ config, lib, ... }:

let
  cfg = config.services.hound;
  settingsAvailable = lib.versionAtLeast lib.version "24.11";
in
{
  options = {
    services.hound = {
      repos = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
        example = [ "https://github.com/NuschtOS/nixos-modules.git" ];
        description = ''
          A list of repos which should be fetched from their default branch. The display name is derived using builtins.baseNameOf and .git is stripped
        '';
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.repos != [ ]) {
    assertions = [ {
      assertion = settingsAvailable;
      message = "services.hound.repo only works with NixOS 24.11 and up. Please unset the option.";
    } ];

    services.hound = lib.optionalAttrs settingsAvailable {
      settings = {
        vcs-config.git.detect-ref = true;
        repos = lib.listToAttrs (map (url: lib.nameValuePair
          (lib.removeSuffix ".git" (builtins.baseNameOf url))
          { inherit url; }
        ) cfg.repos);
      };
    };
  };
}
