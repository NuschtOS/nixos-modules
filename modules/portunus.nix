{ config, lib, options, pkgs, ... }:

let
  cfg = config.services.portunus;
  inherit (config.security) ldap;
in
{
  options.services.portunus = {
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

        To properly function this requires the services.oauth2_proxy.nginx.domain option from <https://github.com/NixOS/nixpkgs/pull/273234>.
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
      {
        assertion = cfg.enable -> lib.versionAtLeast config.services.portunus.package.version "2.0.0";
        message = "Portunus 2.0.0 is required for this module!";
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
              (if (lib.versionAtLeast prev.dex-oidc.version "2.39") then
                (fetchpatch {
                  url = "https://github.com/SuperSandro2000/dex/commit/b1cecedb6dba9027679b0a0fcd0a2863dece2e8d.patch";
                  hash = "sha256-2k5ulZ6sh1g0u3cAGnsL3O6m4vX0NBnpjgDSagMobx8=";
                })
              else if (lib.versionAtLeast prev.dex-oidc.version "2.38") then
                (fetchpatch {
                  url = "https://github.com/SuperSandro2000/dex/commit/c1b2ac971920f1e07ce0e3d5890fe4f5d4e6207a.patch";
                  hash = "sha256-UVlA9sJrjg05tlqd3ELPB1OZtWlRXSvKTYPiz9oIuc0=";
                })
              else
                (fetchpatch {
                  url = "https://github.com/SuperSandro2000/dex/commit/d2fb6cdf8188e6973721ddac657a7c5d3daf6955.patch";
                  hash = "sha256-PKC7jsNyFN28qFZ7SLYgnd0s09G2cb+vBeFvRzyyLGQ=";
                })
              )
            ] ++ [
              # Complain if the env set in SecretEnv cannot be found
              (fetchpatch {
                url = "https://github.com/dexidp/dex/commit/f25f72053c9282cfe22521cd508698a07dc5190f.patch";
                hash = "sha256-dyo+UPpceHxL3gcBQaGaDAHJqmysDJw051gMG1aeh5o=";
              })
            ];

            vendorHash = if lib.versionAtLeast prev.dex-oidc.version "2.39" then
              "sha256-NgKZb2Oi4BInO/dSLzSUK722L/3pWQFWSNynjSj5sEE="
            else if lib.versionAtLeast prev.dex-oidc.version "2.38" then
              "sha256-f0b4z+Li0nspdWQyg4DPv6kFCO9xzO8IZBScSX2DoIs="
            else
              "sha256-YIi67pPIcVndIjWk94ckv6X4WLELUe/J/03e+XWIdHE=";
          });
        };

        portunus = prev.portunus.overrideAttrs ({ patches ? [ ], ... }: {
          patches = patches
            ++ lib.optional cfg.removeAddGroup ./portunus-remove-add-group.diff;
        });
      })
    ];

    services = let
      callbackURL = "https://${cfg.domain}/oauth2/callback";
      clientID = "oauth2_proxy"; # - is not allowed in environment variables
    in {
      # the user has no other option to accept this and all clients are internal anyway
      dex.settings.oauth2.skipApprovalScreen = true;

      oauth2_proxy = lib.mkIf cfg.configureOAuth2Proxy {
        enable = true;
        inherit clientID;
        nginx = lib.optionalAttrs (options.services.oauth2-proxy.nginx.domain or null != null) {
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

      portunus.dex = lib.mkIf cfg.configureOAuth2Proxy {
        enable = true;
        oidcClients = [{
          inherit callbackURL;
          id = clientID;
        }];
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
