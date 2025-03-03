{ config, lib, libS, ... }:

let
  cfg = config.programs.vim;
in
{
  options = {
    programs.vim = {
      undofile = libS.mkOpinionatedOption "configure undofile to save undo/redo across editor re-opens";
      rememberCursorPosition = libS.mkOpinionatedOption "remember the last cursor position and re-open the file at that point the next time it is open";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = lib.mkIf (cfg.undofile || cfg.rememberCursorPosition) {
      "vim/vimrc".text = lib.optionalString cfg.undofile /* vim */ ''
        set undofile                  " save undo file after quit
        set undodir=$HOME/.vim/undo   " undo files location
        set undolevels=1000           " number of steps to save
        set undoreload=10000          " number of lines to save

        set viminfo+=n~/.vim/viminfo  " move viminfo for better file completion
        set viminfo^=<1000            " keep more entries

      '' + lib.optionalString cfg.rememberCursorPosition /* vim */ ''
        " remember cursor position
        augroup JumpBack
          au!
          au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
        augroup END

      '';
    };
  };
}
