{ config, lib, ... }:

let
  cfg = config.services.portunus;
in
{
  options.services.portunus = {
    addToHosts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Wether to add a hosts entry for the portunus domain pointing to externalIp";
    };

    externalIp4 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv4 of portunus instance. This is used in the addToHosts option.";
    };

    externalIp6 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv6 of portunus instance. This is used in the addToHosts option.";
    };

    ldapPreset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc ''
        Wether to set config.security.ldap to portunus specific settings.
      '';
    };
  };

  config = {
    networking.hosts = lib.mkIf cfg.addToHosts {
      ${cfg.externalIp4} = [ cfg.domain ];
      ${cfg.externalIp6} = [ cfg.domain ];
    };

    security.ldap = lib.mkIf cfg.ldapPreset {
      roleBaseDN = "ou=groups";
      roleField = "cn";
      roleFilter = "(&(objectclass=groupOfNames)(member=%s))";
      roleValue = "dn";
      searchUID = "search";
      server = cfg.domain;
      userField = "uid";
      # TODO: add enum setting for login with username, email or both
      # userFilter = "(&(objectclass=person)(|(uid=%s)(mail=%s)))";
      userFilter = "(&(objectclass=person)(uid=%s))";
      userBaseDN = "ou=users";
    };
  };
}
