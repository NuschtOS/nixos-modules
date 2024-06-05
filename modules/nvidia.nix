{ config, lib, ... }:

let
  cfg = config.hardware;
in
{
  options.hardware = {
    nvidiaGPU = lib.mkEnableOption "" // { description = "Whether to add and configure drivers for NVidia hardware acceleration."; };
  };

  config = lib.mkIf cfg.nvidiaGPU {
    environment.sessionVariables = {
      # source https://github.com/elFarto/nvidia-vaapi-driver#firefox
      LIBVA_DRIVER_NAME = "nvidia";
      __EGL_VENDOR_LIBRARY_FILENAMES = "nvidia";

      # source https://discourse.nixos.org/t/nvk-error-when-using-prop-nvidia-drivers/43300/4
      VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
    };

    hardware.nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
    };

    programs.firefox.hardwareAcceleration = true;

    services.xserver.videoDrivers = [ "nvidia" ];
  };
}
