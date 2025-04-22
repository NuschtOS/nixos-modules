{ config, lib, libS, options, pkgs, ... }:

let
  cfg = config.services.matrix-synapse;
  cfga = cfg.synapse-admin;
  cfge = cfg.element-web;
  cfgl = cfg.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.matrix-synapse = {
      addAdditionalOembedProvider = libS.mkOpinionatedOption "add additional oembed providers from oembed.com";

      configurePostgres = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Whether to configure and create a local PostgreSQL database.";
      };

      domain = lib.mkOption {
        type = lib.types.str;
        example = "matrix.example.com";
        description = "The domain that matrix-synapse will use.";
      };

      element-web = {
        enable = lib.mkEnableOption "" // { description = "Whether to configure the element-web client under Matrix' domain."; };

        domain = lib.mkOption {
          type = lib.types.str;
          example = "element.example.com";
          description = "The domain that element-web will use.";
        };

        package = lib.mkPackageOption pkgs "element-web" { };

        enableConfigFeatures = libS.mkOpinionatedOption "enable most features available via config.json";
      };

      listenOnSocket = libS.mkOpinionatedOption "listen on a unix socket instead of a port";

      ldap = {
        enable = lib.mkEnableOption "login via ldap";

        userGroup = libS.ldap.mkUserGroupOption;

        searchUserPasswordFile = lib.mkOption {
          type = lib.types.str;
          example = "/var/lib/secrets/search-user-password";
          description = "Path to a file containing the password for the search/bind user.";
        };
      };

      synapse-admin = {
        enable = lib.mkEnableOption "" // { description = "Whether to configure synapse-admin to be served at the matrix servers domain under the /admin path."; };

        package = lib.mkPackageOption pkgs "synapse-admin" { } // {
          # TODO: remove after 25.05
          default = pkgs.synapse-admin-etkecc or pkgs.synapse-admin;
          example = "pkgs.synapse-admin-etkecc";
          extraDescription = "If synapse-admin-etkecc exists, that is the default, otherwise synapse-admin.";
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
    };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "services" "matrix-synapse" "ldap" "bindPasswordFile" ] [ "services" "matrix-synapse" "ldap" "searchUserPasswordFile" ])
    (lib.mkRemovedOptionModule [ "services" "matrix-synapse" "matrix-sliding-sync" ] "matrix-sliding-sync has been removed as matrix-synapse 114.0 and later covers its functionality")
  ];

  config = lib.mkIf cfg.enable {
    assertions = [ {
      assertion = cfg.listenOnSocket -> config.services.nginx.enable;
      message = "Enabling services.matrix-synapse.listenOnSocket requires enabling services.nginx.enable";
    } ];

    environment.etc."matrix-synapse/config.yaml".source = cfg.configFile;

    services.matrix-synapse = lib.mkMerge [
      {
        enableRegistrationScript = lib.mkIf cfg.listenOnSocket false;

        settings.listeners = lib.mkIf cfg.listenOnSocket (lib.mkForce [
          ((lib.head (lib.head (lib.head options.services.matrix-synapse.settings.type.getSubModules).imports).options.listeners.default) // {
            bind_addresses = null;
            path = "/run/matrix-synapse/matrix-synapse.sock";
            port = null;
            tls = null;
          })
        ]);

        settings.oembed.additional_providers = lib.mkIf cfg.addAdditionalOembedProvider [
          (
            let
              providers = pkgs.fetchurl {
                url = "https://oembed.com/providers.json?2024-12-13";
                hash = "sha256-CL2d/DRukPZCHOkAWz3dCD1551KLcdIJBG1XiaWXYc8=";
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
        settings = {
          email.client_base_url = cfg.settings.web_client_location;
          web_client_location = "https://${cfge.domain}";
        };
      })

      (lib.mkIf cfgl.enable {
        plugins = with cfg.package.plugins; [
          matrix-synapse-ldap3
        ];

        settings.modules = [{
          module = "ldap_auth_provider.LdapAuthProviderModule";
          config = {
            enabled = true;
            mode = "search";
            uri = ldap.serverURI;
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
    ];

    services.nginx = {
      upstreams = lib.mkIf cfg.listenOnSocket {
        matrix-synapse.servers."unix:/run/matrix-synapse/matrix-synapse.sock" = { };
      };

      virtualHosts = lib.mkMerge [
        (lib.mkIf cfga.enable {
          # see https://github.com/etkecc/synapse-admin/blob/main/docs/reverse-proxy.md#nginx
          "${cfg.domain}" = {
            forceSSL = lib.mkIf cfg.recommendedDefaults true;
            locations = {
              "= /admin".return = "307 /admin/";
              "/admin/" = {
                alias = "${cfga.package}/";
                priority = 500;
                tryFiles = "$uri $uri/ /index.html";
              };
              "~ ^/admin/.*\\.(?:css|js|jpg|jpeg|gif|png|svg|ico|woff|woff2|ttf|eot|webp)$" = {
                priority = 400;
                root = cfga.package;
                extraConfig = /* nginx */ ''
                  rewrite ^/admin/(.*)$ /$1 break;
                  expires 30d;
                  more_set_headers "Cache-Control: public";
                '';
              };
            };
          };
        })

        (lib.mkIf cfge.enable {
          "${cfge.domain}" = {
            forceSSL = lib.mkIf cfg.recommendedDefaults true;
            locations."/".root = (cfge.package.override {
              conf = lib.recursiveUpdate
                (lib.recursiveUpdate
                  (let
                    inherit (config.services.matrix-synapse.settings) public_baseurl server_name;
                  in {
                    default_server_config."m.homeserver" = {
                      "base_url" = public_baseurl;
                      "server_name" = server_name;
                    };
                    default_theme = "dark";
                    room_directory.servers = [ server_name ];
                  })
                  (lib.optionalAttrs cfge.enableConfigFeatures {
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
                  })
                )
                (cfge.package.conf or { });
            }).overrideAttrs ({ postInstall ? "", ... }: {
              # prevent 404 spam in nginx log
              postInstall = postInstall + ''
                ln -rs $out/config.json $out/config.${cfge.domain}.json
              '';
            });
          };
        })

        {
          "${cfg.domain}" = {
            forceSSL = lib.mkIf cfg.recommendedDefaults true;
            locations."/" = lib.mkIf cfg.listenOnSocket {
              proxyPass = "http://matrix-synapse";
            };
          };
        }
      ];
    };

    services.postgresql = lib.mkIf cfg.configurePostgres {
      databases = [ "matrix-synapse" ]; # some parts of nixos-modules read this field to know all databases
    };

    services.portunus.seedSettings.groups = lib.mkIf (cfgl.userGroup != null) [ {
      long_name = "Matrix Users";
      name = cfgl.userGroup;
      permissions = { };
    } ];

    systemd.services = lib.mkIf cfg.configurePostgres {
      # https://element-hq.github.io/synapse/latest/postgres.html#set-up-database
      # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/databases/postgresql.nix#L655
      postgresql.postStart = ''
        $PSQL -tAc "SELECT 1 FROM pg_database WHERE datname = 'matrix-synapse'" | grep -q 1 || $PSQL -tAc 'CREATE DATABASE "matrix-synapse" ENCODING="UTF8" LOCALE="C" TEMPLATE="template0" OWNER="matrix-synapse"'
      '';
    };

    users.users = lib.mkIf cfg.listenOnSocket {
      nginx.extraGroups = [ "matrix-synapse" ];
    };
  };
}
