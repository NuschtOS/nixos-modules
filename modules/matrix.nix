{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.matrix-synapse;
  cfge = cfg.element-web;
  inherit (config.security) ldap;
in
{
  options = {
    services.matrix-synapse = {
      addAdditionalOembedProvider = libS.mkOpinionatedOption "add additional oembed providers from oembed.com";

      element-web = {
        enable = lib.mkEnableOption (lib.mdDoc "the element-web client");

        domain = lib.mkOption {
          type = lib.types.str;
          example = "element.example.org";
          description = lib.mdDoc "The domain that element-web will use.";
        };

        package = lib.mkPackageOptionMD pkgs "Element-Web" {
          default = [ "element-web" ];
        };

        enableConfigFeatures = libS.mkOpinionatedOption "enable most features available via config.json";
      };

      ldap = {
        enable = lib.mkEnableOption (lib.mdDoc "login via ldap");

        userGroup = libS.ldap.mkUserGroupOption;

        bindPasswordFile = lib.mkOption {
          type = lib.types.str;
          example = "/var/lib/secrets/bind-password";
          description = lib.mdDoc "Path to a file containing the bind password.";
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
    };
  };

  config.environment.etc = lib.mkIf cfg.enable {
    "matrix-synapse/config.yaml".source = cfg.configFile;
  };

  config.services.nginx = lib.mkIf cfge.enable {
    enable = true;
    virtualHosts."${cfge.domain}" = {
      forceSSL = true;
      enableACME = lib.mkDefault true;
      root = (cfge.package.override {
        conf = with config.services.matrix-synapse.settings; {
          default_server_config."m.homeserver" = {
            "base_url" = public_baseurl;
            "server_name" = server_name;
          };
          default_theme = "dark";
          room_directory.servers = [ server_name ];
        } // lib.optionalAttrs cfge.enableConfigFeatures {
          features = {
            # https://github.com/matrix-org/matrix-react-sdk/blob/develop/src/settings/Settings.tsx
            # https://github.com/vector-im/element-web/blob/develop/docs/labs.md
            feature_ask_to_join = true;
            feature_bridge_state = true;
            feature_exploring_public_spaces = true;
            feature_jump_to_date = true;
            feature_mjolnir = true;
            feature_pinning = true;
            feature_presence_in_room_list = true;
            feature_report_to_moderators = true;
            feature_qr_signin_reciprocate_show = true;
          };
          show_labs_settings = true;
        };
      }).overrideAttrs ({ postInstall ? "", ... }: {
        # prevent 404 spam in nginx log
        postInstall = postInstall + ''
          ln -rs $out/config.json $out/config.${cfge.domain}.json
        '';
      });
    };
  };

  config.services.matrix-synapse = lib.mkMerge [
    {
      settings = lib.mkIf cfge.enable rec {
        email.client_base_url = web_client_location;
        web_client_location = "https://${cfge.domain}";
      };
    }

    (lib.mkIf cfg.ldap.enable {
      plugins = with config.services.matrix-synapse.package.plugins; [
        matrix-synapse-ldap3
      ];

      settings.modules = [{
        module = "ldap_auth_provider.LdapAuthProviderModule";
        config = {
          enabled = true;
          mode = "search";
          uri = "ldaps://${ldap.domainName}:${toString ldap.port}";
          base = ldap.userBaseDN;
          attributes = {
            uid = ldap.userField;
            mail = ldap.mailField;
            name = ldap.givenNameField;
          };
          bind_dn = ldap.bindDN;
          bind_password_file = cfg.ldap.bindPasswordFile;
          tls_options.validate = true;
        } // lib.optionalAttrs (cfg.ldap.userGroup != null) {
          filter = ldap.groupFilter cfg.ldap.userGroup;
        };
      }];
    })

    {
      settings.oembed.additional_providers = lib.mkIf cfg.addAdditionalOembedProvider [
        (
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
        )
      ];
    }

    (lib.mkIf cfg.recommendedDefaults {
      settings = {
        federation_client_minimum_tls_version = "1.2";
        suppress_key_server_warning = true;
        user_directory.prefer_local_users = true;
      };
      withJemalloc = true;
    })
  ];

  config.services.portunus.seedSettings.groups = lib.optional (cfg.ldap.userGroup != null) {
    long_name = "Matrix Users";
    name = cfg.ldap.userGroup;
    permissions = { };
  };
}
