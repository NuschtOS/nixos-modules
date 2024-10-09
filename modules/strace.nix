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
      (pkgs.strace.overrideAttrs ({ patches ? [ ], ... }: {
        patches = patches ++ [
          (let
            version = "6.3";
          in pkgs.fetchpatch {
            url = "https://github.com/xfgusta/strace-with-colors/raw/v${version}-1/strace-with-colors.patch";
            name = "strace-with-colors-${version}.patch";
            hash = "sha256-gcQldGsRgvGnrDX0zqcLTpEpchNEbCUFdKyii0wetEI=";
          })
        ];
      }))
    ];
  };
}
