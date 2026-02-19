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

  # see https://github.com/elFarto/nvidia-vaapi-driver#firefox
  config = lib.mkIf cfg.hardwareAcceleration {
    environment = {
      etc."libva.conf".text = ''
        LIBVA_MESSAGING_LEVEL=1
      '';

      sessionVariables.MOZ_DISABLE_RDD_SANDBOX = 1;
    };

    programs.firefox.preferences = {
      "gfx.x11-egl.force-enabled" = true;
      "media.ffmpeg.vaapi.enabled" = true;
      "media.hardware-video-decoding.force-enabled" = true;
      "media.rdd-ffmpeg.enabled" = true;
    };
  };
}
