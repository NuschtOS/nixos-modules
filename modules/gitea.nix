{ config, lib, libS, ... }:

let
  cfg = config.services.gitea;
  cfgl = cfg.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.gitea = {
      # based on https://github.com/majewsky/nixos-modules/blob/master/gitea.nix
      ldap = {
        enable = lib.mkEnableOption (lib.mdDoc "login via ldap");

        adminGroup = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "gitea-admins";
          description = lib.mdDoc "Name of the ldap group that grants admin access in gitea.";
        };

        bindPasswordFile = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "/var/lib/secrets/bind-password";
          description = lib.mdDoc "Path to a file containing the bind password.";
        };

        userGroup = libS.ldap.mkUserGroupOption;

        options =
          let
            mkOptStr = lib.mkOption {
              type = with lib.types; nullOr str;
              default = null;
            };
          in
          {
            id = lib.mkOption {
              type = lib.types.ints.unsigned;
              default = 1;
            };
            name = mkOptStr;
            security-protocol = mkOptStr;
            host = mkOptStr;
            port = lib.mkOption {
              type = with lib.types; nullOr port;
              default = null;
            };
            bind-dn = mkOptStr;
            bind-password = mkOptStr;
            user-search-base = mkOptStr;
            user-filter = mkOptStr;
            admin-filter = mkOptStr;
            username-attribute = mkOptStr;
            firstname-attribute = mkOptStr;
            surname-attribute = mkOptStr;
            email-attribute = mkOptStr;
            public-ssh-key-attribute = mkOptStr;
          };
      };
      recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
    };
  };

  config.services.gitea = lib.mkIf (cfg.enable && cfgl.enable) {
    ldap.options = {
      name = "ldap";
      security-protocol = "LDAPS";
      host = ldap.domainName;
      inherit (ldap) port;
      bind-dn = ldap.bindDN;
      bind-password = "$(cat ${cfgl.bindPasswordFile})";
      user-search-base = ldap.userBaseDN;
      user-filter = ldap.searchFilterWithGroupFilter cfgl.userGroup (ldap.userFilter "%[1]s");
      admin-filter = ldap.groupFilter cfgl.adminGroup;
      username-attribute = ldap.userField;
      firstname-attribute = ldap.givenNameField;
      surname-attribute = ldap.surnameField;
      email-attribute = ldap.mailField;
      public-ssh-key-attribute = ldap.sshPublicKeyField;
    };
    settings = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
      cors = {
        ALLOW_DOMAIN = cfg.settings.server.DOMAIN;
        ENABLED = true;
        SCHEME = "https";
      };
      cron.ENABLED = true;
      "cron.resync_all_sshkeys".ENABLED = true;
      "cron.resync_all_hooks".ENABLED = true;
      other.SHOW_FOOTER_VERSION = false;
      repository.ACCESS_CONTROL_ALLOW_ORIGIN = cfg.settings.server.DOMAIN;
      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
      security.DISABLE_GIT_HOOKS = true;
      server = {
        ENABLE_GZIP = true;
        ROOT_URL = "https://${cfg.settings.server.DOMAIN}/";
        SSH_SERVER_CIPHERS = "chacha20-poly1305@openssh.com, aes256-gcm@openssh.com, aes128-gcm@openssh.com";
        SSH_SERVER_KEY_EXCHANGES = "curve25519-sha256@libssh.org, ecdh-sha2-nistp521, ecdh-sha2-nistp384, ecdh-sha2-nistp256, diffie-hellman-group14-sha1";
        SSH_SERVER_MACS = "hmac-sha2-256-etm@openssh.com, hmac-sha2-256, hmac-sha1";
      };
      session = {
        COOKIE_SECURE = true;
        PROVIDER = "db";
        SAME_SITE = "strict";
        SESSION_LIFE_TIME = 28 * 86400; # 28 days
      };
      "ssh.minimum_key_sizes" = {
        ECDSA = -1;
        RSA = 4095;
      };
      time.DEFAULT_UI_LOCATION = config.time.timeZone;
    });
  };

  config.systemd.services = lib.mkIf (cfg.enable && cfgl.enable) {
    gitea.preStart =
      let
        exe = lib.getExe cfg.package;
        # allow executing shell after the --bind-password argument to e.g. cat a password file
        formatOption = key: value: "--${key} ${if key == "bind-password" then value else lib.escapeShellArg value}";
        ldapOptionsStr = opt: lib.concatStringsSep " " (lib.mapAttrsToList formatOption opt);
        commonArgs = "--attributes-in-bind --synchronize-users";
      in
      lib.mkAfter ''
        if ${exe} admin auth list | grep -q ${cfgl.options.name}; then
          ${exe} admin auth update-ldap ${commonArgs} ${ldapOptionsStr cfgl.options}
        else
          ${exe} admin auth add-ldap ${commonArgs} ${ldapOptionsStr (lib.filterAttrs (name: _: name != "id") cfgl.options)}
        fi
      '';
  };

  config.services.portunus.seedSettings.groups = [
    (lib.mkIf (cfgl.adminGroup != null) {
      long_name = "Gitea Administrators";
      name = cfgl.adminGroup;
      permissions = { };
    })
    (lib.mkIf (cfgl.userGroup != null) {
      long_name = "Gitea Users";
      name = cfgl.userGroup;
      permissions = { };
    })
  ];
}
