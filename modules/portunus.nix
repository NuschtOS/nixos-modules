{ config, lib, ... }:

let
  cfg = config.services.portunus;
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
  };

  config = {
    networking.hosts = lib.mkIf cfg.addToHosts {
      ${cfg.internalIp4} = [ cfg.domain ];
      ${cfg.internalIp6} = [ cfg.domain ];
    };

    nixpkgs.overlays = [
      (final: prev: with final; {
        portunus = prev.portunus.overrideAttrs ({ patches ? [ ], ... }: {
          patches = patches ++ [
            # allow editing members of groups
            (fetchpatch {
              url = "https://github.com/majewsky/portunus/commit/70ebf6abf944f3b5064169a2ac9d5f2ddcc7b58c.patch";
              sha256 = "sha256-fZzOuJ6K1NXJHWvOfSIU5FAfL0dVK7b7dhhtb6yuCGE=";
            })
            # fix creating new groups with members
          ];
        });
      })
    ];

    security.ldap = lib.mkIf cfg.ldapPreset {
      domainName = cfg.domain;
      givenNameField = "givenName";
      groupFilter = group: "(&(objectclass=person)(isMemberOf=cn=${group},${config.security.ldap.roleBaseDN}))";
      mailField = "mail";
      port = 636;
      roleBaseDN = "ou=groups";
      roleField = "cn";
      roleFilter = "(&(objectclass=groupOfNames)(member=%s))";
      roleValue = "dn";
      sshPublicKeyField = "sshPublicKey";
      searchUID = "search";
      surnameField = "sn";
      userField = "uid";
      userFilter = param: "(&(objectclass=person)(|(uid=${param})(mail=${param})))";
      userBaseDN = "ou=users";
    };
  };
}
