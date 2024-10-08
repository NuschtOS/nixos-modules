{ config, lib, libS, pkgs, utils, ... }:

let
  cfg = config.services.postgresql;
  cfgu = config.services.postgresql.upgrade;
  latestVersion = "16";
in
{
  options.services.postgresql = {
    configurePgStatStatements = libS.mkOpinionatedOption "configure and enable pg_stat_statements";

    databases = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = ''
        List of all databases.

        This option is used eg. when installing extensions like pg_stat_stements in all databases.

        ::: {.note}
        `services.postgresql.ensureDatabases` and `postgres` are automatically added.
        :::
      '';
    };

    ensureUsers = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          ensurePasswordFile = lib.mkOption {
            type = lib.types.nullOr lib.types.path;
            default = null;
            description = "Path to a file containing the password of the user.";
          };
        };
      });
    };

    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";

    refreshCollation = libS.mkOpinionatedOption "refresh collation on startup. This prevents errors when initializing new DBs after a glibc upgrade";

    upgrade = {
      enable = libS.mkOpinionatedOption "install the upgrade-pg-cluster script to update postgres";

      extraArgs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "--link" "--jobs=$(nproc)" ];
        description = "Extra arguments to pass to pg_upgrade. See https://www.postgresql.org/docs/current/pgupgrade.html for doc.";
      };

      newPackage = (lib.mkPackageOption pkgs "postgresql" {
        default = [ "postgresql_${latestVersion}" ];
      }) // {
        description = ''
          The postgres package to which should be updated.
          After running upgrade-pg-cluster this must be set to services.postgresql.package to complete the update.
        '';
      };

      stopServices = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "hedgedoc" "hydra" "nginx" ];
        description = "Systemd services to stop when upgrade is started.";
      };
    };

    vacuumAnalyzeTimer = {
      enable = libS.mkOpinionatedOption "timer to run VACUUM ANALYZE on all DBs";

      timerConfig = lib.mkOption {
        type = lib.types.nullOr (lib.types.attrsOf utils.systemdUtils.unitOptions.unitOption);
        default = {
          OnCalendar = "03:00";
          Persistent = true;
          RandomizedDelaySec = "30m";
        };
        example = {
          OnCalendar = "06:00";
          Persistent = true;
          RandomizedDelaySec = "5h";
        };
        description = ''
          When to run the VACUUM ANALYZE.
          See {manpage}`systemd.timer(5)` for details.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [ {
      assertion = cfg.refreshCollation -> lib.versionAtLeast cfg.package.version "15";
      message = "services.postgresql.refreshCollation requires at least PostgreSQL version 15";
    } ];

    warnings = lib.optional (lib.versionOlder cfg.package.version latestVersion)
      "You are are running PostgreSQL version ${cfg.package.version} but the latest version is ${latestVersion}. Consider upgrading :)";

    environment.systemPackages = lib.optional cfgu.enable (
      let
        # conditions copied from nixos/modules/services/databases/postgresql.nix
        newPackage = if cfg.enableJIT then cfgu.newPackage.withJIT else cfgu.newPackage;
        newData = "/var/lib/postgresql/${cfgu.newPackage.psqlSchema}";
        newBin = "${if cfg.extraPlugins == [] then newPackage else newPackage.withPackages cfg.extraPlugins}/bin";

        oldPackage = if cfg.enableJIT then cfg.package.withJIT else cfg.package;
        oldData = config.services.postgresql.dataDir;
        oldBin = "${if cfg.extraPlugins == [] then oldPackage else oldPackage.withPackages cfg.extraPlugins}/bin";
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" /* bash */ ''
        set -eu

        echo "Current version: ${cfg.package.version}"
        echo "Update version:  ${cfgu.newPackage.version}"

        if [[ ${cfgu.newPackage.version} == ${cfg.package.version} ]]; then
          echo "There is no major postgres update available."
          exit 2
        fi

        systemctl stop postgresql ${lib.concatStringsSep " " cfgu.stopServices}

        install -d -m 0700 -o postgres -g postgres "${newData}"
        cd "${newData}"
        sudo -u postgres "${newBin}/initdb" -D "${newData}"

        sudo -u postgres "${newBin}/pg_upgrade" \
          --old-datadir "${oldData}" --new-datadir "${newData}" \
          --old-bindir ${oldBin} --new-bindir ${newBin} \
          ${lib.concatStringsSep " " cfgu.extraArgs} \
          "$@"

        echo "


          Run the following commands after setting:
          services.postgresql.package = pkgs.postgresql_${lib.versions.major cfgu.newPackage.version}

          sudo -u postgres vacuumdb --all --analyze-in-stages
          ${newData}/delete_old_cluster.sh
        "
      ''
    );

    services = {
      postgresql = {
        databases = [ "postgres" ] ++ config.services.postgresql.ensureDatabases;
        enableJIT = lib.mkIf cfg.recommendedDefaults true;
        settings.shared_preload_libraries = lib.mkIf cfg.configurePgStatStatements "pg_stat_statements";
      };

      postgresqlBackup = lib.mkIf cfg.recommendedDefaults {
        compression = "zstd";
        compressionLevel = 9;
        pgdumpOptions = "--create --clean";
      };
    };

    systemd = {
      services = {
        postgresql = {
          postStart = lib.mkMerge [
            (lib.mkIf cfg.refreshCollation (lib.mkBefore /* bash */ ''
              # copied from upstream due to the lack of extensibility
              # TODO: improve this upstream?
              PSQL="psql --port=${toString cfg.settings.port}"

              while ! $PSQL -d postgres -c "" 2> /dev/null; do
                if ! kill -0 "$MAINPID"; then exit 1; fi
                sleep 0.1
              done

              $PSQL -tAc 'ALTER DATABASE "template1" REFRESH COLLATION VERSION'
            ''))

            (lib.concatMapStrings (user: lib.optionalString (user.ensurePasswordFile != null) /* psql */ ''
              $PSQL -tA <<'EOF'
                DO $$
                DECLARE password TEXT;
                BEGIN
                  password := trim(both from replace(pg_read_file('${user.ensurePasswordFile}'), E'\n', '''));
                  EXECUTE format('ALTER ROLE ${user.name} WITH PASSWORD '''%s''';', password);
                END $$;
              EOF
            '') cfg.ensureUsers)

            # install/update pg_stat_statements extension in all databases
            # based on https://git.catgirl.cloud/999eagle/dotfiles-nix/-/blob/main/modules/system/server/postgres/default.nix#L294-302
            (lib.mkIf cfg.configurePgStatStatements (lib.concatStrings (map (db:
              (lib.concatMapStringsSep "\n" (ext: /* bash */ ''
                $PSQL -tAd "${db}" -c "CREATE EXTENSION IF NOT EXISTS ${ext}"
                $PSQL -tAd "${db}" -c "ALTER EXTENSION ${ext} UPDATE"
              '') (lib.splitString "," cfg.settings.shared_preload_libraries))
            ) cfg.databases)))

            (lib.mkIf cfg.refreshCollation (lib.concatStrings (map (db: ''
              $PSQL -tAc 'ALTER DATABASE "${db}" REFRESH COLLATION VERSION'
            '') cfg.databases)))
          ];

          # reduce downtime for dependent services
          stopIfChanged = lib.mkIf cfg.recommendedDefaults false;
        };

        postgresql-vacuum-analyze = lib.mkIf cfg.vacuumAnalyzeTimer.enable {
          description = "Vacuum and analyze all PostgreSQL databases";
          after = [ "postgresql.service" ];
          requires = [ "postgresql.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe' cfg.package "psql"} --port=${builtins.toString cfg.settings.port} -tAc 'VACUUM ANALYZE'";
            User = "postgres";
          };
          wantedBy = [ "timers.target" ];
        };
      };

       timers.postgresql-vacuum-analyze = lib.mkIf cfg.vacuumAnalyzeTimer.enable {
         inherit (cfg.vacuumAnalyzeTimer) timerConfig;
         wantedBy = [ "timers.target" ];
       };
    };
  };
}
