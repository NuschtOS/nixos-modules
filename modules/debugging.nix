{ config, lib, pkgs, ... }:

let
  cfg = config.debugging;
in
{
  options = {
    debugging.enable = lib.mkEnableOption "debugging tools";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = import ../lib/debug-pkgs.nix pkgs;
  };
}
