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
    };

    hardware.nvidia = {
      modesetting.enable = true;
      nvidiaSettings = true;
    };

    programs.firefox.hardwareAcceleration = true;

    services.xserver.videoDrivers = [ "nvidia" ];
  };
}
