{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.home-assistant;
  inherit (config.security) ldap;
in
{
  options = {
    services.home-assistant = {
      configurePostgres = lib.mkOption {
        type = lib.types.bool;
        default = false;
        example = true;
        description = "Whether to configure and create a local PostgreSQL database.";
      };

      ldap = {
        enable = lib.mkEnableOption ''login only via LDAP

          ::: {.note}
          Only enable this after completing the onboarding!
          :::
        '';

        userGroup = libS.ldap.mkUserGroupOption;
        adminGroup = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          example = "home-assistant-admins";
          description = "Name of the ldap group that grants admin access in Home-Assistant.";
        };
      };

      recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
    };
  };

  config.nixpkgs.overlays = lib.mkIf cfg.enable [
    (final: prev: {
      home-assistant = (prev.home-assistant.override (lib.optionalAttrs cfg.recommendedDefaults {
        extraPackages = ps: with ps; [
          pyqrcode # for TOTP qrcode
        ];
      })).overrideAttrs ({ patches ? [ ], ... }: {
        patches = patches ++ lib.optionals cfg.recommendedDefaults [
          ./home-assistant-no-cloud.diff
        ] ++ lib.optionals cfg.ldap.enable [
          # expand command_line authentication provider
          (final.fetchpatch {
            url = "https://github.com/home-assistant/core/pull/107419.diff";
            hash = "sha256-e477JfbvwVVHMLJ3XMAyK6lcnZV6QCK6r/Bwihl+iUs=";
          })
          ./home-assistant-create-person-when-credentials-exist.diff
        ];

        doInstallCheck = false;
      });
    })
  ];

  config.services.home-assistant = lib.mkMerge [
    (lib.mkIf (cfg.enable && cfg.recommendedDefaults) {
      config = {
        # load imperative config done via the web ui
        # https://wiki.nixos.org/wiki/Home_Assistant#Automations,_Scenes,_and_Scripts_from_the_UI
        "automation ui" = "!include automations.yaml";
        "scene ui" = "!include scenes.yaml";
        "script ui" = "!include scripts.yaml";

        default_config = { }; # yes, this is required...
        homeassistant = {
          # required for https://github.com/home-assistant/core/pull/107419 to allow new users
          auth_providers = [
            { type = "homeassistant"; }
          ];
          temperature_unit = "C";
          time_zone = config.time.timeZone;
          unit_system = "metric";
        };

        # https://www.home-assistant.io/integrations/recorder/#common-filtering-examples
        recoder = {
          exclude = {
            domains = [ "automation" "update" ];
            entity_globs = [ "sensor.sun*" "weather.*" ];
            entities = [ "sensor.date" "sensor.last_boot" "sun.sun" ];
            event_types = [ "call_service" ];
          };
        };

        # see https://github.com/zigpy/zigpy/pull/1340
        zha.zigpy_config.ota.z2m_remote_index = "https://raw.githubusercontent.com/Koenkk/zigbee-OTA/master/index.json";
      };
    })

    (lib.mkIf (cfg.enable && cfg.ldap.enable) {
      config.homeassistant.auth_providers = [{
        type = "command_line";
        # the script is not inheriting PATH from home-assistant
        command = pkgs.resholve.mkDerivation {
          pname = "ldap-auth-sh";
          version = "unstable-2019-02-23";

          src = pkgs.fetchFromGitHub {
            owner = "bob1de";
            repo = "ldap-auth-sh";
            rev = "819f9233116e68b5af5a5f45167bcbb4ed412ed4";
            hash = "sha256-+QjRP5SKUojaCv3lZX2Kv3wkaNvpWFd97phwsRlhroY=";
          };

          installPhase = ''
            install -Dm755 ldap-auth.sh -t $out/bin
          '';

          solutions.default = {
            fake.external = [ "on_auth_failure" "on_auth_success" ];
            inputs = with pkgs; [ coreutils curl gnugrep gnused openldap ];
            interpreter = lib.getExe pkgs.bash;
            keep."source:$CONFIG_FILE" = true;
            scripts = [ "bin/ldap-auth.sh" ];
          };
        }+ "/bin/ldap-auth.sh";
        args = [
          # https://github.com/bob1de/ldap-auth-sh/blob/master/examples/home-assistant.cfg
          (pkgs.writeText "config.cfg" /* shell */ ''
            ATTRS="${ldap.userField} ${ldap.roleField} isMemberOf"
            CLIENT="ldapsearch"
            DEBUG=0
            FILTER="${ldap.groupFilter cfg.ldap.userGroup}"
            NAME_ATTR="${ldap.userField}"
            SCOPE="base"
            SERVER="${ldap.serverURI}"
            USERDN="uid=$(ldap_dn_escape "$username"),${ldap.userBaseDN}"
            BASEDN="$USERDN"

            on_auth_success() {
              # print the meta entries for use in HA
              if [ ! -z "$NAME_ATTR" ]; then
                name=$(echo "$output" | ${lib.getExe pkgs.gnused} -nr "s/^\s*${ldap.userField}:\s*(.+)\s*\$/\1/Ip")
                [ -z "$name" ] || echo "$name = $name"
                fullname=$(echo "$output" | ${lib.getExe pkgs.gnused} -nr "s/^\s*${ldap.roleField}:\s*(.+)\s*\$/\1/Ip")
                [ -z "$fullname" ] || echo "fullname = $fullname"
                ${lib.optionalString (cfg.ldap.adminGroup != null) /* bash */ ''
                group=$(echo "$output" | ${lib.getExe pkgs.gnused} -nr "s/^\s*isMemberOf: cn=${cfg.ldap.adminGroup}\s*(.+)\s*\$/\1/Ip")
                [ -z "$group" ] && echo "group = system-users" || echo "group = system-admin"
                ''}
              fi
            }

            # to receive less confusing errors
            on_auth_failure() { false; }
          '')
        ];
        meta = true;
      }];
    })

    (lib.mkIf cfg.configurePostgres {
      config.recorder.db_url = "postgresql://@/hass";
    })
  ];

  config.services.portunus.seedSettings.groups = lib.optional (cfg.ldap.userGroup != null) {
    long_name = "Home-Assistant Users";
    name = cfg.ldap.userGroup;
    permissions = { };
  } ++ lib.optional (cfg.ldap.adminGroup != null) {
    long_name = "Home-Assistant Administrators";
    name = cfg.ldap.adminGroup;
    permissions = { };
  };

  config.services.postgresql = lib.mkIf cfg.configurePostgres {
    ensureDatabases = [ "hass" ];
    ensureUsers = [ {
      name = "hass";
      ensureDBOwnership = true;
    } ];
  };

  config.systemd.tmpfiles.rules = lib.mkIf (cfg.enable && cfg.recommendedDefaults) [
    "f ${cfg.configDir}/automations.yaml 0444 hass hass"
    "f ${cfg.configDir}/scenes.yaml 0444 hass hass"
    "f ${cfg.configDir}/scripts.yaml 0444 hass hass"
  ];
}
