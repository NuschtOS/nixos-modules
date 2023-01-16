{ config, lib, options, ... }:

let
  cfg = config.services.hydra;
  inherit (config.security) ldap;
in
{
  options = {
    services.hydra.ldap = {
      enable = lib.mkEnableOption (lib.mdDoc "LDAP login");

      roleMappings = lib.mkOption {
        type = with lib.types; listOf (attrsOf str);
        example = [{ hydra-admins = "admins"; }];
        default = [ ];
        description = lib.mdDoc "LDAP";
      };
    };
  };

  config = lib.mkIf cfg.ldap.enable {
    services.hydra.extraConfig = ''
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
            ldap_server = "${ldap.server}"
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
            user_filter = "${ldap.userFilter}"
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
          ${lib.concatStringsSep "\n" (lib.concatMap (lib.mapAttrsToList (name: value: "${name} = ${value}")) cfg.ldap.roleMappings)}
        </role_mapping>
      </ldap>
    '';
  };
}
