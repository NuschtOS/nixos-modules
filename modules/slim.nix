{ config, lib, libS, options, pkgs, ... }:

let
  cfg = config.slim;
in
{
  options.slim = {
    enable = libS.mkOpinionatedOption "disable some normally rarely used things to slim down the system";
  };

  config = lib.mkIf cfg.enable ({
    documentation = {
      # html docs and info are not required, man pages are enough
      doc.enable = false;
      info.enable = false;
    };

    environment.defaultPackages = lib.mkForce [ ];

    nixpkgs.overlays = lib.mkIf (!config.programs.thunderbird.enable or true) [
      (_final: prev: {
        thunderbird = prev.thunderbird.override { cfg.speechSynthesisSupport = false; };
      })
    ];

  } // lib.optionalAttrs (lib.versionAtLeast lib.version "24.11") {
    programs.thunderbird.package = pkgs.thunderbird.override { cfg.speechSynthesisSupport = false; };
  } // {

    # during testing only 550K-650K of the tmpfs where used
    security.wrapperDirSize = "10M";

    services = lib.optionalAttrs (options.services?orca) {
      orca.enable = false; # requires speechd
    } // lib.optionalAttrs (options.services?speechd) {
      speechd.enable = false; # voice files are big and fat
    };
  });
}
