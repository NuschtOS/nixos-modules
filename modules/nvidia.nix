{ config, lib, pkgs, ... }:

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
      __EGL_VENDOR_LIBRARY_FILENAMES = "/run/opengl-driver/share/glvnd/egl_vendor.d/10_nvidia.json";

      # source https://discourse.nixos.org/t/nvk-error-when-using-prop-nvidia-drivers/43300/4
      VK_DRIVER_FILES = "/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json";
    };

    hardware.nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
    };

    programs.firefox.hardwareAcceleration = true;

    services.xserver.videoDrivers = [ "nvidia" ];

    system.checks = let
      openglDriver = config.systemd.tmpfiles.settings.opengl."/run/opengl-driver"."L+".argument;
    in [
      (pkgs.runCommand "check-that-nvidia-driver-json-files-exist" {} /* bash */ ''
        set -eoux pipefail

        # the cut drops /run/opengl-driver/
        [[ -e ${openglDriver}/$(echo ${config.environment.sessionVariables.__EGL_VENDOR_LIBRARY_FILENAMES} | cut -d'/' -f4-) ]]
        [[ -e ${openglDriver}/$(echo ${config.environment.sessionVariables.VK_DRIVER_FILES} | cut -d'/' -f4-) ]]
        touch $out
      '')
    ];
  };
}
