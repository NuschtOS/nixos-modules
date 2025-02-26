{ config, lib, ... }:

let
  cfg = config.services.portunus;
  cfgd = config.services.dex;
  cfgo = config.services.oauth2-proxy;
  inherit (config.security) ldap;
in
{
  options.services = {
    dex = {
      discoveryEndpoint = lib.mkOption {
        type = lib.types.str;
        default = "${cfgd.settings.issuer}/.well-known/openid-configuration";
        defaultText = "$''{config.services.dex.settings.issuer}/.well-known/openid-configuration";
        description = "The discover endpoint of dex";
      };
    };

    portunus = {
      # maybe based on $service.ldap.enable && services.portunus.enable?
      addToHosts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to add a hosts entry for the portunus domain pointing to externalIp";
      };

      # only here to fix manual creation
      domain = lib.mkOption {
        default = "";
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
        description = "Whether to set security.ldap to portunus specific settings.";
      };

      oauth2-proxy = {
        configure = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether to configure oauth2-proxy to work together with Dex and Portunus as a backend.

            If Portunus is enabled locally, the oidc client is configured in Dex, otherwise it must be done manually via `services.portunus.dex.oidcClients`.

            Use `services.oauth2-proxy.nginx.virtualHosts` to configure the nginx virtual hosts that should require authentication.
          '';
        };

        clientID = lib.mkOption {
          type = lib.types.str;
          default = "oauth2_proxy";
          description = ''
            The client ID oauth2-proxy will be using.
            `-` is not allowed here, as it makes it impossible to configure the secret securely via an environment variable.
          '';
        };
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

      webDomain = lib.mkOption {
        type = lib.types.str;
        default = "";
        example = "auth.example.com";
        description = "The domain name to connect to, to visit the ldap server web interface and to which to issue cookies to.";
      };
    };
  };

  imports = [
    (lib.mkRenamedOptionModule ["services" "portunus" "configureOAuth2Proxy"] ["services" "portunus" "oauth2-proxy" "configure"])
  ];

  config = {
    assertions = [
      {
        assertion = cfg.oauth2-proxy.configure -> cfgo.keyFile != null;
        message = ''
          Setting services.portunus.configureOAuth2Proxy to true requires to set service.oauth2-proxy.keyFile
          to a file that contains `OAUTH2_PROXY_CLIENT_SECRET` and `OAUTH2_PROXY_COOKIE_SECRET`.
        '';
      }
      {
        assertion = cfg.enable -> lib.versionAtLeast cfg.package.version "2.0.0";
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
        dex-oidc = let
          functionArgs = prev.dex-oidc.override.__functionArgs;
          buildGoModule = if functionArgs?buildGoModule then
            "buildGoModule"
          else if functionArgs?buildGo124Module then
            "buildGo124Module"
          else throw "nixos-modules/portunus/dex: yet another buildGo*Module version...";
        in prev.dex-oidc.override {
          "${buildGoModule}" = args: final."${buildGoModule}" (args // {
            patches = args.patches or [ ] ++ [
              # remember session
              (if (lib.versionAtLeast prev.dex-oidc.version "2.42") then
                ./dex-session-cookie-password-connector-2.42.patch
              else if (lib.versionAtLeast prev.dex-oidc.version "2.41") then
                ./dex-session-cookie-password-connector-2.41.patch
              else if (lib.versionAtLeast prev.dex-oidc.version "2.40") then
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

            vendorHash = if lib.versionAtLeast prev.dex-oidc.version "2.42" then
              "sha256-yBAr1pDhaJChtz8km9eDISc9aU+2JtKhetlS8CbClaE="
            else if lib.versionAtLeast prev.dex-oidc.version "2.41" then
              "sha256-a0F4itrposTBeI1XB0Ru3wBkw2zMBlsMhZUW8PuM1NA="
            else if lib.versionAtLeast prev.dex-oidc.version "2.40" then
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

    services = {
      dex.settings = {
        issuer = lib.mkForce "https://${cfg.webDomain}/dex";
        # the user has no other option to accept this and all clients are internal anyway
        oauth2.skipApprovalScreen = true;
      };

      oauth2-proxy = lib.mkIf cfg.oauth2-proxy.configure {
        enable = true;
        inherit (cfg.oauth2-proxy) clientID;
        # if Portunus is not enabled locally, its domain is most likely wrong
        nginx.domain = lib.mkIf cfg.enable cfg.webDomain;
        provider = "oidc";
        redirectURL = "https://${cfgo.nginx.domain}/oauth2/callback";
        reverseProxy = true;
        upstream = "http://127.0.0.1:4181";
        extraConfig = {
          exclude-logging-path = "/oauth2/static/css/all.min.css,/oauth2/static/css/bulma.min.css";
          oidc-issuer-url = cfgd.settings.issuer;
          provider-display-name = "Portunus";
          # checking for groups requires next to the default scopes also the `groups` scope, otherwise all authentication tries fail
          scope = lib.mkIf (lib.any (x: x.allowed_groups != null) (lib.attrValues cfgo.nginx.virtualHosts)) "openid email profile groups";
        };
      };

      portunus.dex = lib.mkIf (cfg.enable && cfg.oauth2-proxy.configure) {
        enable = true;
        oidcClients = [{
          callbackURL = cfgo.redirectURL;
          id = cfg.oauth2-proxy.clientID;
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

    systemd.services = lib.mkIf cfg.oauth2-proxy.configure {
      oauth2-proxy.serviceConfig = {
         requires = [ "network-online.target" ];
         after = [ "network-online.target" ];
       };
    };
  };
}
