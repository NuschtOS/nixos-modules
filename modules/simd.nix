{ config, lib, libS, ... }:

let
  cfg = config.simd;
in
{
  options.simd = {
    enable = lib.mkEnableOption "optimized builds with simd instructions. This is an experimental option meant to be used for testing, as it invlidated the entire cache";
    arch = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = ''
        Microarchitecture string for nixpkgs.hostPlatform.gcc.march and to generate system-features.
        Can be determined with: ``nix shell nixpkgs#gcc -c gcc -march=native -Q --help=target | grep march``
      '';
    };
  };

  config = {
    nix.settings.system-features = lib.mkIf (cfg.arch != null) (libS.nix.gcc-system-features cfg.arch);

    nixpkgs.hostPlatform = lib.mkIf cfg.enable {
      gcc.arch = cfg.arch;
      inherit (config.nixpkgs) system;
    };
  };
}
