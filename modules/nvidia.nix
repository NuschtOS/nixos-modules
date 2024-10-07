{ config, lib, options, ... }:

let
  cfg = config.hardware;
  # TODO: remove with 24.11
  hardwareOpengl = if options.hardware?graphics then "graphics" else "opengl";
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

    hardware = {
      "${hardwareOpengl}".enable = true;
      nvidia = {
        modesetting.enable = true;
        nvidiaSettings = true;
      };
    };

    programs.firefox.hardwareAcceleration = true;

    services.xserver.videoDrivers = [ "nvidia" ];
  };
}
