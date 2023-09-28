{ config, lib, pkgs, ... }:

{
  options.hardware = {
    intelGPU = lib.mkEnableOption "" // { description = "Whether to add drivers for intel hardware acceleration."; };
  };

  config = {
    hardware.opengl = {
     extraPackages = with pkgs; lib.mkIf config.hardware.intelGPU [
        intel-compute-runtime # OpenCL library for iGPU
        # video encoding/decoding hardware acceleration
        intel-media-driver # broadwell or newer
        intel-vaapi-driver # older hardware like haswell
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; lib.mkIf config.hardware.intelGPU [
        # video encoding/decoding hardware acceleration
        intel-media-driver # broadwell or newer
        intel-vaapi-driver # older hardware like haswell
      ];
    };
  };
}
