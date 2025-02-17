{ config, lib, libS, ... }:

let
  cfg = config.services.grafana;
in
{
  options = {
    services.grafana = {
      configureNginx = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to configure Nginx.";
      };

      oauth = {
        enable = lib.mkEnableOption "login only via OAuth2";
        enableViewerRole = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the fallback Viewer role when users do not have the user- or adminGroup.";
        };
        adminGroup = libS.ldap.mkUserGroupOption;
        userGroup = libS.ldap.mkUserGroupOption;
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and secure default settings";
    };
  };

  imports = [
    (lib.mkRemovedOptionModule [ "services" "grafana" "configureRedis" ] ''
      The configureRedis option has been removed, as it only caches session which is normally not required for a small to medium sized instance.
    '')
  ];

  config = {
    # the default values are hardcoded instead of using options. because I couldn't figure out how to extract them from the freeform type
    assertions = lib.mkIf cfg.enable [
      {
        assertion = cfg.oauth.enable -> cfg.settings."auth.generic_oauth".client_secret != null;
        message = ''
          Setting services.grafana.oauth.enable to true requires to set services.grafana.settings."auth.generic_oauth".client_secret.
          Use this `$__file{/path/to/some/secret}` syntax to reference secrets securely.
        '';
      }
      {
        assertion = cfg.settings.security.secret_key != "SW2YcwTIb9zpOOhoPsMm";
        message = "services.grafana.settings.security.secret_key must be changed from it's insecure, default value!";
      }
      {
        assertion = cfg.settings.security.disable_initial_admin_creation || cfg.settings.security.admin_password != "admin";
        message = "services.grafana.settings.security.admin_password must be changed from it's insecure, default value!";
      }
    ];

    services.grafana.settings = lib.mkMerge [
      (lib.mkIf (cfg.enable && cfg.recommendedDefaults) (libS.modules.mkRecursiveDefault {
        # no analytics, sorry, not sorry
        analytics = {
          feedback_links_enabled = false;
          reporting_enabled = false;
        };
        log.level = "warn";
        security = {
          cookie_secure = true;
          content_security_policy = true;
          strict_transport_security = true;
        };
        server = {
          enable_gzip = true;
          root_url = "https://${cfg.settings.server.domain}";
        };
      }))

      (lib.mkIf (cfg.enable && cfg.configureNginx) {
        server = {
          protocol = "socket";
          socket_gid = config.users.groups.nginx.gid;
        };
      })

      (lib.mkIf (cfg.enable && cfg.oauth.enable) {
        "auth.generic_oauth" = let
          inherit (config.services.dex.settings) issuer;
        in {
          enabled = true;
          allow_assign_grafana_admin = true; # required for grafana-admins
          allow_sign_up = true; # otherwise no new users can be created
          api_url = "${issuer}/userinfo";
          auth_url = "${issuer}/auth";
          auto_login = true; # redirect automatically to the only oauth provider
          client_id = "grafana";
          disable_login_form = true; # only allow OAuth
          icon = "signin";
          name = config.services.portunus.webDomain;
          oauth_allow_insecure_email_lookup = true; # otherwise updating the mail in ldap will break login
          use_refresh_token = true;
          role_attribute_path = "contains(groups[*], '${cfg.oauth.adminGroup}') && 'Admin' || contains(groups[*], '${cfg.oauth.userGroup}') && 'Editor'"
            + lib.optionalString cfg.oauth.enableViewerRole "|| 'Viewer'";
          role_attribute_strict = true;
          # https://dexidp.io/docs/custom-scopes-claims-clients/
          scopes = "openid email groups profile offline_access";
          token_url = "${issuer}/token";
        };
      })
    ];
  };

  config.services.nginx = lib.mkIf (cfg.enable && cfg.configureNginx) {
    upstreams.grafana.servers."unix:${cfg.settings.server.socket}" = { };
    virtualHosts = {
      "${cfg.settings.server.domain}".locations = {
        "/".proxyPass = "http://grafana";
        "= /api/live/ws" = {
          proxyPass = "http://grafana";
          proxyWebsockets = true;
        };
      };
    };
  };

  config.services.portunus = {
    dex = lib.mkIf cfg.oauth.enable {
      enable = true;
      oidcClients = [{
        callbackURL = "https://${cfg.settings.server.domain}/login/generic_oauth";
        id = "grafana";
      }];
    };
    seedSettings.groups = lib.optional (cfg.oauth.adminGroup != null) {
      long_name = "Grafana Administrators";
      name = cfg.oauth.adminGroup;
      permissions = { };
    } ++ lib.optional (cfg.oauth.userGroup != null) {
      long_name = "Grafana Users";
      name = cfg.oauth.userGroup;
      permissions = { };
    };
  };

  config.users.users = lib.mkIf (cfg.enable && cfg.configureNginx) {
    grafana.extraGroups = [ "nginx" ];
  };
}
