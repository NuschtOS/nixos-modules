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
          (let
            patchVersion = if lib.versionAtLeast version "6.16" then "6.16" else "6.3";
          in pkgs.fetchpatch {
            url = "https://github.com/xfgusta/strace-with-colors/raw/v${patchVersion}-1/strace-with-colors.patch";
            name = "strace-with-colors-${version}.patch";
            hash = {
              "6.16" = "sha256-Uw4lOKuEwT6kTwLZYuTqlq64wBHDt5kL5JwV7hdiBNg=";
              "6.3" = "sha256-gcQldGsRgvGnrDX0zqcLTpEpchNEbCUFdKyii0wetEI=";
            }.${patchVersion} or (throw "nixos-modules.strace: does not know a patch for strace version ${version}");
          })
        ];
      }))
    ];
  };
}
