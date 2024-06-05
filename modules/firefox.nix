{ config, lib, libS, ... }:

let
  cfg = config.programs.firefox;
in
{
  options.programs.firefox = {
    hardwareAcceleration = libS.mkOpinionatedOption "Firefox hardware acceleration";
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
