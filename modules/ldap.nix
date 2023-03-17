{ config, lib, ... }:

let
  cfg = config.security.ldap;
  inherit (config.services) portunus;
in
{
  options.security.ldap = lib.mkOption {
    type = lib.types.submodule {
      options = {
        bindDN = lib.mkOption {
          type = lib.types.str;
          example = "uid=search";
          default = "uid=${cfg.searchUID}";
          apply = s: s + "," + cfg.userBaseDN;
          description = lib.mdDoc ''
            The DN of the service user used by services.
            The user base dn will be automatically appended.
          '';
        };

        domainComponent = lib.mkOption {
          type = with lib.types; listOf str;
          example = [ "example" "com" ];
          apply = dc: lib.removeSuffix "," (lib.concatMapStrings (x: "dc=${x},") dc);
          description = lib.mdDoc ''
            Domain component(s) (dc) represented as a list of strings.

            Each entry will be prefixed with `dc=` and all are concatinated with `,`, except the last one.
            The example would be concatinated to `dc=example,dc=com`
          '';
        };

        roleBaseDN = lib.mkOption {
          type = lib.types.str;
          example = "ou=groups";
          apply = s: s + "," + cfg.domainComponent;
          description = lib.mdDoc ''
            The directory path where applications should search for users.
            Domain component will be automatically appended.
          '';
        };

        roleField = lib.mkOption {
          type = lib.types.str;
          example = "cn";
          description = lib.mdDoc "The attribute where the user account is listed in a group.";
        };

        roleFilter = lib.mkOption {
          type = lib.types.str;
          example = "(&(objectclass=groupOfNames)(member=%s))";
          description = lib.mdDoc "Filter to get the groups of an user object.";
        };

        roleValue = lib.mkOption {
          type = lib.types.str;
          example = "dn";
          description = lib.mdDoc "The attribute of the user object where to find its distinguished name.";
        };

        searchUID = lib.mkOption {
          type = lib.types.str;
          example = "search";
          description = lib.mdDoc "The uid of the service user used by services, often referred as search user.";
        };

        server = lib.mkOption {
          type = lib.types.str;
          example = "auth.example.com";
          description = lib.mdDoc "The DNS name to connect to the ldap server.";
        };

        userBaseDN = lib.mkOption {
          type = lib.types.str;
          example = "ou=users";
          apply = s: s + "," + cfg.domainComponent;
          description = lib.mdDoc ''
            The directory path where applications should search for users.
            Domain component will be automatically appended.
          '';
        };

        userField = lib.mkOption {
          type = lib.types.str;
          example = "uid";
          description = lib.mdDoc "The attribute of the user object where to find its username.";
        };

        # TODO: allow email and user login for double bind?
        # (|(uid=%s)(mail=%s))
        userFilter = lib.mkOption {
          type = lib.types.str;
          example = "(&(objectclass=person)(uid=%s))";
          description = lib.mdDoc "Filter User search filter";
        };
      };
    };
    default = { };
    description = "LDAP options used in other services.";
  };
}
