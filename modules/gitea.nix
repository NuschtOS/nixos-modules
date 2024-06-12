{ config, lib, libS, ... }:

let
  cfg = config.services.gitea;
  cfgl = cfg.ldap;
  cfgo = cfg.oidc;
  inherit (config.security) ldap;

  mkOptStr = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
  };
  mkOptBool = lib.mkOption {
    type = lib.types.bool;
    default = false;
  };
in
{
  options = {
    services.gitea = {
      # based on https://github.com/majewsky/nixos-modules/blob/master/gitea.nix
      ldap = {
        enable = lib.mkEnableOption "login via ldap";

        adminGroup = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "gitea-admins";
          description = "Name of the ldap group that grants admin access in gitea.";
        };

        searchUserPasswordFile = lib.mkOption {
          type = with lib.types; nullOr str;
          example = "/var/lib/secrets/search-user-password";
          description = "Path to a file containing the password for the search/bind user.";
        };

        userGroup = libS.ldap.mkUserGroupOption;

        options = {
          id = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 1;
          };
          name = lib.mkOption {
            type = lib.types.str;
          };
          security-protocol = mkOptStr;
          host = mkOptStr;
          port = lib.mkOption {
            type = lib.types.port;
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
          avatar-attribute = mkOptStr;
          # TODO: enable LDAP groups
          page-size = lib.mkOption {
            type  = lib.types.ints.unsigned;
            default = 0;
          };
          attributes-in-bind = mkOptBool;
          skip-local-2fa = mkOptBool;
          allow-deactivate-all = mkOptBool;
          synchronize-users = mkOptBool;
        };
      };

      oidc = {
        enable = lib.mkEnableOption "login via OIDC through Dex and Portunus";

        clientSecretFile = lib.mkOption {
          type = with lib.types; nullOr str;
          example = "/var/lib/secrets/search-user-password";
          description = "Path to a file containing the password for the search/bind user.";
        };

        options = {
          id = lib.mkOption {
            type = lib.types.ints.unsigned;
            default = 2;
          };
          name = lib.mkOption {
            type = lib.types.str;
          };
          provider = mkOptStr;
          key = mkOptStr;
          secret = mkOptStr;
          icon-url = mkOptStr;
          auto-discover-url = mkOptStr;
          skip-local-2fa = mkOptBool;
          scopes = mkOptStr;
          required-claim-name = mkOptStr;
          required-claim-value = mkOptStr;
          group-claim-name = mkOptStr;
          admin-group = mkOptStr;
          restricted-group = mkOptStr;
          group-team-map = mkOptStr;
          group-team-map-removal = mkOptBool;
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
    };
  };

  imports = [
    (lib.mkRenamedOptionModule [ "services" "gitea" "ldap" "bindPasswordFile" ] [ "services" "gitea" "ldap" "searchUserPasswordFile" ])
  ];

  config.services.gitea = lib.mkIf cfg.enable {
    ldap.options = lib.mkIf cfgl.enable {
      name = "ldap";
      security-protocol = "LDAPS";
      host = ldap.domainName;
      inherit (ldap) port;
      bind-dn = ldap.bindDN;
      bind-password = "$(cat ${cfgl.searchUserPasswordFile})";
      user-search-base = ldap.userBaseDN;
      user-filter = ldap.searchFilterWithGroupFilter cfgl.userGroup (ldap.userFilter "%[1]s");
      admin-filter = ldap.groupFilter cfgl.adminGroup;
      username-attribute = ldap.userField;
      firstname-attribute = ldap.givenNameField;
      surname-attribute = ldap.surnameField;
      email-attribute = ldap.mailField;
      public-ssh-key-attribute = ldap.sshPublicKeyField;
      attributes-in-bind = true;
      synchronize-users = true;
    };

    oidc.options = lib.mkIf cfgo.enable {
      name = "dex";
      provider = "openidConnect";
      key = "gitea";
      secret = "$(cat ${cfgo.clientSecretFile})";
      icon-url = "${config.services.dex.settings.issuer}/theme/favicon.png";
      auto-discover-url = "${config.services.dex.settings.issuer}/.well-known/openid-configuration";
      group-claim-name = "groups";
      admin-group = "gitea-admins";
      restricted-group = "gitea-users";
    };

    settings = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
      cors = {
        ALLOW_DOMAIN = cfg.settings.server.DOMAIN;
        ENABLED = true;
      };
      cron.ENABLED = true;
      "cron.archive_cleanup" = {
        SCHEDULE = "@every 3h";
        OLDER_THAN = "6h";
      };
      "cron.delete_old_actions".ENABLED = true;
      "cron.delete_old_system_notices".ENABLED = true;
      other.SHOW_FOOTER_VERSION = false;
      repository.ACCESS_CONTROL_ALLOW_ORIGIN = cfg.settings.server.DOMAIN;
      "repository.signing".DEFAULT_TRUST_MODEL = "committer";
      security.DISABLE_GIT_HOOKS = true;
      server = {
        ENABLE_GZIP = true;
        # The description of this setting is wrong and it doesn't control any CDN functionality but acts just as an override to the avatar federation.
        # see https://github.com/go-gitea/gitea/issues/31112
        OFFLINE_MODE = false;
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

  config.services.portunus.dex = lib.mkIf cfg.oidc.enable {
    enable = true;
    oidcClients = [{
      callbackURL = "https://${cfg.settings.server.DOMAIN}/user/oauth2/${cfgo.options.name}/callback";
      id = "gitea";
    }];
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

  config.systemd.services = lib.mkIf (cfg.enable && (cfgl.enable || cfgo.enable)) {
    gitea.preStart =
      let
        exe = lib.getExe cfg.package;
        # Return the option as an argument except if it is null or a special boolean type, then look if the value is truthy.
        # Also escape it unless it is going to execute shellcode.
        formatOption = key: value: if (value == null) then ""
          else if (builtins.isBool value) then (lib.optionalString value "--${key}")
          # allow executing shell after the --bind-password argument to e.g. cat a password file
          else "--${key} ${(if (key == "bind-password" || key == "secret") then value else lib.escapeShellArg value)}";
        optionsStr = opt: lib.concatStringsSep " " (lib.mapAttrsToList formatOption opt);
      in
      lib.mkAfter (lib.optionalString cfgl.enable ''
        if ${exe} admin auth list | grep -q ${cfgl.options.name}; then
          ${exe} admin auth update-ldap ${optionsStr cfgl.options}
        else
          ${exe} admin auth add-ldap ${optionsStr (lib.filterAttrs (name: _: name != "id") cfgl.options)}
        fi
      '' + lib.optionalString cfgo.enable ''
        if ${exe} admin auth list | grep -q ${cfgo.options.name}; then
          ${exe} admin auth update-oauth ${optionsStr cfgo.options}
        else
          ${exe} admin auth add-oauth ${optionsStr (lib.filterAttrs (name: _: name != "id") cfgo.options)}
        fi
      '');
  };
}
