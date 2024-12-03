{ config, lib, ... }:

let
  cfg = config.programs.firefox;
in
{
  options.programs.firefox = {
    hardwareAcceleration = lib.mkEnableOption "Firefox hardware acceleration" // {
      default = lib.hasAttr "driver" (config.hardware.intelgpu or { });
    };
  };

  config = lib.mkIf cfg.hardwareAcceleration {
    environment = {
      # source https://github.com/elFarto/nvidia-vaapi-driver#firefox
      etc."libva.conf".text = ''
        LIBVA_MESSAGING_LEVEL=1
      '';

      # source https://github.com/elFarto/nvidia-vaapi-driver#firefox
      sessionVariables.MOZ_DISABLE_RDD_SANDBOX = 1;
    };

    programs.firefox.preferences = {
      # source https://github.com/elFarto/nvidia-vaapi-driver#firefox
      "media.ffmpeg.vaapi.enabled" = true;
      "media.rdd-ffmpeg.enabled" = true;
      "gfx.x11-egl.force-enabled" = true;
    };
  };
}
