{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.nextcloud;
  inherit (config.services.nextcloud.package.packages) apps;

  hasImaginary = lib.versionAtLeast lib.version "25.11pre";
in
{
  options = {
    services.nextcloud = {
      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";

      # TODO: drop when removing 25.05 support
      imaginary.enable = if (!hasImaginary) then
        lib.mkEnableOption "Imaginary" // {
          default = config.opinionatedDefaults;
        }
      else
        lib.mkOption {  };

      configureMemories = lib.mkEnableOption "" // { description = "Whether to configure dependencies for Memories App."; };

      configureMemoriesVaapi = lib.mkOption {
        type = lib.types.bool;
        default = lib.hasAttr "driver" (config.hardware.intelgpu or { });
        defaultText = lib.literalExpression ''lib.hasAttr "driver" config.hardware.intelgpu'';
        description = "Whether to configure Memories App to use an Intel iGPU for hardware acceleration.";
      };

      configurePreviewSettings = lib.mkOption {
        type = lib.types.bool;
        default = cfg.imaginary.enable;
        defaultText = lib.literalExpression "config.services.nextcloud.imaginary.enable";
        description = ''
          Whether to configure the preview settings to be more optimised for real world usage.
          By default this is enabled, when Imaginary is configured.
        '';
      };
    };
  };

  imports = [
    (lib.mkRenamedOptionModule ["services" "nextcloud" "configureImaginary"] ["services" "nextcloud" "imaginary" "enable"])
    (lib.mkRemovedOptionModule ["services" "nextcloud" "configureRecognize"] ''
      configureRecognize has been removed in favor of using the recognize packages from NixOS like:

      services.nextcloud.extraApps = {
        inherit (config.services.nextcloud.package.packages.apps) recognize;
      };
    '')
  ];

  config = lib.mkIf cfg.enable {
    services = {
      imaginary = lib.mkIf cfg.imaginary.enable {
        enable = true;
        settings.return-size = true;
      };

      nextcloud = {
        extraApps = lib.mkMerge [
          (lib.mkIf cfg.configureMemories {
            inherit (apps) memories;
          })
          (lib.mkIf cfg.configurePreviewSettings {
            inherit (apps) previewgenerator;
          })
        ];

        imaginary.enable = config.opinionatedDefaults;

        phpOptions = lib.mkIf cfg.recommendedDefaults {
          # recommended by nextcloud admin overview after some usage, default 8
          "opcache.interned_strings_buffer" = 16;
          # https://docs.nextcloud.com/server/latest/admin_manual/installation/server_tuning.html#:~:text=opcache.jit%20%3D%201255%20opcache.jit_buffer_size%20%3D%20128m
          "opcache.jit" = 1255;
          "opcache.jit_buffer_size" = "128M";
          # https://docs.nextcloud.com/server/32/admin_manual/installation/server_tuning.html#enable-php-opcache
          "opcache.revalidate_freq" = 60; # default 1
        };

        settings = lib.mkMerge [
          (lib.mkIf cfg.recommendedDefaults {
            # otherwise the Logging App does not function
            log_type = "file";
          })

          (lib.mkIf cfg.imaginary.enable {
            enabledPreviewProviders = [
              # default from https://github.com/nextcloud/server/blob/master/config/config.sample.php#L1494-L1505
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
              # https://docs.nextcloud.com/server/latest/admin_manual/installation/server_tuning.html#previews
              ''OC\Preview\Imaginary''
            ];

            preview_imaginary_url = "http://${config.services.imaginary.address}:${toString config.services.imaginary.port}";
          })

          (lib.mkIf (cfg.configurePreviewSettings || cfg.configureMemories) {
            enabledPreviewProviders = [
              # https://memories.gallery/file-types/
              ''OC\Preview\Image'' # alias for png,jpeg,gif,bmp
              ''OC\Preview\HEIC''
              ''OC\Preview\TIFF''
              ''OC\Preview\Movie''
            ];
          })

          (lib.mkIf cfg.configureMemories {
            "memories.exiftool_no_local" = false;
            "memories.exiftool" = "${apps.memories}/bin-ext/exiftool/exiftool";
            "memories.vod.ffmpeg" = "${apps.memories}/bin-ext/ffmpeg";
            "memories.vod.ffprobe" = "${apps.memories}/bin-ext/ffprobe";
            "memories.vod.path" = "${apps.memories}/bin-ext/go-vod";
            "memories.vod.vaapi" = lib.mkIf cfg.configureMemoriesVaapi true;
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
        inherit (config.systemd.services.nextcloud-setup.serviceConfig) LoadCredential;
      in {
        nextcloud-cron-preview-generator = lib.mkIf cfg.configurePreviewSettings {
          environment.NEXTCLOUD_CONFIG_DIR = "${cfg.datadir}/config";
          serviceConfig = {
            inherit LoadCredential;
            ExecStart = "${occ} preview:pre-generate";
            Type = "oneshot";
            User = "nextcloud";
          };
        };

        nextcloud-preview-generator-setup = lib.mkIf cfg.configurePreviewSettings {
          wantedBy = [ "multi-user.target" ];
          wants = [ "nextcloud-setup.service" ];
          after = [ "nextcloud-setup.service" ];
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
            inherit LoadCredential;
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
      # generate video thumbnails with preview generator
      packages = lib.optional cfg.configurePreviewSettings pkgs.ffmpeg-headless;
    };
  };
}
