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
      LIBVA_DRIVER_NAME = "nvidia";
    };

    hardware = {
      graphics.enable = true;
      nvidia = {
        modesetting.enable = true;
        nvidiaSettings = true;
      };
    };

    programs.firefox.hardwareAcceleration = true;

    services.xserver.videoDrivers = [ "nvidia" ];
  };
}
