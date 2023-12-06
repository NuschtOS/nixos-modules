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
    assertions = [
      {
        assertion = cfg.quic.enable && cfg.quic.bpf -> !lib.versionOlder cfg.package.version "1.25.0";
        message = "Setting services.nginx.quic.bpf to true requires nginx version 1.25.0 or newer, but currently \"${cfg.package.version}\" is used!";
      }
    ];

    boot.kernel.sysctl = lib.mkIf cfg.tcpFastOpen {
      # enable tcp fastopen for outgoing and incoming connections
      "net.ipv4.tcp_fastopen" = 3;
    };

    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 80 443 ];

    nixpkgs.overlays = lib.mkIf cfg.tcpFastOpen [
      (final: prev:
        let
          configureFlags = [ "-DTCP_FASTOPEN=23" ];
        in
        {
          nginx = prev.nginx.override { inherit configureFlags; };
          nginxQuic = prev.nginxQuic.override { inherit configureFlags; };
          nginxStable = prev.nginxStable.override { inherit configureFlags; };
          nginxMainline = prev.nginxMainline.override { inherit configureFlags; };
        })
    ];

    services = {
      logrotate.settings.nginx = lib.mkIf cfg.rotateLogsFaster {
        frequency = "daily";
        rotate = 7;
      };

      # NOTE: do not use mkMerge here to prevent infinite recursions
      nginx = {
        appendConfig = lib.optionalString (cfg.quic.enable && cfg.quic.bpf) /* nginx */ ''
          quic_bpf on;
        '' + lib.optionalString cfg.recommendedDefaults /* nginx */ ''
          worker_processes auto;
          worker_cpu_affinity auto;
        '';

        commonHttpConfig = lib.optionalString cfg.recommendedDefaults /* nginx */ ''
          error_log syslog:server=unix:/dev/log;
        '' + lib.optionalString cfg.quic.enable /* nginx */''
          quic_retry on;
        '' + lib.optionalString cfg.recommendedZstdSettings /* nginx */ ''
          # TODO: upstream this?
          zstd_types application/x-nix-archive;
        '';

        commonServerConfig = lib.mkIf cfg.setHSTSHeader /* nginx */ ''
          more_set_headers "Strict-Transport-Security: max-age=63072000; includeSubDomains; preload";
        '';

        package = lib.mkIf cfg.quic.enable pkgs.nginxQuic; # based on pkgs.nginxMainline

        recommendedBrotliSettings = lib.mkIf cfg.allCompression true;
        recommendedGzipSettings = lib.mkIf cfg.allCompression true;
        recommendedOptimisation = lib.mkIf cfg.allCompression true;
        recommendedProxySettings = lib.mkIf cfg.allCompression true;
        recommendedTlsSettings = lib.mkIf cfg.allCompression true;
        recommendedZstdSettings = lib.mkIf cfg.allCompression true;

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

        # NOTE: do not use mkMerge here to prevent infinite recursions
        virtualHosts =
          let
            extraParameters = [
              # net.core.somaxconn is set to 4096
              # see https://www.nginx.com/blog/tuning-nginx/#:~:text=to%20a%20value-,greater%20than%20512,-%2C%20change%20the%20backlog
              "backlog=1024"

              "deferred"
              "fastopen=256" # requires nginx to be compiled with -DTCP_FASTOPEN=23
            ];
          in
          lib.mkIf (cfg.recommendedDefaults || cfg.default404Server.enable || cfg.quic.enable) {
            "_" = {
              kTLS = lib.mkIf cfg.recommendedDefaults true;
              reuseport = lib.mkIf (cfg.recommendedDefaults || cfg.quic.enable) true;

              default = lib.mkIf cfg.default404Server.enable true;
              forceSSL = lib.mkIf cfg.default404Server.enable true;
              useACMEHost = lib.mkIf cfg.default404Server.enable cfg.default404Server.acmeHost;
              extraConfig = lib.mkIf cfg.default404Server.enable /* nginx */ ''
                return 404;
              '';

              listen = lib.mkIf cfg.tcpFastOpen (lib.mkDefault [
                { addr = "0.0.0.0"; port = 80; inherit extraParameters; }
                { addr = "0.0.0.0"; port = 443; ssl = true; inherit extraParameters; }
                { addr = "[::]"; port = 80; inherit extraParameters; }
                { addr = "[::]"; port = 443; ssl = true; inherit extraParameters; }
              ]);

              quic = lib.mkIf cfg.quic.enable true;
            };
          };
      };
    };

    security.dhparams = lib.mkIf cfg.generateDhparams {
      enable = cfg.generateDhparams;
      params.nginx = { };
    };

    systemd.services.nginx.serviceConfig = lib.mkIf (cfg.quic.enable && cfg.quic.bpf) {
      # NOTE: CAP_BPF is included in CAP_SYS_ADMIN but it is not enough alone
      AmbientCapabilities = [ "CAP_BPF" "CAP_NET_ADMIN" "CAP_SYS_ADMIN" ];
      CapabilityBoundingSet = [ "CAP_BPF" "CAP_NET_ADMIN" "CAP_SYS_ADMIN" ];
      SystemCallFilter = [ "bpf" ];
    };
  };
}
