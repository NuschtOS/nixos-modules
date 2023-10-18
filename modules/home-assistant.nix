{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.home-assistant;
  inherit (config.security) ldap;
in
{
  options = {
    services.home-assistant = {
      ldap = {
        enable = lib.mkEnableOption (lib.mdDoc ''login only via LDAP

          ::: {.note}
          Only enable this after completing the onboarding!
          :::
        '');
        userGroup = libS.ldap.mkUserGroupOption;
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config.services.home-assistant = lib.mkMerge [
    (lib.mkIf cfg.recommendedDefaults {
      config = {
        default_config = { }; # yes, this is required...
        homeassistant = {
          auth_providers = lib.mkIf (!cfg.ldap.enable) [
            { type = "homeassistant"; }
          ];
          temperature_unit = "C";
          time_zone = config.time.timeZone;
          unit_system = "metric";
        };
      };
    })

    (lib.mkIf cfg.ldap.enable {
      config.homeassistant.auth_providers = [{
        type = "command_line";
        command =
          # the script is not inheriting PATH from home-assistant
          pkgs.resholve.writeScript "ldap-auth-sh"
            {
              fake.external = [ "on_auth_failure" "on_auth_success" ];
              inputs = with pkgs; [ coreutils curl gnugrep gnused openldap ];
              interpreter = "${pkgs.bash}/bin/bash";
              keep."source:$CONFIG_FILE" = true;
            }
            (builtins.readFile "${pkgs.fetchFromGitHub {
          owner = "bob1de";
          repo = "ldap-auth-sh";
          rev = "819f9233116e68b5af5a5f45167bcbb4ed412ed4";
          sha256 = "sha256-+QjRP5SKUojaCv3lZX2Kv3wkaNvpWFd97phwsRlhroY=";
        }}/ldap-auth.sh");
        args = [
          # https://github.com/bob1de/ldap-auth-sh/blob/master/examples/home-assistant.cfg
          (pkgs.writeText "config.cfg" /* shell */ ''
            ATTRS="${ldap.userField}"
            CLIENT="ldapsearch"
            DEBUG=0
            FILTER="${ldap.groupFilter "home-assistant-users"}"
            NAME_ATTR="${ldap.userField}"
            SCOPE="base"
            SERVER="ldaps://${ldap.domainName}"
            USERDN="uid=$(ldap_dn_escape "$username"),${ldap.userBaseDN}"
            BASEDN="$USERDN"

            on_auth_success() {
              # print the meta entries for use in HA
              if [ ! -z "$NAME_ATTR" ]; then
                name=$(echo "$output" | ${lib.getExe pkgs.gnused} -nr "s/^\s*$NAME_ATTR:\s*(.+)\s*\$/\1/Ip")
                [ -z "$name" ] || echo "name=$name"
              fi
            }
          '')
        ];
        meta = true;
      }];
    })
  ];

  config.services.portunus.seedSettings.groups = lib.optional (cfg.ldap.userGroup != null) {
    long_name = "Home-Assistant Users";
    name = cfg.ldap.userGroup;
    permissions = { };
  };
}
