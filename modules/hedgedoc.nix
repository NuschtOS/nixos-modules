{ config, lib, libS, ... }:

let
  cfg = config.services.hedgedoc.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.hedgedoc.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc ''
        login only via LDAP.
        Use `service.hedgedoc.environmentFile` in format `bindCredentials=password` to set the credentials used by the search user
      '');

      userGroup = libS.ldap.mkUserGroupOption;
    };
  };

  config.services.hedgedoc.settings.ldap = lib.mkIf cfg.enable {
    url = "ldaps://${ldap.domainName}:${toString ldap.port}";
    bindDn = ldap.bindDN;
    bindCredentials = "$bindCredentials";
    searchBase = ldap.userBaseDN;
    searchFilter = ldap.searchFilterWithGroupFilter cfg.userGroup (ldap.userFilter "{{username}}");
    tlsca = "/etc/ssl/certs/ca-certificates.crt";
    useridField = ldap.userField;
  };

  config.services.portunus.seedSettings.groups = lib.optional (cfg.userGroup != null) {
    long_name = "Hedgedoc Users";
    name = cfg.userGroup;
    permissions = {};
  };
}
