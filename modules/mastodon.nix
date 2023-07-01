{ config, lib, libS, ... }:

let
  cfg = config.services.mastodon.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.mastodon.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc "login only via LDAP");

      userGroup = libS.ldap.mkUserGroupOption;
    };
  };

  config.services.mastodon.extraConfig = lib.mkIf cfg.enable {
    LDAP_ENABLED = "true";
    LDAP_BASE = ldap.userBaseDN;
    LDAP_BIND_DN = ldap.bindDN;
    LDAP_HOST = ldap.domainName;
    LDAP_METHOD = "simple_tls";
    LDAP_PORT = toString ldap.port;
    LDAP_UID = ldap.userField;
    # convert .,- (space) in LDAP usernames to underscore, otherwise those users cannot log in
    LDAP_UID_CONVERSION_ENABLED = "true";
    LDAP_SEARCH_FILTER = ldap.searchFilterWithGroupFilter cfg.userGroup "(|(%{uid}=%{email})(%{mail}=%{email}))";
  };

  config.services.portunus.seedSettings.groups = lib.optional (cfg.userGroup != null) {
    long_name = "Mastodon Users";
    name = cfg.userGroup;
    dont_manage_members = true;
    permissions = {};
  };
}
