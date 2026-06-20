{ config, lib, libS, ... }:

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
          # redone based on https://codeberg.org/rheinneckar.social/nixos-config/src/branch/main/patches/mastodon-bird-ui.patch
          patches = [
            ./mastodon-bird-ui.patch
          ];
        }).overrideAttrs (oldAttrs: {
          mastodonModules = oldAttrs.mastodonModules.overrideAttrs (oldAttrs: let
            src = final.fetchFromGitHub rec {
              name = "mastodon-bird-ui-${tag}";
              owner = "ronilaukkarinen";
              repo = "mastodon-bird-ui";
              tag = "4.0.0";
              hash = "sha256-rFPkPLspuswC4vZHpedDvpBJOeV2rUuU1wxfKYY2ixw=";
            };
          in {
            pname = "mastodon-birdui-theme";

            postPatch = oldAttrs.postPatch or "" + /* bash */ ''
              STYLES_PATH="app/javascript/styles"
              BIRD_UI_PATH="$STYLES_PATH/mastodon-bird-ui"
              SRC_DIR=${src}/src
              mkdir -p $BIRD_UI_PATH/{components,components/profile,components/profile/icons,layouts,micro-interactions,variables,variants}

              # Core module files
              cp "$SRC_DIR/_index.scss" "$BIRD_UI_PATH/_index.scss"

              # Variables
              for f in "$SRC_DIR/variables/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/variables/$(basename "$f")"
              done

              # Components
              for f in "$SRC_DIR/components/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/components/$(basename "$f")"
              done

              # Profile components
              for f in "$SRC_DIR/components/profile/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/components/profile/$(basename "$f")"
              done

              # Profile icons
              for f in "$SRC_DIR/components/profile/icons/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/components/profile/icons/$(basename "$f")"
              done

              # Layouts
              for f in "$SRC_DIR/layouts/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/layouts/$(basename "$f")"
              done

              # Micro-interactions
              for f in "$SRC_DIR/micro-interactions/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/micro-interactions/$(basename "$f")"
              done

              # Variants
              for f in "$SRC_DIR/variants/"_*.scss; do
                cp "$f" "$BIRD_UI_PATH/variants/$(basename "$f")"
              done

              cat > "$BIRD_UI_PATH/mastodon-bird-ui.scss" << 'EOF'
              @use "index";
              EOF

              echo "@use 'application';
              @use 'mastodon-bird-ui';
              @use 'mastodon-bird-ui/variables/light-mixin' as light;

              [data-color-scheme=\"light\"] {
                @include light.tokens;
              }

              @media (prefers-color-scheme: light) {
                html:not([data-color-scheme]) {
                  @include light.tokens;
                }
              }" > "$STYLES_PATH/mastodon-bird-ui-auto.scss"
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
