{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.mastodon;
  cfgl = cfg.ldap;
  cfgo = cfg.oauth;
  inherit (config.security) ldap;
in
{
  options.services.mastodon = {
    enableBirdUITheme = lib.mkEnableOption "Bird UI Theme";

    extraSecretsEnv = lib.mkOption {
      type = with lib.types; nullOr path;
      default = null;
      description = ''
        Extra envs to write into `/var/lib/mastodon/.secrets_env`.

        The format is:

        ```
        OIDC_CLIENT_SECRET="$(cat /path/to/clientSecret)"
        ```
      '';
    };

    ldap = {
      enable = lib.mkEnableOption "login via LDAP";

      userGroup = libS.ldap.mkUserGroupOption;
    };

    oauth = {
      enable = lib.mkEnableOption ''
        login via OAuth2.
        This requires providing OIDC_CLIENT_SECRET via services.mastodon.extraSecretsEnv
      '';

      clientId = lib.mkOption {
        type = lib.types.str;
        description = "OAuth2 client id";
      };
    };
  };

  config = {
    nixpkgs.overlays = lib.mkIf cfg.enableBirdUITheme [
      (final: prev: {
        mastodon = (prev.mastodon.override {
          patches = [
            # redone based on https://codeberg.org/rheinneckar.social/nixos-config/src/branch/main/patches/mastodon-bird-ui.patch
            ./mastodon-bird-ui.patch
          ];
        }).overrideAttrs (oldAttrs: let
          src = pkgs.applyPatches {
            src = final.fetchFromGitHub {
              owner = "ronilaukkarinen";
              repo = "mastodon-bird-ui";
              tag = "2.1.1";
              hash = "sha256-WEw9wE+iBCLDDTZjFoDJ3EwKTY92+LyJyDqCIoVXhzk=";
            };

            # based on:
            # https://github.com/ronilaukkarinen/mastodon-bird-ui#make-mastodon-bird-ui-as-optional-by-integrating-it-as-site-theme-in-settings-for-all-users
            postPatch = ''
              substituteInPlace layout-single-column.css layout-multiple-columns.css \
                --replace-fail theme-contrast theme-mastodon-bird-ui-contrast \
                --replace-fail theme-mastodon-light theme-mastodon-bird-ui-light

              mkdir mastodon-bird-ui
              mv layout-single-column.css mastodon-bird-ui/layout-single-column.scss
              mv layout-multiple-columns.css mastodon-bird-ui/layout-multiple-columns.scss

              echo -e "@import 'contrast/variables';
              @import 'application';
              @import 'contrast/diff';
              @import 'mastodon-bird-ui/layout-single-column.scss';
              @import 'mastodon-bird-ui/layout-multiple-columns.scss';" > mastodon-bird-ui-contrast.scss
              echo -e "@import 'mastodon-light/variables';
              @import 'application';
              @import 'mastodon-light/diff';
              @import 'mastodon-bird-ui/layout-single-column.scss';
              @import 'mastodon-bird-ui/layout-multiple-columns.scss';" > mastodon-bird-ui-light.scss
              echo -e "@import 'application';
              @import 'mastodon-bird-ui/layout-single-column.scss';
              @import 'mastodon-bird-ui/layout-multiple-columns.scss';" > mastodon-bird-ui-dark.scss
            '';
          };
        in {
          mastodonModules = oldAttrs.mastodonModules.overrideAttrs (oldAttrs: {
            pname = "mastodon-birdui-theme";

            postPatch = oldAttrs.postPatch or "" + ''
              cp -r ${src}/*.scss ${src}/mastodon-bird-ui/ app/javascript/styles/
            '';
          });
        });
      })
    ];

    services.mastodon.extraConfig = lib.mkMerge [
      (lib.mkIf cfgl.enable {
        LDAP_ENABLED = "true";
        LDAP_BASE = ldap.userBaseDN;
        LDAP_BIND_DN = ldap.bindDN;
        LDAP_HOST = ldap.domainName;
        LDAP_METHOD = "simple_tls";
        LDAP_PORT = toString ldap.port;
        LDAP_UID = ldap.userField;
        # convert .,- (space) in LDAP usernames to underscore, otherwise those users cannot log in
        LDAP_UID_CONVERSION_ENABLED = "true";
        LDAP_SEARCH_FILTER = ldap.searchFilterWithGroupFilter cfgl.userGroup "(|(%{uid}=%{email})(%{mail}=%{email}))";
      })

      (lib.mkIf cfgo.enable {
        OIDC_ENABLED = "true";
        OIDC_DISPLAY_NAME = "auth.c3d2.de";
        OIDC_DISCOVERY = "true";
        OIDC_ISSUER = config.services.dex.settings.issuer;
        OIDC_AUTH_ENDPOINT = config.services.dex.discoveryEndpoint;
        OIDC_SCOPE = "openid,profile,email";
        OIDC_UID_FIELD = "preferred_username";
        OIDC_CLIENT_ID = cfgo.clientId;
        OIDC_REDIRECT_URI = "https://${cfg.localDomain}/auth/auth/openid_connect/callback";
        OIDC_SECURITY_ASSUME_EMAIL_IS_VERIFIED = "true";
      })
    ];

    systemd.services = lib.mkIf (cfg.extraSecretsEnv != null) {
      mastodon-init-dirs.script = lib.mkAfter ''
        cat ${cfg.extraSecretsEnv} >> /var/lib/mastodon/.secrets_env
      '';
    };
  };

  config.services.portunus.seedSettings.groups = lib.optional (cfgl.userGroup != null) {
    long_name = "Mastodon Users";
    name = cfgl.userGroup;
    permissions = { };
  };
}
