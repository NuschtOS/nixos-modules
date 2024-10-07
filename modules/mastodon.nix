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
    services.mastodon = {
      package = lib.mkIf cfg.enableBirdUITheme (pkgs.mastodon.overrideAttrs (_: with pkgs; let
        src = pkgs.applyPatches {
          src = fetchFromGitHub {
            owner = "mstdn";
            repo = "Bird-UI-Theme-Admins";
            rev = "2f9921db746593f393c13f9b79e5b4c2e19b03bd";
            hash = "sha256-+7FUm5GNXRWyS9Oiow6kwX+pWh11wO3stm5iOTY3sYY=";
          };

          patches = [
            # fix compose box background
            (fetchpatch {
              url = "https://github.com/mstdn/Bird-UI-Theme-Admins/commit/d5a07d653680fba0ad8dd941405e2d0272ff9cd1.patch";
              hash = "sha256-1gnQNCSSuTE/pkPCf49lJQbmeLAbaiPD9u/q8KiFvlU=";
            })
          ];
        };
      in {
        mastodonModules = mastodon.mastodonModules.overrideAttrs (oldAttrs: {
          pname = "mastodon-birdui-theme";

          nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
            rsync
            xorg.lndir
          ];

          postPatch = ''
            rsync -r ${src}/mastodon/ .
          '';
        });

        postBuild = ''
          cp ${src}/mastodon/config/themes.yml config/themes.yml
        '';
      }));

      extraConfig = lib.mkMerge [
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
    };

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
