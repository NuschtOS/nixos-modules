{ config, lib, options, ... }:

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
      description = "Whether to add a hosts entry for the portunus domain pointing to externalIp";
    };

    configureOAuth2Proxy = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Wether to configure OAuth2 Proxy with Portunus' Dex.

        Use `services.oauth2-proxy.nginx.virtualHosts` to configure the nginx virtual hosts that should require authentication.

        To properly function this requires the services.oauth2-proxy.nginx.domain option from <https://github.com/NixOS/nixpkgs/pull/273234>.
      '';
    };

    internalIp4 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = "Internal IPv4 of portunus instance. This is used in the addToHosts option.";
    };

    internalIp6 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = "Internal IPv6 of portunus instance. This is used in the addToHosts option.";
    };

    ldapPreset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to set config.security.ldap to portunus specific settings.";
    };

    removeAddGroup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "When enabled, remove the function to add new Groups via the web ui, to enforce seeding usage.";
    };

    seedGroups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to seed groups configured in services as not member managed groups.";
    };

    domain = lib.mkOption {
      default = "";
    };

    webDomain = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "auth.example.com";
      description = "The domain name to connect to, to visit the ldap server web interface and to which to issue cookies to.";
    };
  };

  config = {
    assertions = [
      {
        assertion = cfg.configureOAuth2Proxy -> config.services.oauth2-proxy.keyFile != null;
        message = ''
          Setting services.portunus.configureOAuth2Proxy to true requires to set service.oauth2-proxy.keyFile
          to a file that contains `OAUTH2_PROXY_CLIENT_SECRET` and `OAUTH2_PROXY_COOKIE_SECRET`.
        '';
      }
      {
        assertion = cfg.enable -> lib.versionAtLeast config.services.portunus.package.version "2.0.0";
        message = "Portunus 2.0.0 is required for this module!";
      }
      {
        assertion = cfg.enable -> cfg.domain != "";
        message = "services.portunus.domain must be set to the domain name under which you can reach the *internal* Portunus ldaps port.";
      }
      {
        assertion = cfg.enable -> cfg.webDomain != "";
        message = "services.portunus.webDomain must be set to the domain name under which you can reach the Portunus Web UI.";
      }
    ];

    warnings = lib.optional cfg.addToHosts "services.portunus.addToHosts is deprecated! Please use security.ldap.domain instead."
      ++ lib.optional (cfg.internalIp4 != null) "services.portunus.internalIp4 is deprecated! Please use security.ldap.domain instead."
      ++ lib.optional (cfg.internalIp4 != null) "services.portunus.internalIp6 is deprecated! Please use security.ldap.domain instead.";

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
              (if (lib.versionAtLeast prev.dex-oidc.version "2.40") then
                ./dex-session-cookie-password-connector-2.40.patch
              else if (lib.versionAtLeast prev.dex-oidc.version "2.39") then
                ./dex-session-cookie-password-connector-2.39.patch
              else if (lib.versionAtLeast prev.dex-oidc.version "2.38") then
                ./dex-session-cookie-password-connector-2.38.patch
              else
                ./dex-session-cookie-password-connector-2.37.patch
              )

              # Complain if the env set in SecretEnv cannot be found
              (fetchpatch {
                url = "https://github.com/dexidp/dex/commit/f25f72053c9282cfe22521cd508698a07dc5190f.patch";
                hash = "sha256-dyo+UPpceHxL3gcBQaGaDAHJqmysDJw051gMG1aeh5o=";
              })
            ];

            vendorHash = if lib.versionAtLeast prev.dex-oidc.version "2.40" then
              "sha256-oxu3eNsjUGo6Mh6QybeGggsCZsZOGYo7nBD5ZU8MSy8="
            else if lib.versionAtLeast prev.dex-oidc.version "2.39" then
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
      callbackURL = "https://${cfg.webDomain}/oauth2/callback";
      clientID = "oauth2_proxy"; # - is not allowed in environment variables
    in {
      dex.settings = {
        issuer = lib.mkForce "https://${cfg.webDomain}/dex";
        # the user has no other option to accept this and all clients are internal anyway
        oauth2.skipApprovalScreen = true;
      };

      oauth2-proxy = lib.mkIf cfg.configureOAuth2Proxy {
        enable = true;
        inherit clientID;
        # if Portunus is not enabled locally, its domain is most likely wrong
        nginx.domain = lib.mkIf cfg.enable config.services.portunus.webDomain;
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
      webDomainName = cfg.webDomain;
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
      userFilter = replaceStr: "(|(uid=${replaceStr})(mail=${replaceStr}))";
      userBaseDN = "ou=users";
    };
  };
}
