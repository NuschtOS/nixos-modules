{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.nginx;
in
{
  options.services.nginx = {
    allCompression = libS.mkOpinionatedOption "set all recommended compression options";

    default404Server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = lib.mdDoc ''
          Wether to add a default server which always responds with 404.
          This is useful when using a wildcard cname with a wildcard certitificate to not return the first server entry in the config on unknown subdomains
          or to do the same for an old and not fully removed domain.
        '';
      };

      acmeHost = lib.mkOption {
        type = lib.types.str;
        description = lib.mdDoc ''
          The acme host to use for the default 404 server.
        '';
      };
    };

    generateDhparams = libS.mkOpinionatedOption "generate more secure, 2048 bits dhparams replacing the default 1024 bits";

    openFirewall = libS.mkOpinionatedOption "open the firewall port for the http (80) and https (443) default ports";

    quic = {
      enable = lib.mkEnableOption (lib.mdDoc "quic support in nginx");

      bpf = libS.mkOpinionatedOption "configure nginx' bpf support which routes quic packets from the same source to the same worker";
    };

    recommendedDefaults = libS.mkOpinionatedOption "set recommended performance options not grouped into other settings";

    resolverAddrFromNameserver = libS.mkOpinionatedOption "set resolver address to environment.nameservers";

    rotateLogsFaster = libS.mkOpinionatedOption "keep logs only for 7 days and rotate them daily";

    setHSTSHeader = libS.mkOpinionatedOption "add the HSTS header to all virtual hosts";

    tcpFastOpen = libS.mkOpinionatedOption "enable tcp fast open";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 80 443 ];

    services = {
      logrotate.settings.nginx = lib.mkIf cfg.rotateLogsFaster {
        frequency = "daily";
        rotate = 7;
      };

      nginx = lib.mkMerge [
        {
          appendConfig = lib.mkIf cfg.recommendedDefaults /* nginx */ ''
            worker_processes auto;
            worker_cpu_affinity auto;
          '';

          commonHttpConfig = lib.mkIf cfg.recommendedDefaults /* nginx */ ''
            error_log syslog:server=unix:/dev/log;
          '' + lib.mkIf cfg.recommendedZstdSettings /* nginx */ ''
            # TODO: upstream this?
            zstd_types application/x-nix-archive;
          '';

          commonServerConfig = lib.mkIf cfg.setHSTSHeader /* nginx */ ''
            more_set_headers "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload";
          '';

          resolver.addresses =
            let
              isIPv6 = addr: builtins.match ".*:.*:.*" addr != null;
              escapeIPv6 = addr:
                if isIPv6 addr then
                  "[${addr}]"
                else
                  addr;
            in
            lib.optionals (cfg.resolverAddrFromNameserver && config.networking.nameservers != [ ]) (map escapeIPv6 config.networking.nameservers);
          sslDhparam = lib.mkIf cfg.generateDhparams config.security.dhparams.params.nginx.path;

          virtualHosts = lib.mkMerge [
            (lib.mkIf cfg.default404Server.enable {
              "_" = {
                default = true;
                forceSSL = lib.mkDefault true;
                useACMEHost = cfg.default404Server.acmeHost;
                extraConfig = /* nginx */ ''
                  return 404;
                '';
              };
            })

            (lib.mkIf cfg.recommendedDefaults {
              "_" = {
                kTLS = true;
                reuseport = true;
              };
            })

            (lib.mkIf cfg.tcpFastOpen (let
              extraParameters = [
                # net.core.somaxconn is set to 4096
                # see https://www.nginx.com/blog/tuning-nginx/#:~:text=to%20a%20value-,greater%20than%20512,-%2C%20change%20the%20backlog
                "backlog=1024"

                "deferred"
                "fastopen=256" # requires nginx to be compiled with -DTCP_FASTOPEN=23
              ];
            in {
              "_".listen = lib.mkDefault [
                { addr = "[::]"; port = 80; inherit extraParameters; }
                { addr = "[::]"; port = 443; ssl = true; inherit extraParameters; }
              ];
            }))
          ];
        }

        (lib.mkIf cfg.quic.enable {
          appendConfig = lib.mkIf cfg.quic.bpf /* nginx */ ''
            quic_bpf on;
          '';

          commonHttpConfig = lib.mkf cfg.quic.enable /* nginx */''
            quic_retry on;
          '';

          package = pkgs.nginxQuic; # based on pkgs.nginxMainline

          virtualHosts."_" = {
            quic = true;
            reuseport = true;
          };
        })

        (lib.mkIf cfg.allCompression (libS.modules.mkRecursiveDefault {
          recommendedBrotliSettings = true;
          recommendedGzipSettings = true;
          recommendedOptimisation = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;
          recommendedZstdSettings = true;
        }))
      ];
    };

    security.dhparams = lib.mkIf cfg.generateDhparams {
      enable = cfg.generateDhparams;
      params.nginx = { };
    };

    systemd.services.nginx.serviceConfig = lib.mkIf cfg.quic.bpf {
      # NOTE: CAP_BPF is included in CAP_SYS_ADMIN but it is not enough alone
      AmbientCapabilities = [ "CAP_BPF" "CAP_NET_ADMIN" "CAP_SYS_ADMIN" ];
      CapabilityBoundingSet = [ "CAP_BPF" "CAP_NET_ADMIN" "CAP_SYS_ADMIN" ];
      SystemCallFilter = [ "bpf" ];
    };
  };
}
