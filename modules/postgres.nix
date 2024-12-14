{ config, lib, libS, options, pkgs, utils, ... }:

let
  cfg = config.services.postgresql;
  cfgu = config.services.postgresql.upgrade;
  latestVersion = if pkgs?postgresql_17 then "17" else "16";
in
{
  options.services.postgresql = {
    configurePgStatStatements = libS.mkOpinionatedOption "configure and enable pg_stat_statements extension";

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
      enable = libS.mkOpinionatedOption ''
        install the `upgrade-postgres` script.

        The script can upgrade a local postgres server in a two step process.
        Before the upgrade can be be started, `services.postgresql.upgrade.stopServices` must be configured!
        After that is done and deploment, the upgrade can be started by running the script.

        The script first stops all services configured in `stopServices` and the postgres server and then runs a `pg_upgrade` with the configured `newPackage`.
        After that is complete, `services.postgresql.package` must be adjusted and deployed.
        As a final step it is highly recommend to run the printed `vacuumdb` command to achieve the best performance.
        If the upgrade is successful, the old data can be deleted by running the printed `delete_old_cluster.sh` script.

        ::: {.warning}
        It is recommended to do a backup before doing the upgrade in the form of an SQL dump of the databases.
        :::
      '';

      extraArgs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "--link" "--jobs=$(nproc)" ];
        description = "Extra arguments to pass to `pg_upgrade`. See <https://www.postgresql.org/docs/current/pgupgrade.html> for more information.";
      };

      newPackage = (lib.mkPackageOption pkgs "postgresql" {
        default = [ "postgresql_${latestVersion}" ];
      }) // {
        description = ''
          The postgres package that is being upgraded to.
          After running `upgrade-postgres`, `service.postgresql.packages` must be set to this exact package to successfully complete the update.
        '';
      };

      stopServices = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "hedgedoc" "phpfpm-nextcloud" "nextcloud-notify_push" ];
        description = ''
          Systemd service names which are stopped before an upgrade is started.
          It is very important that all postgres clients are stopped before an upgrade is attempted as they are blocking operations on the databases.

          The service files of some well known services are added by default. Check the source code of the module to discover which those are.

          ::: {.note}
          These can match the service name but do not need to! For example services using phpfpm might have a `phpfpm-` prefix.
          :::
        '';
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

    environment = {
      interactiveShellInit = lib.mkIf cfgu.enable ''
        if [[ ${cfgu.newPackage.version} != ${cfg.package.version} ]]; then
          echo "There is a major postgres update available! Current version: ${cfg.package.version}, Update version:  ${cfgu.newPackage.version}"
        fi
      '';

      systemPackages = lib.mkIf cfgu.enable [ (
        let
          extensions = if lib.hasAttr "extensions" options.services.postgresql then "extensions" else "extraPlugins";
          # conditions copied from nixos/modules/services/databases/postgresql.nix
          newPackage = if cfg.enableJIT then cfgu.newPackage.withJIT else cfgu.newPackage;
          newData = "/var/lib/postgresql/${cfgu.newPackage.psqlSchema}";
          newBin = "${if cfg.${extensions} == [] then newPackage else newPackage.withPackages cfg.${extensions}}/bin";

          oldPackage = if cfg.enableJIT then cfg.package.withJIT else cfg.package;
          oldData = config.services.postgresql.dataDir;
          oldBin = "${if cfg.${extensions} == [] then oldPackage else oldPackage.withPackages cfg.${extensions}}/bin";
        in
        pkgs.writeScriptBin "upgrade-postgres" /* bash */ ''
          set -eu

          echo "Current version: ${cfg.package.version}"
          echo "Update version:  ${cfgu.newPackage.version}"

          if [[ ${cfgu.newPackage.version} == ${cfg.package.version} ]]; then
            echo "There is no major postgres update available."
            exit 2
          fi

          # don't fail when any unit cannot be stopped
          systemctl stop ${lib.concatStringsSep " " cfgu.stopServices} || true
          systemctl stop postgresql

          install -d -m 0700 -o postgres -g postgres "${newData}"
          cd "${newData}"
          sudo -u postgres "${newBin}/initdb" -D "${newData}"

          sudo -u postgres "${newBin}/pg_upgrade" \
            --old-datadir "${oldData}" --new-datadir "${newData}" \
            --old-bindir ${oldBin} --new-bindir ${newBin} \
            ${lib.concatStringsSep " " cfgu.extraArgs} \
            "$@"

          echo "


            Run the below shell commands after setting this NixOS option:
            services.postgresql.package = pkgs.postgresql_${lib.versions.major cfgu.newPackage.version}

            sudo -u postgres vacuumdb --all --analyze-in-stages
            ${newData}/delete_old_cluster.sh
          "
        ''
      ) ];
    };

    services = {
      postgresql = {
        databases = [ "postgres" ] ++ config.services.postgresql.ensureDatabases;
        enableJIT = lib.mkIf cfg.recommendedDefaults true;
        settings.shared_preload_libraries = lib.mkIf cfg.configurePgStatStatements "pg_stat_statements";
        upgrade.stopServices = with config.services; lib.mkMerge [
          (lib.mkIf (atuin.enable && atuin.database.createLocally) [ "atuin" ])
          (lib.mkIf (gitea.enable && gitea.database.socket == "/run/postgresql") [ "gitea" ])
          (lib.mkIf (grafana.enable && grafana.settings.database.host == "/run/postgresql") [ "grafana" ])
          (lib.mkIf (healthchecks.enable && healthchecks.settings.DB_HOST == "/run/postgresql") [ "healthchecks" ])
          (lib.mkIf (hedgedoc.enable && hedgedoc.settings.db.host == "/run/postgresql") [ "hedgedoc" ])
          # @ means to connect to localhost
          (lib.mkIf (home-assistant.enable && (lib.hasPrefix "postgresql://@/" home-assistant.config.recorder.db_url)) [ "home-assistant" ])
          # if host= is omitted, hydra defaults to connect to localhost
          (lib.mkIf (hydra.enable && (!lib.hasInfix ";host=" hydra.dbi)) [
            "hydra-evaluator" "hydra-notify" "hydra-send-stats" "hydra-update-gc-roots" "hydra-queue-runner" "hydra-server"
          ])
          (lib.mkIf (mastodon.enable && mastodon.database.host == "/run/postgresql") [ "mastodon-sidekiq-all" "mastodon-streaming.target" "mastodon-web"])
          # assume that when host is set, which is not the default, the database is none local
          (lib.mkIf (matrix-synapse.enable && (!lib.hasAttr "host" matrix-synapse.settings.database.args)) [ "matrix-synapse" ])
          (lib.mkIf (mediawiki.enable && mediawiki.database.socket ==  "/run/postgresql") [ "phpfpm-mediawiki" ])
          (lib.mkIf (miniflux.enable && miniflux.createDatabaseLocally) [ "miniflux" ])
          # TODO: simplify after https://github.com/NixOS/nixpkgs/pull/352508 got merged
          (lib.mkIf (mobilizon.enable && lib.hasSuffix "/run/postgresql" mobilizon.settings.":mobilizon"."Mobilizon.Storage.Repo".socket_dir) [ "mobilizon" ])
          (lib.mkIf (nextcloud.notify_push.enable && nextcloud.notify_push.dbhost == "/run/postgresql") [ "nextcloud-notify_push" ])
          (lib.mkIf (nextcloud.enable && nextcloud.config.dbhost == "/run/postgresql") [ "phpfpm-nextcloud" ])
          (lib.mkIf (pretalx.enable && pretalx.settings.database.host == "/run/postgresql") [ "pretalx-web" "pretalx-worker" ])
          (lib.mkIf (vaultwarden.enable && (lib.hasInfix "?host=/run/postgresql" vaultwarden.config.DATABASE_URL)) [ "vaultwarden" ])
        ];
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

            (lib.mkIf cfg.refreshCollation (lib.concatStrings (map (db: /* bash */ ''
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
