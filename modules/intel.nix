{ config, lib, pkgs, ... }:

let
  cfg = config.hardware;
in
{
  options.hardware = {
    intelGPU = lib.mkEnableOption "" // { description = "Whether to add and configure drivers for intel hardware acceleration."; };
  };

  config = lib.mkIf cfg.intelGPU {
    environment.sessionVariables = {
      # source https://github.com/elFarto/nvidia-vaapi-driver#firefox
      LIBVA_DRIVER_NAME = "intel";
      __EGL_VENDOR_LIBRARY_FILENAMES = "intel";

      # source https://discourse.nixos.org/t/nvk-error-when-using-prop-nvidia-drivers/43300/4
      VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/intel_icd.x86_64.json";
    };

    hardware.opengl = {
      extraPackages = with pkgs; [
        intel-compute-runtime # OpenCL library for iGPU
        # video encoding/decoding hardware acceleration
        intel-media-driver # broadwell or newer
        intel-vaapi-driver # older hardware like haswell
      ];
      extraPackages32 = with pkgs.pkgsi686Linux; [
        # video encoding/decoding hardware acceleration
        intel-media-driver # broadwell or newer
        intel-vaapi-driver # older hardware like haswell
      ];
    };

    programs.firefox.hardwareAcceleration = true;
  };
}
