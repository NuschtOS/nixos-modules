{ config, lib, pkgs, ... }:

let
  cfg = config.programs.strace;
in
{
  options = {
    programs.strace = {
      withColors = lib.mkEnableOption "strace with colors patch";
    };
  };

  config = lib.mkIf cfg.withColors {
    environment.systemPackages = [
      (pkgs.strace.overrideAttrs ({ patches ? [ ], version, ... }: {
        patches = patches ++ [
          (pkgs.fetchpatch {
            url = "https://github.com/xfgusta/strace-with-colors/raw/v${version}-1/strace-with-colors.patch";
            name = "strace-with-colors-${version}.patch";
            hash = {
              "6.16" = "sha256-Uw4lOKuEwT6kTwLZYuTqlq64wBHDt5kL5JwV7hdiBNg=";
              "6.3" = "sha256-gcQldGsRgvGnrDX0zqcLTpEpchNEbCUFdKyii0wetEI=";
            }.${version} or (throw "nixos-modules.strace: does not know a patch for strace version ${version}");
          })
        ];
      }))
    ];
  };
}
