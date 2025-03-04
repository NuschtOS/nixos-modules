{ config, lib, libS, pkgs, ... }:

let
  cfg = config.slim;
in
{
  options.slim = {
    enable = libS.mkOpinionatedOption "disable some normally rarely used things to slim down the system";
  };

  config = lib.mkIf cfg.enable {
    documentation = {
      # html docs and info are not required, man pages are enough
      doc.enable = false;
      info.enable = false;
    };

    environment.defaultPackages = lib.mkForce [ ];

    programs.thunderbird.package = pkgs.thunderbird.override { cfg.speechSynthesisSupport = false; };

    # during testing only 550K-650K of the tmpfs where used
    security.wrapperDirSize = "10M";

    services = {
      orca.enable = false; # requires speechd
      speechd.enable = false; # voice files are big and fat
    };
  };
}
