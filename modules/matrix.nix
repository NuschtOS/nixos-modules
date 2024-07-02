{ config, lib, libS, options, pkgs, ... }:

let
  cfg = config.services.matrix-synapse;
  cfge = cfg.element-web;
  cfgl = cfg.ldap;
  cfgs = cfg.matrix-sliding-sync;
  inherit (config.security) ldap;
in
{
  options = {
    services.matrix-synapse = {
      addAdditionalOembedProvider = libS.mkOpinionatedOption "add additional oembed providers from oembed.com";

      domain = lib.mkOption {
        type = lib.types.str;
        example = "matrix.example.com";
        description = "The domain that matrix-synapse will use.";
      };

      element-web = {
        enable = lib.mkEnableOption "the element-web client";

        domain = lib.mkOption {
          type = lib.types.str;
          example = "element.example.com";
          description = "The domain that element-web will use.";
        };

        package = lib.mkPackageOption pkgs "element-web" { };

        enableConfigFeatures = libS.mkOpinionatedOption "enable most features available via config.json";
      };

      ldap = {
        enable = lib.mkEnableOption "login via ldap";

        userGroup = libS.ldap.mkUserGroupOption;

        searchUserPasswordFile = lib.mkOption {
          type = lib.types.str;
          example = "/var/lib/secrets/search-user-password";
          description = "Path to a file containing the password for the search/bind user.";
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";

      matrix-sliding-sync = {
        enable = lib.mkEnableOption "the extra sliding-sync service. Make sure to also configure the services.matrix-sliding-sync.environmentFile setting";

        domain = lib.mkOption {
          type = lib.types.str;
          example = "matrix-sliding-sync.example.com";
          description = "The domain that matrix-sliding-sync will use.";
        };
      };
    };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "services" "matrix-synapse" "ldap" "bindPasswordFile" ] [ "services" "matrix-synapse" "ldap" "searchUserPasswordFile" ])
  ];

  # NOTE: mkMerge cannot be used on config otherwise services.matrix-sliding-sync.enable causes an infinite recursion
  config.environment.etc = lib.mkIf cfg.enable {
    "matrix-synapse/config.yaml".source = cfg.configFile;
  };

  config.services.matrix-synapse = lib.mkMerge [
    {
      settings.oembed.additional_providers = lib.mkIf cfg.addAdditionalOembedProvider [
        (
          let
            providers = pkgs.fetchurl {
              url = "https://oembed.com/providers.json?2023-03-23";
              hash = "sha256-OdgBgkLbtNMn84ixKuC1gGzpyr+X+ORiLl6TAK3lYuQ=";
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
        public_baseurl = "https://${cfg.domain}";
        suppress_key_server_warning = true;
        user_directory.prefer_local_users = true;
      };
      withJemalloc = true;
    })

    (lib.mkIf cfge.enable {
      settings = lib.mkIf cfge.enable rec {
        email.client_base_url = web_client_location;
        web_client_location = "https://${cfge.domain}";
      };
    })

    (lib.mkIf cfgl.enable {
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
          bind_password_file = cfgl.searchUserPasswordFile;
          tls_options.validate = true;
        } // lib.optionalAttrs (cfgl.userGroup != null) {
          filter = ldap.groupFilter cfgl.userGroup;
        };
      }];
    })

    (lib.mkIf cfgs.enable {
      enableRegistrationScript = false; # required for listenging on unix socket

      settings.listeners = lib.mkForce [
        ((lib.head (lib.head (lib.head options.services.matrix-synapse.settings.type.getSubModules).imports).options.listeners.default) // {
          bind_addresses = null;
          path = "/run/matrix-synapse/matrix-synapse.sock";
          port = null;
          tls = null;
        })
     ];
    })
  ];

  config.services.matrix-sliding-sync = lib.mkIf cfgs.enable {
    enable = true;
    settings = {
      SYNCV3_BINDADDR = "/run/matrix-sliding-sync/matrix-sliding-sync.sock";
      SYNCV3_SERVER = "/run/matrix-synapse/matrix-synapse.sock";
    };
  };

  config.services.nginx = {
    upstreams = lib.mkIf cfgs.enable {
      matrix-sliding-sync.servers."unix:${config.services.matrix-sliding-sync.settings.SYNCV3_BINDADDR}" = { };
      matrix-synapse.servers."unix:${config.services.matrix-sliding-sync.settings.SYNCV3_SERVER}" = { };
    };
    virtualHosts = lib.mkIf (cfge.enable || cfgs.enable) {
      "${cfge.domain}" = lib.mkIf cfge.enable {
        forceSSL = true;
        locations."/".root = (cfge.package.override {
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
              feature_jump_to_date = true;
              feature_mjolnir = true;
              feature_notifications = true;
              feature_pinning = true;
              feature_report_to_moderators = true;
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

      "${cfg.domain}" = lib.mkIf cfgs.enable {
        forceSSL = true;
        locations."/".proxyPass = "http://matrix-synapse";
      };

      "${cfgs.domain}" = lib.mkIf cfgs.enable {
        forceSSL = true;
        locations."/".proxyPass = "http://matrix-sliding-sync";
      };
    };
  };

  config.services.portunus.seedSettings.groups = lib.optional (cfgl.userGroup != null) {
    long_name = "Matrix Users";
    name = cfgl.userGroup;
    permissions = { };
  };

  config.systemd = lib.mkIf cfgs.enable {
    # don't hazzle with postgres socket auth and DynamicUser
    services.matrix-sliding-sync.serviceConfig = {
      DynamicUser = lib.mkForce false;
      Group = "matrix-sliding-sync";
      RuntimeDirectory = "matrix-sliding-sync";
      User = "matrix-sliding-sync";
    };
  };

  config.users = lib.mkIf cfgs.enable {
    groups.matrix-sliding-sync = { };
    users = {
      matrix-sliding-sync = {
        extraGroups = [ "matrix-synapse" ];
        group = "matrix-sliding-sync";
        isSystemUser = true;
      };
      nginx.extraGroups = [ "matrix-synapse" ];
    };
  };
}
