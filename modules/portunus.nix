{ config, lib, pkgs, ... }:

let
  cfg = config.services.portunus;
  inherit (config.security) ldap;
in
{
  options.services.portunus = {
    # TODO: how to automatically set this?
    # maybe based on $service.ldap.enable && services.portunus.enable?
    addToHosts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to add a hosts entry for the portunus domain pointing to externalIp";
    };

    configureOAuth2Proxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Wether to configure OAuth2 Proxy with Portunus' Dex.

        Use `services.oauth2_proxy.nginx.virtualHosts` to configure the nginx virtual hosts that should require authentication.
      '';
    };

    internalIp4 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv4 of portunus instance. This is used in the addToHosts option.";
    };

    internalIp6 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv6 of portunus instance. This is used in the addToHosts option.";
    };

    ldapPreset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to set config.security.ldap to portunus specific settings.";
    };

    removeAddGroup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "When enabled, remove the function to add new Groups via the web ui, to enforce seeding usage.";
    };

    seedGroups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Wether to seed groups configured in services as not member managed groups.";
    };

    # TODO: upstream to nixos
    seedSettings = lib.mkOption {
      type = with lib.types; nullOr (attrsOf (listOf (attrsOf anything)));
      default = null;
      description = lib.mdDoc ''
        Seed settings for users and grousp.
        See upstream for format <https://github.com/majewsky/portunus#seeding-users-and-groups-from-static-configuration>
      '';
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.configureOAuth2Proxy -> config.services.oauth2_proxy.keyFile != null;
        message = ''
          Setting services.portunus.configureOAuth2Proxy to true requires to set service.oauth2_proxy.keyFile
          to a file that contains `OAUTH2_PROXY_CLIENT_SECRET` and `OAUTH2_PROXY_COOKIE_SECRET`.
        '';
      }
    ];

    networking.hosts = lib.mkIf cfg.addToHosts {
      ${cfg.internalIp4} = [ cfg.domain ];
      ${cfg.internalIp6} = [ cfg.domain ];
    };

    nixpkgs.overlays = lib.mkIf cfg.enable [
      (final: prev: with final; {
        dex-oidc = prev.dex-oidc.override {
          buildGoModule = args: buildGoModule (args // {
            patches = args.patches or [ ] ++ [
              # remember session
              (fetchpatch {
                url = "https://github.com/SuperSandro2000/dex/commit/d2fb6cdf8188e6973721ddac657a7c5d3daf6955.patch";
                hash = "sha256-PKC7jsNyFN28qFZ7SLYgnd0s09G2cb+vBeFvRzyyLGQ=";
              })
              # Complain if the env set in SecretEnv cannot be found
              (fetchpatch {
                url = "https://github.com/dexidp/dex/commit/f25f72053c9282cfe22521cd508698a07dc5190f.patch";
                hash = "sha256-dyo+UPpceHxL3gcBQaGaDAHJqmysDJw051gMG1aeh5o=";
              })
            ];

            vendorHash = "sha256-YIi67pPIcVndIjWk94ckv6X4WLELUe/J/03e+XWIdHE=";
          });
        };

        portunus = (prev.portunus.override { buildGoModule = buildGo121Module; }).overrideAttrs ({ patches ? [ ], buildInputs ? [ ], ... }: let
          version = "2.0.0-beta.2";
        in {
          inherit version;

          # TODO: upstream
          src = fetchFromGitHub {
            owner = "majewsky";
            repo = "portunus";
            rev = "v${version}";
            hash = "sha256-1OU3bepvqriGCW1qDszPnUDJ6eqBzNTiBZ2J4KF4ynw=";
          };

          patches = patches
            ++ lib.optional cfg.removeAddGroup ./portunus-remove-add-group.diff;

          # TODO: upstream
          buildInputs = buildInputs ++ [
            libxcrypt-legacy
          ];
        });
      })
    ];

    services = let
      callbackURL = "https://${cfg.domain}/oauth2/callback";
      clientID = "oauth2_proxy"; # - is not allowed in environment variables
    in {
      dex = {
        enable = lib.mkIf cfg.configureOAuth2Proxy true;
        # the user has no other option to accept this and all clients are internal anyway
        settings.oauth2.skipApprovalScreen = true;
      };

      oauth2_proxy = lib.mkIf cfg.configureOAuth2Proxy {
        enable = true;
        inherit clientID;
        nginx = {
          inherit (config.services.portunus) domain;
        };
        provider = "oidc";
        redirectURL = callbackURL;
        reverseProxy = true;
        upstream = "http://127.0.0.1:4181";
        extraConfig = {
          oidc-issuer-url = config.services.dex.settings.issuer;
          provider-display-name = "Portunus";
        };
      };

      portunus = {
         dex.oidcClients = lib.mkIf cfg.configureOAuth2Proxy [{
          inherit callbackURL;
          id = clientID;
        }];
        seedPath = pkgs.writeText "seed.json" (builtins.toJSON cfg.seedSettings);
      };
    };

    security.ldap = lib.mkIf cfg.ldapPreset {
      domainName = cfg.domain;
      givenNameField = "givenName";
      groupFilter = group: "(&(objectclass=person)(isMemberOf=cn=${group},${ldap.roleBaseDN}))";
      mailField = "mail";
      port = 636;
      roleBaseDN = "ou=groups";
      roleField = "cn";
      roleFilter = "(&(objectclass=groupOfNames)(member=%s))";
      roleValue = "dn";
      searchFilterWithGroupFilter = userFilterGroup: userFilter: if (userFilterGroup != null) then "(&${ldap.groupFilter userFilterGroup}${userFilter})" else userFilter;
      sshPublicKeyField = "sshPublicKey";
      searchUID = "search";
      surnameField = "sn";
      userField = "uid";
      userFilter = replaceStr: "(&(objectclass=person)(|(uid=${replaceStr})(mail=${replaceStr})))";
      userBaseDN = "ou=users";
    };
  };
}
