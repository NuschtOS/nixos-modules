{ config, lib, ... }:

let
  cfg = config.services.hedgedoc;
  inherit (config.security) ldap;
in
{
  options = {
    services.hedgedoc.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc ''
        login only via LDAP.
        Use `service.hedgedoc.environmentFile` in format `bindCredentials=password` to set the credentials used by the search user
      '');
    };
  };

  config = lib.mkIf cfg.ldap.enable {
    services.hedgedoc.settings.ldap = {
      url = "ldaps://${ldap.domainName}:${toString ldap.port}";
      bindDn = ldap.bindDN;
      bindCredentials = "$bindCredentials";
      searchBase = ldap.userBaseDN;
      searchFilter = ldap.userFilter "{{username}}";
      tlsca = "/etc/ssl/certs/ca-certificates.crt";
      useridField = ldap.userField;
    };
  };
}
