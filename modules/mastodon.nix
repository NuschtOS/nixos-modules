{ config, lib, ... }:

let
  cfg = config.services.mastodon;
  inherit (config.security) ldap;
in
{
  options = {
    services.mastodon.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc "login only via LDAP");
    };
  };

  config = lib.mkIf cfg.ldap.enable {
    services.mastodon.extraConfig = {
      LDAP_ENABLED = "true";
      LDAP_BASE = ldap.userBaseDN;
      LDAP_BIND_DN = ldap.bindDN;
      LDAP_HOST = ldap.domainName;
      LDAP_METHOD = "simple_tls";
      LDAP_PORT = toString ldap.port;
      # TODO: use security.ldap.userFilter
      LDAP_SEARCH_FILTER = "(&${ldap.groupFilter "mastodon"}(|(%{uid}=%{email})(%{mail}=%{email})))";
      LDAP_UID = ldap.userField;
      # convert .,- (space) in LDAP usernames to underscore, otherwise those users cannot log in
      LDAP_UID_CONVERSION_ENABLED = "true";
    };
  };
}
