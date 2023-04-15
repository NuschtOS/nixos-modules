{ config, lib, pkgs, ... }:

{
  options.hardware = {
    intelGPU = lib.mkEnableOption "" // { description = "Whether to add drivers for intel hardware acceleration."; };
  };

  config = {
    hardware.opengl = {
     extraPackages = with pkgs; lib.mkIf config.hardware.intelGPU [
        intel-compute-runtime # OpenCL library
        intel-media-driver # video encoding/decoding hardware accerlation
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; lib.mkIf config.hardware.intelGPU [
        intel-media-driver # video encoding/decoding hardware accerlation
      ];
    };
  };
}
