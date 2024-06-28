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
              description = "Wether to check the given URLs with ip4, ip6 or both.";
            };

            statusCode = lib.mkOption {
              type = with lib.types; listOf ints.unsigned;
              example = [ 200 ];
              description = "HTTP status code which is considered sucessfull.";
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
        config = lib.mkIf (cfgb.httpProbe != { }) {
          # TODO: how to properly remove an attrset layer
          modules = lib.mkMerge (lib.mapAttrsToList (name: opts: let
            setting = {
              "http_${name}" = {
                http = {
                  fail_if_not_ssl = true;
                  ip_protocol_fallback = false;
                  method = "GET";
                  no_follow_redirects = true;
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
            // (lib.optionalAttrs (opts.ip == "both" || opts.ip == "ip6") {
            "http_${name}_ip6" = lib.recursiveUpdate setting."http_${name}" {
              http.preferred_ip_protocol = "ip6";
            };
          })) cfgb.httpProbe);
        };

        configFile = lib.mkIf (cfgb.config != { }) (yamlFormat.generate "blackbox-exporter.yaml" cfgb.config);
      };

      ruleFiles = map (rule: yamlFormat.generate "prometheus-rule" rule) cfg.rulesConfig;

      scrapeConfigs = let
        genHttpProbeScrapeConfig = { name, opts }: {
          job_name = "blackbox_http_${name}_${toString opts.statusCode}";
          metrics_path = "/probe";
          params.module = [ "http_${name}" ];
          relabel_configs = [ {
            source_labels = [ "__address__" ];
            target_label = "__param_target";
          } {
            source_labels = [ "__param_target" ];
            target_label = "instance";
          } {
            target_label = "__address__";
            replacement = cfgb.blackboxExporterURL;
          } ];
          static_configs = [ {
            targets = opts.urls;
          } ];
        };
      in lib.filter (v: v != null) (lib.mapAttrsToList (name: opts:
        if (opts.ip == "both" || opts.ip == "ip4") then (genHttpProbeScrapeConfig { inherit name opts; }) else null
      ) cfgb.httpProbe
      ++ lib.mapAttrsToList (name: opts:
        if (opts.ip == "both" || opts.ip == "ip6") then (genHttpProbeScrapeConfig { inherit name opts; } // {
          job_name = "blackbox_http_${name}_${toString opts.statusCode}_ip6";
          params.module = [ "http_${name}_ip6" ];
        }) else null
      ) cfgb.httpProbe);
    };
  };
}
