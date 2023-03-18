{ config, lib, libS, ... }:

let
  cfg = config.services.gitea;
  cfgl = cfg.ldap.options;
  inherit (config.security) ldap;
in
{
  options = {
    services.gitea = {
      # based on https://github.com/majewsky/nixos-modules/blob/master/gitea.nix
      ldap = {
        enable = lib.mkEnableOption (lib.mdDoc "login via ldap");

        adminGroup = lib.mkOption {
          type = lib.types.str;
          example = "gitea-admins";
          description = lib.mdDoc "Name of the ldap group that grants admin access in gitea.";
        };

        bindPasswordFile = lib.mkOption {
          type = lib.types.str;
          example = "/var/lib/secrets/bind-password";
          description = lib.mdDoc "Path to a file containing the bind password.";
        };

        options = let
          mkOptStr = default: lib.mkOption {
            type = lib.types.str;
            inherit default;
          };
        in {
          id = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1;
          };
          name = mkOptStr "ldap";
          security-protocol = mkOptStr "LDAPS";
          host = mkOptStr ldap.domainName;
          port = lib.mkOption {
            type = lib.types.port;
            default = ldap.port;
          };
          bind-dn = mkOptStr ldap.bindDN;
          bind-password = mkOptStr "$(cat ${cfg.ldap.bindPasswordFile})";
          user-search-base = mkOptStr ldap.userBaseDN;
          user-filter = mkOptStr (ldap.userFilter "%[1]s");
          admin-filter = mkOptStr (ldap.groupFilter cfg.ldap.adminGroup);
          username-attribute = mkOptStr ldap.userField;
          firstname-attribute = mkOptStr ldap.givenNameField;
          surname-attribute = mkOptStr ldap.surnameField;
          email-attribute = mkOptStr ldap.mailField;
          public-ssh-key-attribute = mkOptStr ldap.sshPublicKeyField;
        };
      };
      recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services.gitea = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
      rootUrl = "https://${config.services.gitea.domain}/";
      settings = {
        cors = {
          ALLOW_DOMAIN = config.services.gitea.domain;
          ENABLED = true;
          SCHEME = "https";
        };
        other.SHOW_FOOTER_VERSION = false;
        repository.ACCESS_CONTROL_ALLOW_ORIGIN = config.services.gitea.domain;
        server = {
          ENABLE_GZIP = true;
          SSH_SERVER_CIPHERS = "chacha20-poly1305@openssh.com, aes256-gcm@openssh.com, aes128-gcm@openssh.com";
          SSH_SERVER_KEY_EXCHANGES = "curve25519-sha256@libssh.org, ecdh-sha2-nistp521, ecdh-sha2-nistp384, ecdh-sha2-nistp256, diffie-hellman-group14-sha1";
          SSH_SERVER_MACS = "hmac-sha2-256-etm@openssh.com, hmac-sha2-256, hmac-sha1";
        };
        session = {
          COOKIE_SECURE = true;
          PROVIDER = "db";
          SAME_SITE = "strict";
          SESSION_LIFE_TIME = 604800; # 7 days
        };
        "ssh.minimum_key_sizes" = {
          ECDSA = -1;
          RSA = 4095;
        };
        time.DEFAULT_UI_LOCATION = config.time.timeZone;
        update_checker.ENABLED = false;
      };
    });

    systemd.services.gitea.preStart = let
      exe = lib.getExe cfg.package;
      # allow executing shell after the --bind-password argument to e.g. cat a password file
      formatOption = key: value: "--${key} ${if key == "bind-password" then value else lib.escapeShellArg value}";
      ldapOptionsStr = opt: lib.concatStringsSep " " (lib.mapAttrsToList formatOption opt);
      commonArgs = "--attributes-in-bind --synchronize-users";
    in lib.mkIf cfg.ldap.enable (lib.mkAfter ''
      if ${exe} admin auth list | grep -q ${cfgl.name}; then
        ${exe} admin auth update-ldap ${commonArgs} ${ldapOptionsStr cfgl}
      else
        ${exe} admin auth add-ldap ${commonArgs} ${ldapOptionsStr (lib.filterAttrs (name: value: name != "id") cfgl)}
      fi
    '');
  };
}
