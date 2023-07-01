{ config, lib, ... }:

let
  cfg = config.security.ldap;
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

        domainName = lib.mkOption {
          type = lib.types.str;
          example = "auth.example.com";
          description = lib.mdDoc "The domain name to connect to the ldap server.";
        };

        givenNameField = lib.mkOption {
          type = lib.types.str;
          example = "givenName";
          description = lib.mdDoc "The attribute of the user object where to find its given name.";
        };

        groupFilter = lib.mkOption {
          type = with lib.types; functionTo str;
          example = lib.literalExpression ''group: "(&(objectclass=person)(isMemberOf=cn=''${group},''${config.security.ldap.roleBaseDN}"'';
          description = lib.mdDoc "A function that returns a group filter that matches the first argument against the names of the groups the user is part of.";
        };

        mailField = lib.mkOption {
          type = lib.types.str;
          example = "mail";
          description = lib.mdDoc "The attribute of the user object where to find its email.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          example = "636";
          description = lib.mdDoc "The port the ldap server listens on. Usually this is 389 for ldap and 636 for ldaps.";
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

        searchFilterWithGroupFilter = lib.mkOption {
          type = with lib.types; functionTo (functionTo str);
          example = lib.literalExpression ''userFilterGroup: userFilter: if (userFilterGroup != null) then "(&''${config.security.ldap.groupFilter userFilterGroup})" else userFilter'';
          description = lib.mdDoc ''
            A function that returns a search filter that may include a group filter.
            The first argument may be the group that is filtered upon or null.
            If set to null no additional filtering is done. If set the supplied filter is combined with the user filter.
            The second argument must be the user filter including the applications placeholders or ideally the userFilter option.
          '';
        };

        sshPublicKeyField = lib.mkOption {
          type = lib.types.str;
          example = "sshPublicKey";
          description = lib.mdDoc "The attribute of the user object where to find its ssh public key.";
        };

        surnameField = lib.mkOption {
          type = lib.types.str;
          example = "sn";
          description = lib.mdDoc "The attribute of the user object where to find its surname.";
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

        userFilter = lib.mkOption {
          type = with lib.types; functionTo str;
          example = ''param: "(&(objectclass=person)(|(uid=''${param})(mail=''${param})))"'';
          description = lib.mdDoc "A function that returns a user search filter that uses the first argument as the placeholder.";
        };
      };
    };
    default = { };
    description = "LDAP options used in other services.";
  };
}
