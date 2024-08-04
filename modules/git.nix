{ config, lib, libS, ... }:

let
  cfg = config.programs.git;
in
{
  options.programs.git = {
    configureDelta = lib.mkEnableOption "" // { description = "Whether to configure delta, a syntax-highlighting pager for git."; };

    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
  };

  config = {
    programs.git.config = lib.mkMerge [
      (lib.mkIf cfg.recommendedDefaults {
        aliases = {
          ci = "commit";
          co = "checkout";
          st = "status";
        };
        interactive.singlekey = true;
        pull.rebase = true;
      })

      # https://github.com/dandavison/delta?tab=readme-ov-file#get-started
      (lib.mkIf cfg.configureDelta {
        core.pager = "delta";
        delta = {
          features = "line-numbers decorations relative-paths";
          light = false;
          navigate = true;
          relative-paths = true;
          whitespace-error-style = "22 reverse";
        };
        "delta decorations" = {
          commit-decoration-style = "bold yellow box ul";
          file-decoration-style = "none";
          file-style = "bold yellow";
          map-styles = "bold purple => normal bold rebeccapurple, bold cyan => syntax bold darkslategray";
        };
        diff.colorMoved = "default";
        interactive.diffFilter = "delta --color-only";
        merge.conflictstyle = "diff3";
      })
    ];
  };
}
