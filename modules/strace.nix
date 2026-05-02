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
        # TODO: drop module with 26.05
        patches = patches ++ lib.optionals (lib.versionOlder version "7.0") [
          (let
            patchVersion = "6.16";
          in pkgs.fetchpatch {
            url = "https://github.com/xfgusta/strace-with-colors/raw/v${patchVersion}-1/strace-with-colors.patch";
            name = "strace-with-colors-${patchVersion}.patch";
            hash = "sha256-Uw4lOKuEwT6kTwLZYuTqlq64wBHDt5kL5JwV7hdiBNg=";
          })
        ];
      }))
    ];
  };
}
