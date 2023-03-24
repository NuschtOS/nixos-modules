{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.matrix-synapse;
  inherit (config.security) ldap;
in
{
  options = {
    services.matrix-synapse = {
      addAdditionalOembedProvider = libS.mkOpinionatedOption "add additional oembed providers from oembed.com";

      ldap = {
        enable = lib.mkEnableOption (lib.mdDoc "login via ldap");

        userFilter = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "(objectClass=posixAccount)";
          description = lib.mdDoc "Ldap filter used for accounts loggin in.";
        };

        bindPasswordFile = lib.mkOption {
          type = lib.types.str;
          example = "/var/lib/secrets/bind-password";
          description = lib.mdDoc "Path to a file containing the bind password.";
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services.matrix-synapse = lib.mkMerge [
      (lib.mkIf cfg.addAdditionalOembedProvider {
        plugins = with config.services.matrix-synapse.package.plugins; [
          matrix-synapse-ldap3
        ];

        settings.modules = [{
          module = "ldap_auth_provider.LdapAuthProvider";
          config = {
            enabled = true;
            mode = "search";
            uri = "ldaps://${ldap.domainName}:${toString ldap.port}";
            base = ldap.userBaseDN;
            attributes = {
               uid = ldap.roleField;
               mail = ldap.mailField;
               name = ldap.givenNameField;
             };
            bind_dn = ldap.bindDN;
            bind_password_file = cfg.ldap.bindPasswordFile;
            tls_options.validate = true;
          } // lib.optionalAttrs (cfg.ldap.userFilter != null) {
            filter = cfg.ldap.userFilter;
          };
        }];
      })

      (lib.mkIf cfg.addAdditionalOembedProvider {
        settings.oembed.additional_providers = [(
          let
            providers = pkgs.fetchurl {
              url = "https://oembed.com/providers.json?2023-03-23";
              sha256 = "sha256-OdgBgkLbtNMn84ixKuC1gGzpyr+X+ORiLl6TAK3lYuQ=";
            };
          in
          pkgs.runCommand "providers.json"
            {
              nativeBuildInputs = with pkgs; [ jq ];
            } ''
            # filter out entries that do not contain a schemes entry
            # Error in configuration at 'oembed.additional_providers.<item 0>.<item 22>.endpoints.<item 0>': 'schemes' is a required property
            # and have none http protocols: Unsupported oEmbed scheme (spotify) for pattern: spotify:*
            jq '[ ..|objects| select(.endpoints[0]|has("schemes")) | .endpoints[0].schemes=([ .endpoints[0].schemes[]|select(.|contains("http")) ]) ]' ${providers} > $out
          ''
        )];
      })

      (lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
        settings = {
          federation_client_minimum_tls_version = "1.2";
          report_stats = false;
          suppress_key_server_warning = true;
          url_preview_ip_range_blacklist = [
            "127.0.0.0/8"
            "10.0.0.0/8"
            "172.16.0.0/12"
            "192.168.0.0/16"
            "100.64.0.0/10"
            "192.0.0.0/24"
            "169.254.0.0/16"
            "192.88.99.0/24"
            "198.18.0.0/15"
            "192.0.2.0/24"
            "198.51.100.0/24"
            "203.0.113.0/24"
            "224.0.0.0/4"
            "::1/128"
            "fe80::/10"
            "fc00::/7"
            "2001:db8::/32"
            "ff00::/8"
            "fec0::/10"
          ];
          user_directory.prefer_local_users = true;
        };
        withJemalloc = true;
      }))
    ];
  };
}
