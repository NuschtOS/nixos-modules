{ config, lib, pkgs, ... }:

let
  cfg = config.services.prometheus;
  cfgb = cfg.exporters.blackbox;

  yamlFormat = pkgs.formats.yaml { };
in
{
  options.services.prometheus = {
    exporters.blackbox = {
      blackboxExporterURL = lib.mkOption {
        type = lib.types.str;
        example = "127.0.0.1:9115";
        description = "URL under which prometheus can reach the blackbox exporter.";
      };

      # TODO: upstream
      config = lib.mkOption {
        inherit (yamlFormat) type;
        default = { };
        description = ''
          Structured configuration that is being written into blackbox' configFile option.

          See <https://github.com/prometheus/blackbox_exporter/blob/master/CONFIGURATION.md> for upstream documentation.
        '';
      };

      dnsProbe = lib.mkOption {
        type = with lib.types; attrsOf (submodule {
          options = {
            domains = lib.mkOption {
              type = with lib.types; listOf str;
              example = [ "example.com" ];
              description = "Query name to query";
            };

            targets = lib.mkOption {
              type = with lib.types; listOf str;
              default = if config.services.resolved.enable then [ "127.0.0.53" ] else lib.head config.networking.nameservers;
              defaultText = lib.literalExpression "if config.services.resolved.enable then [ \"127.0.0.53\" ] else lib.head config.networking.nameservers";
              description = "DNS servers to test this probe against.";
            };

            type = lib.mkOption {
              type = lib.types.str;
              example = "A";
              description = "Record type to query (A, AAAA, CNAME, SOA, NS, ...)";
            };
          };
        });
        default = { };
        example = ''
          {
            name = "example.com";
            type = "A";
          }
        '';
      };

      httpProbe = lib.mkOption {
        type = with lib.types; attrsOf (submodule {
          options = {
            urls = lib.mkOption {
              type = with lib.types; listOf str;
              example = [ "https://example.com" ];
              description = "URL to probe";
            };

            ip = lib.mkOption {
              type = lib.types.enum [ "both" "ip4" "ip6" ];
              default = "both";
              example = "ip6";
              description = "Whether to check the given URLs with ip4, ip6 or both.";
            };

            statusCode = lib.mkOption {
              type = with lib.types; listOf ints.unsigned;
              example = [ 200 ];
              description = "HTTP status code which is considered successful.";
            };
          };
        });
        default = { };
        example = ''
          {
            statusCode = [ 200 ];
            url = [ "https://example.com" ];
          }
        '';
      };
    };

    # TODO: upstream
    rulesConfig = lib.mkOption {
      type = lib.types.listOf yamlFormat.type;
      default = [ ];
      description = ''
        Structured configuration that is being written into prometheus' rules option.

        See <https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/> and
        <https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/> for upstream documentation.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.prometheus = {
      exporters.blackbox = {
        config.modules = lib.mkMerge (
          (lib.mapAttrsToList (probeName: opts:
            (lib.foldl (x: domain: x // {
              "dns_${probeName}_${domain}" = {
                dns = {
                  query_name = domain;
                  query_type = opts.type;
                  valid_rcodes = [ "NOERROR" ];
                };
                prober = "dns";
                timeout = "5s";
              };
            }) { } opts.domains)
          ) cfgb.dnsProbe)

        ++ lib.mapAttrsToList (name: opts: let
          setting = {
            "http_${name}" = {
              http = {
                ip_protocol_fallback = false;
                method = "GET";
                follow_redirects = false;
                preferred_ip_protocol = "ip4";
                valid_http_versions = [
                  "HTTP/1.1"
                  "HTTP/2.0"
                ];
                valid_status_codes = opts.statusCode;
              };
              prober = "http";
              timeout = "10s";
            };
          };
        in (lib.optionalAttrs (opts.ip == "both" || opts.ip == "ip4") setting)
          // (lib.optionalAttrs (opts.ip == "both") {
            "http_${name}_ip6" = lib.recursiveUpdate setting."http_${name}" {
              http.preferred_ip_protocol = "ip6";
            };
          }) // (lib.optionalAttrs (opts.ip == "ip6") {
            "http_${name}" = lib.recursiveUpdate setting."http_${name}" {
              http.preferred_ip_protocol = "ip6";
            };
          })
        ) cfgb.httpProbe);

        configFile = yamlFormat.generate "blackbox-exporter.yaml" cfgb.config;
      };

      ruleFiles = map (rule: yamlFormat.generate "prometheus-rule" rule) cfg.rulesConfig;

      scrapeConfigs = let
        commonProbeScrapeConfig = {
          metrics_path = "/probe";
          relabel_configs = [ {
            source_labels = [ "__address__" ];
            target_label = "__param_target"; # __param_* will be rewritten as query string
          } {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          } {
            # needed because blackbox exporter (ab)uses targets for its targets but we actually need to ask the exporter about the target state
            target_label = "__address__";
            replacement = cfgb.blackboxExporterURL;
          } ];
        };

        genHttpProbeScrapeConfig = { name, opts }: commonProbeScrapeConfig // {
          job_name = "blackbox_http_${name}";
          params.module = [ "http_${name}" ];
          static_configs = [ {
            targets = opts.urls;
          } ];
        };
      in lib.flatten (lib.foldl (x: probe: x ++ [
        (lib.foldl (x: domain: x ++ [
          (commonProbeScrapeConfig // {
            job_name = "blackbox_dns_${probe.name}_${domain}";
            params.module = [ "dns_${probe.name}_${domain}" ];
            static_configs = [ {
              inherit (probe.value) targets;
            } ];
          })
        ]) [ ] probe.value.domains)
      ]) [ ] (lib.attrsToList cfgb.dnsProbe))

      ++ lib.filter (v: v != null) (lib.mapAttrsToList (name: opts:
        if (opts.ip == "both" || opts.ip == "ip4") then (genHttpProbeScrapeConfig { inherit name opts; }) else null
      ) cfgb.httpProbe
      ++ lib.mapAttrsToList (name: opts:
        if (opts.ip == "both") then (genHttpProbeScrapeConfig { inherit name opts; } // {
          job_name = "blackbox_http_${name}_ip6";
          params.module = [ "http_${name}_ip6" ];
        }) else if (opts.ip == "ip6") then (genHttpProbeScrapeConfig { inherit name opts; } // {
          job_name = "blackbox_http_${name}";
          params.module = [ "http_${name}" ];
        }) else null
      ) cfgb.httpProbe);
    };
  };
}
