{ config, lib, libS, ... }:

let
  cfg = config.programs.tmux;
in
{
  options = {
    programs.tmux.allRecommended = libS.mkOpinionatedOption "set recommended tmux settings";
  };

  config = lib.mkIf cfg.allRecommended {
    programs.tmux = {
      aggressiveResize = true;
      baseIndex = 1;
      clock24 = true;
      escapeTime = 100;
      terminal = "xterm-256color";
      extraConfig = ''
        # focus events enabled for terminals that support them
        set -g focus-events on

        # open new tab in PWD
        bind '"' split-window -c "#{pane_current_path}"
        bind % split-window -h -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"
      '';
    };
  };
}
