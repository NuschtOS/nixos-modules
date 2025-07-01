{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.nginx;
in
{
  options.services.nginx = {
    allRecommendOptions = libS.mkOpinionatedOption "set all upstream options starting with `recommended`";

    commonServerConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Shared configuration snipped added to every virtualHosts' extraConfig.";
    };

    compileWithAWSlc = libS.mkOpinionatedOption "compile nginx with aws-lc as crypto library";

    configureQuic = lib.mkEnableOption "quic support in nginx";

    default404Server = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to add a default server which always responds with 404.
          This is useful when using a wildcard cname with a wildcard certitificate to not return the first server entry in the config on unknown subdomains
          or to do the same for an old and not fully removed domain.
          The addresses to listen on are derived from services.nginx.defaultListenAddresses.
        '';
      };

      acmeHost = lib.mkOption {
        type = lib.types.str;
        description = "The acme host to use for the default 404 server.";
      };
    };

    generateDhparams = libS.mkOpinionatedOption "generate more secure, 2048 bits dhparams replacing the default 1024 bits";

    openFirewall = libS.mkOpinionatedOption "open the firewall port for the http (80/tcp), https (443/tcp) and if enabled quic (443/udp) ports";

    recommendedDefaults = libS.mkOpinionatedOption "set recommended performance options not grouped into other settings";

    resolverAddrFromNameserver = libS.mkOpinionatedOption "set resolver address to environment.nameservers";

    rotateLogsFaster = libS.mkOpinionatedOption "keep logs only for 7 days and rotate them daily";

    hstsHeader = {
      enable = libS.mkOpinionatedOption "add the `Strict-Transport-Security` (HSTS) header to all virtual hosts";

      includeSubDomains = lib.mkEnableOption "" // { description = "Whether to add `includeSubDomains` to the `Strict-Transport-Security` header"; };
    };

    tcpFastOpen = lib.mkEnableOption "" // { description = "Whether to configure tcp fast open. This requires configuring useACMEHost for `_` due to limitatons in the nginx config parser"; };

    # source https://gist.github.com/danbst/f1e81358d5dd0ba9c763a950e91a25d0
    virtualHosts = lib.mkOption {
      type = with lib.types; attrsOf (submodule ({ config, ... }: let
        cfgv = config;
      in {
        options = {
          commonLocationsConfig = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = ''
              Shared configuration snipped added to every locations' extraConfig.

              ::: {.note}
              This option mainly exists because nginx' add_header and headers_more's more_set_headers function do not support inheritance to lower levels.
              :::
            '';
          };

          locations = lib.mkOption {
            type = with lib.types; attrsOf (submodule {
              options.extraConfig = lib.mkOption { };
              config.extraConfig = lib.optionalString cfg.hstsHeader.enable /* nginx */ ''
                more_set_headers "Strict-Transport-Security: max-age=63072000; ${lib.optionalString cfg.hstsHeader.includeSubDomains "includeSubDomains; "}preload";
              '' + cfg.commonServerConfig + cfgv.commonLocationsConfig;
            });
          };
        };

        config.kTLS = lib.mkIf cfg.compileWithAWSlc false;
      }));
    };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "services" "nginx" "allCompression" ] [ "services" "nginx" "allRecommendOptions" ])
    (lib.mkRenamedOptionModule [ "services" "nginx" "quic" "bpf" ] [ "services" "nginx" "enableQuicBPF" ])
    (lib.mkRenamedOptionModule [ "services" "nginx" "quic" "enable" ] [ "services" "nginx" "configureQuic" ])
    (lib.mkRenamedOptionModule [ "services" "nginx" "setHSTSHeader" ] [ "services" "nginx" "hstsHeader" "enable" ])
  ];

  config = lib.mkIf cfg.enable {
    assertions = lib.mkIf cfg.hstsHeader.enable (lib.flatten (lib.attrValues (lib.mapAttrs (host: hostConfig: let
      name = ''services.nginx.virtualHosts."${host}"'';
    in [
      {
        assertion = (lib.length (lib.attrNames hostConfig.locations)) == 0 -> hostConfig.root == null;
        message = "Use ${name}.locations./.root instead of ${name}.root to properly apply .locations.*.extraConfig set by `services.nginx.hstsHeader.enable`.";
      }
      {
        assertion = cfg.compileWithAWSlc -> !hostConfig.kTLS;
        message = "${name} uses kTLS which is incompatible with aws-lc.";
      }
    ]) cfg.virtualHosts)));

    boot.kernel.sysctl = lib.mkIf cfg.tcpFastOpen {
      # enable tcp fastopen for outgoing and incoming connections
      "net.ipv4.tcp_fastopen" = 3;
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 80 443 ];
      allowedUDPPorts = lib.mkIf cfg.configureQuic [ 443 ];
    };

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
        appendConfig = lib.optionalString cfg.recommendedDefaults /* nginx */ ''
          worker_processes auto;
          worker_cpu_affinity auto;
        '';

        commonHttpConfig = lib.optionalString cfg.recommendedDefaults /* nginx */ ''
          error_log syslog:server=unix:/dev/log;
        '' + lib.optionalString cfg.configureQuic /* nginx */''
          quic_retry on;
        '';

        enableQuicBPF = lib.mkIf cfg.configureQuic true;

        package = let
          overrideNginx = pkg:
            if cfg.compileWithAWSlc then
              (pkg.override {
                openssl = pkgs.aws-lc;
                # some advanced regex's cause nginx to crash with:
                # traps: nginx[xxxxxx] trap invalid opcode ip:7fa6c23ebe79 sp:7ffcceaaa9e0 error:0 in memfd:sljit[1e79,7fa6c23ea000+10000]
                pcre2 = pkgs.pcre2.override { withJitSealloc = false; };
              }).overrideAttrs ({ patches ? [ ], ... }: {
                patches = patches ++ [
                  (let
                    # aws-lc 1.53+ wants nginx 1.28
                    patchVersion = if lib.versions.majorMinor pkg.version == "1.27" then
                      "1.52.0"
                    else
                      pkgs.aws-lc.version;
                  in pkgs.fetchpatch {
                    url = "https://github.com/aws/aws-lc/raw/refs/tags/v${patchVersion}/tests/ci/integration/nginx_patch/aws-lc-nginx.patch";
                    hash =
                      if patchVersion == "1.53.1" then
                        "sha256-WDNJqr4jiDuU869puFyjfyEvlJO3ZiWLwhX9GWnnJgc="
                      else if patchVersion == "1.52.0" then
                        "sha256-b7J13m3+A92H7vvGZ2aujwB855IKz7vUEmTMuL6XzuQ="
                      else if patchVersion == "1.50.0" then
                        "sha256-6OPLpt0hVDPdG70eJrwehwcX3i9N5lkvaeVaAjFSByM="
                      else
                        throw "aws-lc version ${patchVersion} is not supported.";
                  })
                ];
              })
            else
              pkg;
        in lib.mkIf (cfg.configureQuic || cfg.compileWithAWSlc || cfg.recommendedDefaults) (overrideNginx (
          if cfg.configureQuic then
            pkgs.nginxQuic
          else
            # use the newer version
            if lib.versionOlder pkgs.nginx.version pkgs.nginxMainline.version then
              pkgs.nginxMainline
            else
              pkgs.nginx
        ));

        recommendedBrotliSettings = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);
        recommendedGzipSettings = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);
        recommendedOptimisation = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);
        recommendedProxySettings = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);
        recommendedTlsSettings = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);
        recommendedZstdSettings = lib.mkIf cfg.allRecommendOptions (lib.mkDefault true);

        resolver.addresses =
          let
            isIPv6 = addr: builtins.match ".*:.*:.*" addr != null;
            escapeIPv6 = entry:
            let
              # cut off potential domain name from DoT
              addr = toString (lib.take 1 (builtins.split "#" entry));
            in
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
          lib.mkIf (cfg.recommendedDefaults || cfg.default404Server.enable || cfg.configureQuic) {
            "_" = {
              kTLS = lib.mkIf (cfg.recommendedDefaults && !cfg.compileWithAWSlc) true;
              reuseport = lib.mkIf (cfg.recommendedDefaults || cfg.configureQuic) true;

              default = lib.mkIf cfg.default404Server.enable true;
              addSSL = lib.mkIf cfg.default404Server.enable true;
              useACMEHost = lib.mkIf cfg.default404Server.enable cfg.default404Server.acmeHost;
              locations = lib.mkIf cfg.default404Server.enable {
                "/".return = 404;
              };

              listen = lib.mkIf cfg.tcpFastOpen (lib.mkDefault (lib.flatten (map (addr: [
                { inherit addr; port = 80; inherit extraParameters; }
                { inherit addr; port = 443; ssl = true; inherit extraParameters; }
              ]) config.services.nginx.defaultListenAddresses)));

              quic = lib.mkIf cfg.configureQuic true;
            };
          };
      };
    };

    security.dhparams = lib.mkIf cfg.generateDhparams {
      enable = cfg.generateDhparams;
      params.nginx = { };
    };

    systemd.services.nginx.restartTriggers = lib.mkIf cfg.recommendedDefaults [ config.users.users.${cfg.user}.extraGroups ];
  };
}
