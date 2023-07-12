{ config, lib, libS, ... }:

let
  cfg = config.services.hydra.ldap;
  inherit (config.security) ldap;
in
{
  options = {
    services.hydra.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc ''
        login only via LDAP.
        The bind user password must be placed at `/var/lib/hydra/ldap-password.conf` in the format `bindpw = "PASSWORD"
        It is recommended to use a password without special characters because the perl config parser has weird escaping rule like that comment characters `#` must be escape with backslash
      '');

      roleMappings = lib.mkOption {
        type = with lib.types; listOf (attrsOf str);
        example = [{ hydra-admins = "admins"; }];
        default = [ ];
        description = lib.mdDoc "Map LDAP groups to hydra permissions. See upstream doc, especially role_mapping.";
      };

      userGroup = libS.ldap.mkUserGroupOption;
    };
  };

  config.services.hydra.extraConfig = lib.mkIf cfg.enable /* xml */ ''
    # https://hydra.nixos.org/build/196107287/download/1/hydra/configuration.html#using-ldap-as-authentication-backend-optional
    <ldap>
      <config>
        <credential>
          class = Password
          password_field = password
          password_type = self_check
        </credential>
        <store>
          class = LDAP
          ldap_server = "${ldap.domainName}"
          <ldap_server_options>
            scheme = ldaps
            timeout = 10
          </ldap_server_options>
          binddn = "${ldap.bindDN}"
          include ldap-password.conf
          start_tls = 0
          <start_tls_options>
            ciphers = TLS_AES_256_GCM_SHA384
            sslversion = tlsv1_3
          </start_tls_options>
          user_basedn = "${ldap.userBaseDN}"
          user_filter = "${ldap.searchFilterWithGroupFilter cfg.userGroup (ldap.userFilter "%s")}"
          user_scope = one
          user_field = ${ldap.userField}
          <user_search_options>
            deref = always
          </user_search_options>
          # Important for role mappings to work:
          use_roles = 1
          role_basedn = "${ldap.roleBaseDN}"
          role_filter = "${ldap.roleFilter}"
          role_scope = one
          role_field = ${ldap.roleField}
          role_value = ${ldap.roleValue}
          <role_search_options>
            deref = always
          </role_search_options>
        </store>
      </config>
      <role_mapping>
        # Make all users in the hydra-admin group Hydra admins
        # hydra-admins = admin
        # Allow all users in the dev group to restart jobs and cancel builds
        # dev = restart-jobs
        # dev = cancel-build
        ${lib.concatStringsSep "\n" (lib.concatMap (lib.mapAttrsToList (name: value: "${name} = ${value}")) cfg.roleMappings)}
      </role_mapping>
    </ldap>
  '';

  config.services.portunus.seedSettings.groups = [
    (lib.mkIf (cfg.userGroup != null) {
      long_name = "Hydra Users";
      name = cfg.userGroup;
      permissions = { };
    })
  ] ++ lib.flatten (map lib.attrValues (map (lib.mapAttrs (ldapGroup: _: {
    long_name = "Hydra Role ${ldapGroup}";
    name = ldapGroup;
    permissions = { };
  })) cfg.roleMappings));
}
