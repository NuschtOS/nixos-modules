{ config, lib, ... }:

let
  cfg = config.services.minio;
in
{
  options = {
    services.minio = {
      configureNginx = lib.mkEnableOption "" // { description = "Whether to configure Nginx to serve Minio."; };

      consoleDomain = lib.mkOption {
        type = lib.types.str;
        default = null;
        description = "Domain under which the minio console will be reachable.";
      };

      maxUploadSize = lib.mkOption {
        type = lib.types.str;
        default = "100M";
        description = ''
          Configure Nginx' global client_max_body_size to this size.
          This allows single files up to this size to be uploaded to Minio. Existing files and downloads are not influeneced.
          NixOS' defaults to 10M which was deemed unuitable as a default for Minio.
        '';
      };

      s3Domain = lib.mkOption {
        type = lib.types.str;
        default = null;
        description = "Domain under which the S3 API will be reachable.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services = {
      minio = {
        consoleAddress = lib.mkIf cfg.configureNginx "127.0.0.1:9001";
        listenAddress = lib.mkIf cfg.configureNginx "127.0.0.1:9000";
      };

      nginx = lib.mkIf cfg.configureNginx {
        enable = true;
        clientMaxBodySize = cfg.maxUploadSize;
        virtualHosts = let
          serverConfig = /* nginx */ ''
            # Allow special characters in headers
            ignore_invalid_headers off;
          '';
          locationConfig = /* nginx */ ''
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_connect_timeout 300;
            chunked_transfer_encoding off;
          '';
        in {
          # https://min.io/docs/minio/linux/integrations/setup-nginx-proxy-with-minio.html
          "${cfg.consoleDomain}" = {
            forceSSL = true;
            extraConfig = serverConfig;
            locations."/" = {
              proxyPass = "http://${config.services.minio.consoleAddress}";
              proxyWebsockets = true;
              extraConfig = locationConfig + /* nginx */ ''
                proxy_set_header X-NginX-Proxy true;
              '';
            };
          };
          "${cfg.s3Domain}" = {
            forceSSL = true;
            extraConfig = serverConfig;
            locations."/" = {
              proxyPass = "http://${config.services.minio.listenAddress}";
              extraConfig = locationConfig;
            };
          };
        };
      };
    };

    systemd.services.minio.environment = lib.mkIf cfg.configureNginx {
      MINIO_BROWSER_REDIRECT_URL = "https://${cfg.consoleDomain}/";
    };
  };
}
