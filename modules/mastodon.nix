{ config, lib, ... }:

let
  cfg = config.services.mastodon.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.mastodon.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc "login only via LDAP");

      userFilterGroup = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        description = lib.mdDoc "Restrict logins to users in this group";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.mastodon.extraConfig = {
      LDAP_ENABLED = "true";
      LDAP_BASE = ldap.userBaseDN;
      LDAP_BIND_DN = ldap.bindDN;
      LDAP_HOST = ldap.domainName;
      LDAP_METHOD = "simple_tls";
      LDAP_PORT = toString ldap.port;
      LDAP_UID = ldap.userField;
      # convert .,- (space) in LDAP usernames to underscore, otherwise those users cannot log in
      LDAP_UID_CONVERSION_ENABLED = "true";
    } // lib.optionalAttrs (cfg.userFilterGroup != null) {
      LDAP_SEARCH_FILTER = "(&${ldap.groupFilter cfg.userFilterGroup}(|(%{uid}=%{email})(%{mail}=%{email})))";
    };
  };
}
