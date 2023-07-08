{ config, lib, pkgs, ... }:

let
  cfg = config.services.portunus;
  inherit (config.security) ldap;
in
{
  options.services.portunus = {
    # TODO: how to automatically set this?
    # maybe based on $service.ldap.enable && services.portunus.enable?
    addToHosts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to add a hosts entry for the portunus domain pointing to externalIp";
    };

    internalIp4 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv4 of portunus instance. This is used in the addToHosts option.";
    };

    internalIp6 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv6 of portunus instance. This is used in the addToHosts option.";
    };

    ldapPreset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Whether to set config.security.ldap to portunus specific settings.";
    };

    removeAddGroup = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "When enabled, remove the function to add new Groups via the web ui, to enforce seeding usage.";
    };

    seedGroups = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Wether to seed groups configured in services as not member managed groups.";
    };

    # TODO: upstream to nixos
    seedSettings = lib.mkOption {
      type = with lib.types; nullOr (attrsOf (listOf (attrsOf anything)));
      default = null;
      description = lib.mdDoc ''
        Seed settings for users and grousp.
        See upstream for format <https://github.com/majewsky/portunus#seeding-users-and-groups-from-static-configuration>
      '';
    };
  };

  config = {
    networking.hosts = lib.mkIf cfg.addToHosts {
      ${cfg.internalIp4} = [ cfg.domain ];
      ${cfg.internalIp6} = [ cfg.domain ];
    };

    nixpkgs.overlays = [
      (final: prev: with final; {
        portunus = prev.portunus.overrideAttrs ({ patches ? [ ], ... }: {
          src = fetchFromGitHub {
            owner = "majewsky";
            repo = "portunus";
            rev = "8bad0661ecca9276991447f8e585c20c450ad57a";
            hash = "sha256-59AvNWhnsvtrVmAJRcHeNOYOlHCx1ZZSqwFvyAM+Ye8=";
          };

          patches = patches
          ++ lib.optional cfg.removeAddGroup ./portunus-remove-add-group.diff
          ++ [
            # display errors when editing seeded groups/users
            # https://github.com/majewsky/portunus/pull/17
            (fetchpatch {
              url = "https://github.com/majewsky/portunus/commit/9999994e6b90e20405944767fb7d225914c2303b.patch";
              sha256 = "sha256-IEQpWnG3ZekZ+QCEzSZcbMQe6iEalOhDz3qNbjDgg/A=";
            })
            # add option to not seed group members
            # https://github.com/majewsky/portunus/pull/18
            (fetchpatch {
              url = "https://github.com/majewsky/portunus/commit/faff1294378dfb123985d3250e305bbbf278437b.patch";
              sha256 = "sha256-BCB5zaXCbCnBMmlce64gqaXPh2ZnaeeQfNehqwXfiDI=";
            })
          ];
        });
      })
    ];

    services.portunus.seedPath = pkgs.writeText "seed.json" (builtins.toJSON cfg.seedSettings);

    security.ldap = lib.mkIf cfg.ldapPreset {
      domainName = cfg.domain;
      givenNameField = "givenName";
      groupFilter = group: "(&(objectclass=person)(isMemberOf=cn=${group},${ldap.roleBaseDN}))";
      mailField = "mail";
      port = 636;
      roleBaseDN = "ou=groups";
      roleField = "cn";
      roleFilter = "(&(objectclass=groupOfNames)(member=%s))";
      roleValue = "dn";
      searchFilterWithGroupFilter = userFilterGroup: userFilter: if (userFilterGroup != null) then "(&${ldap.groupFilter userFilterGroup}${userFilter})" else userFilter;
      sshPublicKeyField = "sshPublicKey";
      searchUID = "search";
      surnameField = "sn";
      userField = "uid";
      userFilter = replaceStr: "(&(objectclass=person)(|(uid=${replaceStr})(mail=${replaceStr})))";
      userBaseDN = "ou=users";
    };
  };
}
