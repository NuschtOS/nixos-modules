{ config, lib, ... }:

let
  cfg = config.services.portunus;
in
{
  options.services.portunus = {
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

    security.ldap = lib.mkIf cfg.ldapPreset {
      domainName = cfg.domain;
      givenNameField = "givenName";
      mailField = "mail";
      port = 636;
      roleBaseDN = "ou=groups";
      roleField = "cn";
      roleFilter = "(&(objectclass=groupOfNames)(member=%s))";
      roleValue = "dn";
      searchUID = "search";
      surnameField = "sn";
      userField = "uid";
      # TODO: add enum setting for login with username, email or both
      # userFilter = "(&(objectclass=person)(|(uid=%s)(mail=%s)))";
      userFilter = "(&(objectclass=person)(uid=%s))";
      userBaseDN = "ou=users";
    };
  };
}
