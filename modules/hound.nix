{ config, lib, ... }:

let
  cfg = config.services.hound;
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

  config = lib.mkIf cfg.enable {
    services.hound.settings = lib.mkIf (cfg.repos != [ ]) {
      vcs-config.git.detect-ref = true;
      repos = lib.listToAttrs (map (url: lib.nameValuePair
        (lib.removeSuffix ".git" (builtins.baseNameOf url))
        { inherit url; }
      ) cfg.repos);
    };
  };
}
