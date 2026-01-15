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
      reposMsBetweenPoll = lib.mkOption {
        type = with lib.types; nullOr ints.positive;
        default = null;
        example = lib.literalExpression "1000 * 3600 * 8";
        description = "Milliseconds (ms) between fetching repositories. Hound defaults to 1000 * 30 (30s) internally internally.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.hound.settings = lib.mkIf (cfg.repos != [ ]) {
      vcs-config.git.detect-ref = true;
      repos = lib.listToAttrs (map (url: lib.nameValuePair
        (lib.removeSuffix ".git" (builtins.baseNameOf url))
        {
          ms-between-poll = lib.mkIf (cfg.reposMsBetweenPoll != null) cfg.reposMsBetweenPoll;
          inherit url;
        }
      ) cfg.repos);
    };
  };
}
