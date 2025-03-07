{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.nextcloud;
in
{
  options = {
    services.nextcloud = {
      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";

      configureImaginary = libS.mkOpinionatedOption "configure and use Imaginary for preview generation";

      configureMemories = lib.mkEnableOption "" // { description = "Whether to configure dependencies for Memories App."; };

      configureMemoriesVaapi = lib.mkOption {
        type = lib.types.bool;
        default = lib.hasAttr "driver" (config.hardware.intelgpu or { });
        defaultText = lib.literalExpression ''lib.hasAttr "driver" config.hardware.intelgpu'';
        description = "Whether to configure Memories App to use an Intel iGPU for hardware acceleration.";
      };

      configurePreviewSettings = lib.mkOption {
        type = lib.types.bool;
        default = cfg.configureImaginary;
        defaultText = lib.literalExpression "config.services.nextcloud.configureImaginary";
        description = ''
          Whether to configure the preview settings to be more optimised for real world usage.
          By default this is enabled, when Imaginary is configured.
        '';
      };
    };
  };

  imports = [
    (lib.mkRemovedOptionModule ["services" "nextcloud" "configureRecognize"] ''
      configureRecognize has been removed in favor of using the recognize packages from NixOS like:

      services.nextcloud.extraApps = {
        inherit (pkgs."nextcloud${lib.versions.major config.services.nextcloud.package.version}Packages".apps) recognize;
      };
    '')
  ];

  config = lib.mkIf cfg.enable {
    services = {
      imaginary = lib.mkIf cfg.configureImaginary {
        enable = true;
        address = "127.0.0.1";
        settings.return-size = true;
      };

      nextcloud = {
        extraApps = let
          inherit (pkgs."nextcloud${lib.versions.major cfg.package.version}Packages") apps;
        in lib.mkMerge [
          (lib.mkIf cfg.configureMemories {
            inherit (apps) memories;
          })
          (lib.mkIf cfg.configurePreviewSettings {
            inherit (apps) previewgenerator;
          })
        ];

        phpOptions = lib.mkIf cfg.recommendedDefaults {
          # https://docs.nextcloud.com/server/latest/admin_manual/installation/server_tuning.html#:~:text=opcache.jit%20%3D%201255%20opcache.jit_buffer_size%20%3D%20128m
          "opcache.jit" = 1255;
          "opcache.jit_buffer_size" = "128M";
        };

        settings = lib.mkMerge [
          (lib.mkIf cfg.recommendedDefaults {
            # otherwise the Logging App does not function
            log_type = "file";
          })

          (lib.mkIf cfg.configureImaginary {
            enabledPreviewProviders = [
              # default from https://github.com/nextcloud/server/blob/master/config/config.sample.php#L1295-L1304
              ''OC\Preview\BMP''
              ''OC\Preview\GIF''
              ''OC\Preview\JPEG''
              ''OC\Preview\Krita''
              ''OC\Preview\MarkDown''
              ''OC\Preview\MP3''
              ''OC\Preview\OpenDocument''
              ''OC\Preview\PNG''
              ''OC\Preview\TXT''
              ''OC\Preview\XBitmap''
              # https://docs.nextcloud.com/server/24/admin_manual/installation/server_tuning.html#previews
              ''OC\Preview\Imaginary''
            ];

            preview_imaginary_url = "http://127.0.0.1:${toString config.services.imaginary.port}/";
          })

          (lib.mkIf cfg.configureMemories {
            enabledPreviewProviders = [
              # https://memories.gallery/file-types/
              ''OC\Preview\Image'' # alias for png,jpeg,gif,bmp
              ''OC\Preview\HEIC''
              ''OC\Preview\TIFF''
              ''OC\Preview\Movie''
            ];

            "memories.exiftool" = lib.getExe pkgs.exiftool;
            "memories.vod.vaapi" = lib.mkIf cfg.configureMemoriesVaapi true;
            "memories.vod.ffmpeg" = lib.getExe pkgs.ffmpeg-headless;
            "memories.vod.ffprobe" = lib.getExe' pkgs.ffmpeg-headless "ffprobe";
          })

          (lib.mkIf cfg.configurePreviewSettings {
            enabledPreviewProviders = [
              # https://github.com/nextcloud/server/tree/master/lib/private/Preview
              ''OC\Preview\Font''
              ''OC\Preview\PDF''
              ''OC\Preview\SVG''
              ''OC\Preview\WebP''
            ];

            enable_previews = true;
            jpeg_quality = 60;
            preview_max_filesize_image = 128; # MB
            preview_max_memory = 512; # MB
            preview_max_x = 2048; # px
            preview_max_y = 2048; # px
          })
        ];
      };

      phpfpm.pools = lib.mkIf cfg.configurePreviewSettings {
        # add user packages to phpfpm process PATHs, required to find ffmpeg for preview generator
        # beginning taken from https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/web-apps/nextcloud.nix#L985
        nextcloud.phpEnv.PATH = lib.mkForce "/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/usr/bin:/bin:/etc/profiles/per-user/nextcloud/bin";
      };
    };

    systemd = {
      services = let
        occ = "/run/current-system/sw/bin/nextcloud-occ";
      in {
        nextcloud-cron = lib.mkIf cfg.configureMemories {
          # required for memories
          # see https://github.com/pulsejet/memories/blob/master/docs/troubleshooting.md#issues-with-nixos
          path = with pkgs; [ perl ];
          # fix memories app being unpacked without the x-bit on binaries
          # could be done in nextcloud-update-plugins but then manually updates would be broken until the next auto update
          preStart = "${lib.getExe' pkgs.coreutils "chmod"} +x ${cfg.home}/store-apps/memories/bin-ext/*";
        };

        nextcloud-cron-preview-generator = lib.mkIf cfg.configurePreviewSettings {
          environment.NEXTCLOUD_CONFIG_DIR = "${cfg.datadir}/config";
          serviceConfig = {
            ExecStart = "${occ} preview:pre-generate";
            Type = "oneshot";
            User = "nextcloud";
          };
        };

        nextcloud-preview-generator-setup = lib.mkIf cfg.configurePreviewSettings {
          wantedBy = [ "multi-user.target" ];
          requires = [ "phpfpm-nextcloud.service" ];
          after = [ "phpfpm-nextcloud.service" ];
          environment.NEXTCLOUD_CONFIG_DIR = "${cfg.datadir}/config";
          script = /* bash */ ''
            # check with:
            # for size in squareSizes widthSizes heightSizes; do echo -n "$size: "; nextcloud-occ config:app:get previewgenerator $size; done

            # extra commands run for preview generator:
            # 32   icon file list
            # 64   icon file list android app, photos app
            # 96   nextcloud client VFS windows file preview
            # 256  file app grid view, many requests
            # 512  photos app tags
            ${occ} config:app:set --value="32 64 96 256 512" previewgenerator squareSizes

            # 341 hover in maps app
            # 1920 files/photos app when viewing picture
            ${occ} config:app:set --value="341 1920" previewgenerator widthSizes

            # 256 hover in maps app
            # 1080 files/photos app when viewing picture
            ${occ} config:app:set --value="256 1080" previewgenerator heightSizes
          '';
          serviceConfig = {
            Type = "oneshot";
            User = "nextcloud";
          };
        };

        phpfpm-nextcloud.serviceConfig = lib.mkIf (cfg.configureMemories && cfg.configureMemoriesVaapi) {
          DeviceAllow = [ "/dev/dri/renderD128 rwm" ];
          PrivateDevices = lib.mkForce false;
        };
      };

      timers.nextcloud-cron-preview-generator = lib.mkIf cfg.configurePreviewSettings {
        after = [ "nextcloud-setup.service" ];
        timerConfig = {
          OnCalendar = "*:0/10";
          OnUnitActiveSec = "9m";
          Persistent = true;
          RandomizedDelaySec = 60;
          Unit = "nextcloud-cron-preview-generator.service";
        };
        wantedBy = [ "timers.target" ];
      };
    };

    users.users.nextcloud = {
      extraGroups = lib.mkIf (cfg.configureMemories && cfg.configureMemoriesVaapi) [
        "render" # access /dev/dri/renderD128
      ];
      packages = with pkgs;
        # generate video thumbnails with preview generator
        lib.optional cfg.configurePreviewSettings ffmpeg-headless
        # required for memories, duplicated with nextcloud-cron to better debug
        ++ lib.optional cfg.configureMemories perl;
    };
  };
}
