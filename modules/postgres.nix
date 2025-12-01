{
  config,
  lib,
  libS,
  options,
  pkgs,
  utils,
  ...
}: let
  opt = options.services.postgresql;
  optb = options.services.postgresqlBackup;
  cfg = config.services.postgresql;
  cfgb = config.services.postgresqlBackup;
  cfgu = config.services.postgresql.upgrade;

  # TODO: clean up when dropping support for 25.05
  hasPGdumpAllOptionsAndPostgresqlSetup = lib.versionAtLeast lib.version "25.11pre";
  latestVersion =
    if pkgs?postgresql_18
    then "18"
    else "17";
  currentMajorVersion = lib.versions.major cfg.package.version;
  newMajorVersion = lib.versions.major cfgu.newPackage.version;

  mkTimerDefault = time: {
    OnBootSec = "10m";
    OnCalendar = time;
    Persistent = true;
    RandomizedDelaySec = "10m";
  };

  # withJIT installs the postgres' jit output as an extension but that is no shared object to load
  cfgInstalledExtensions = lib.filter (x: x != "postgresql") (map (e: lib.getName e) cfg.finalPackage.installedExtensions);
in {
  options.services = {
    postgresql = {
      configurePgStatStatements = libS.mkOpinionatedOption "configure and enable pg_stat_statements extension";

      databases = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        description = ''
          List of all databases that exist in postgres and are managed by NixOS.
          When manually creating a database through scripts, they should be added to this option
          to support automatically installing extensions (eg: `pg_stat_stements`) or creating backups.

          ::: {.note}
          `services.postgresql.ensureDatabases` and `postgres` are automatically added.
          :::
        '';
      };

      extensionToInstall = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        defaultText = lib.literalExpression "config.services.postgresql.finalPackage.installedExtensions";
        description = "List of extensions which are going to be installed.";
      };

      installAllAvailableExtensions = libS.mkOpinionatedOption "install all extensions installed with `ALTER EXTENSION \"...\" UPDATE` or the extension equivalent custom SQL statements";

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

      pgRepackTimer = {
        enable = libS.mkOpinionatedOption "install pg_repack and configure a systemd timer to run it periodically on all DBs";

        timerConfig = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf utils.systemdUtils.unitOptions.unitOption);
          default = mkTimerDefault "02:00";
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

      preloadAllInstalledExtensions = libS.mkOpinionatedOption "load all installed extensions through `shared_preload_libraries`";

      preventDowngrade = libS.mkOpinionatedOption "abort startup if /var/lib/postgresql contains any directory not belonging to the current major postgres version";

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
          default = ["--link" "--jobs=$(nproc)"];
          description = "Extra arguments to pass to `pg_upgrade`. See <https://www.postgresql.org/docs/current/pgupgrade.html> for more information.";
        };

        newPackage =
          (lib.mkPackageOption pkgs "postgresql" {
            default = ["postgresql_${latestVersion}"];
          })
          // {
            description = ''
              The postgres package that is being upgraded to.
              After running `upgrade-postgres`, `service.postgresql.packages` must be set to this exact package to successfully complete the update.
            '';
          };

        stopServices = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
          example = ["hedgedoc" "phpfpm-nextcloud" "nextcloud-notify_push"];
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
        enable = libS.mkOpinionatedOption "configure a systemd timer to run `VACUUM ANALYZE` periodically on all DBs";

        timerConfig = lib.mkOption {
          type = lib.types.nullOr (lib.types.attrsOf utils.systemdUtils.unitOptions.unitOption);
          default = mkTimerDefault "03:00";
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

    postgresqlBackup =
      lib.optionalAttrs hasPGdumpAllOptionsAndPostgresqlSetup
      {
        backupAll = lib.mkOption {};

        backupAllExcept = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
          example = ["lossy"];
          description = ''
            List of databases added to `pg_dumpall`'s `--exclude-database` argument.

            This option also enforces ${optb.backupAll} to be turned on which has the effect that all databases are backed up except the ones listed in this option.
          '';
        };
      }
      // {
        databases = lib.mkOption {
          defaultText =
            lib.literalExpression
            /*
            nix
            */
            ''${opt.databases} ++ [ "postgres" ]'';
          # NOTE: option description cannot be overwritten or merged
          # description = ''
          #   List of database names to dump into individually archives.
          #
          #   Defaults to all available postgres databases from the ${opt.databases} option.
          #
          #   ::: {.note}
          #   lib.mkForce must be used to overwrite this option as otherwise appending to the list is not easily possible.
          #   :::
          # '';
        };

        databasesExcept = lib.mkOption {
          type = with lib.types; listOf str;
          default = [];
          description = ''
            This option can be used to exclude backups of databases that came from the ${opt.databases} default.
          '';
        };
      };
  };

  imports = [
    (lib.mkRenamedOptionModule ["services" "postgresql" "enableAllPreloadedLibraries"] ["services" "postgresql" "installAllAvailableExtensions"])
    (lib.mkRenamedOptionModule ["services" "postgresql" "preloadAllExtensions"] ["services" "postgresql" "preloadAllInstalledExtensions"])
  ];

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.refreshCollation -> lib.versionAtLeast cfg.package.version "15";
        message = "services.postgresql.refreshCollation requires at least PostgreSQL version 15";
      }
      {
        assertion = let
          # the csv type maps an empty list [] to an empty string which splitString maps to [""] .....
          preload_libs = lib.splitString "," cfg.settings.shared_preload_libraries;
        in
          preload_libs == "" -> lib.all (so: so != "") preload_libs;
        message = "services.postgresql.settings.shared_preload_libraries cannot contain empty elements: \"${cfg.settings.shared_preload_libraries}\"";
      }
    ];

    warnings =
      lib.optional (lib.versionOlder cfg.package.version latestVersion)
      "You are are running PostgreSQL version ${cfg.package.version} but the latest version is ${latestVersion}. Consider upgrading :)";

    environment = {
      interactiveShellInit = lib.mkIf cfgu.enable ''
        if [[ ${currentMajorVersion} != ${newMajorVersion} ]]; then
          echo "There is a major postgres update available! Current version: ${cfg.package.version}, Update version:  ${cfgu.newPackage.version}"
        fi
      '';

      systemPackages = lib.mkIf cfgu.enable [
        (
          let
            extensions =
              if lib.hasAttr "extensions" options.services.postgresql
              then "extensions"
              else "extraPlugins";
            # conditions copied from nixos/modules/services/databases/postgresql.nix
            newPackage =
              if cfg.enableJIT
              then cfgu.newPackage.withJIT
              else cfgu.newPackage;
            newData = "/var/lib/postgresql/${cfgu.newPackage.psqlSchema}";
            newBin = "${
              if cfg.${extensions} == []
              then newPackage
              else newPackage.withPackages cfg.${extensions}
            }/bin";

            oldPackage =
              if cfg.enableJIT
              then cfg.package.withJIT
              else cfg.package;
            oldData = config.services.postgresql.dataDir;
            oldBin = "${
              if cfg.${extensions} == []
              then oldPackage
              else oldPackage.withPackages cfg.${extensions}
            }/bin";
          in
            pkgs.writeScriptBin "upgrade-postgres"
            /*
            bash
            */
            (''
                set -eu

                echo "Current version: ${cfg.package.version}"
                echo "Update version:  ${cfgu.newPackage.version}"

                if [[ ${currentMajorVersion} == ${newMajorVersion} ]]; then
                  echo "There is no major postgres update available."
                  exit 2
                fi

                # don't fail when any unit cannot be stopped
                systemctl stop ${lib.concatStringsSep " " cfgu.stopServices} || true
                systemctl stop postgresql

              ''
              # postgresql version 18 defaults to checksums enabled
              # The Notes at https://www.postgresql.org/docs/18/app-pgchecksums.html mention that it is safe to enable them even when a failure would happen.
              + lib.optionalString (lib.versionOlder currentMajorVersion "18" && lib.versionAtLeast newMajorVersion "18") ''
                pg_checksums --pgdata ${oldData} --enable --progress
              ''
              + ''
                install -d -m 0700 -o postgres -g postgres "${newData}"
                cd "${newData}"
                sudo -u postgres "${newBin}/initdb" -D "${newData}"

                sudo -u postgres "${newBin}/pg_upgrade" \
                  --old-datadir "${oldData}" --new-datadir "${newData}" \
                  --old-bindir ${oldBin} --new-bindir ${newBin} \
                  ${lib.concatStringsSep " " cfgu.extraArgs} \
                  "$@"

                echo "
                  -----------------------------




                  Now set this NixOS option and deploy:
                    services.postgresql.package = pkgs.postgresql_${newMajorVersion}

                  When the postgres os up and running execute those commands:
                  sudo -u postgres vacuumdb --all --analyze-in-stages --missing-stats-only
                  sudo -u postgres vacuumdb --all --analyze-only
                  sudo -u postgres psql -f /var/lib/postgresql/18/update_extensions.sql


                  Once you checked that everything works, you can delete the old cluster with:
                  ${newData}/delete_old_cluster.sh
                "
              '')
        )
      ];
    };

    services = {
      postgresql = {
        # NOTE: the defaultText of services.postgresqlBackup.databases must match this
        databases = ["postgres"] ++ config.services.postgresql.ensureDatabases;
        enableJIT = lib.mkIf cfg.recommendedDefaults true;
        extensions = lib.mkIf cfg.pgRepackTimer.enable (ps: with ps; [pg_repack]);
        extensionToInstall = lib.mkMerge [
          (lib.mkIf cfg.configurePgStatStatements ["pg_stat_statements"])
          cfgInstalledExtensions
        ];
        settings.shared_preload_libraries = lib.mkMerge [
          (lib.mkIf cfg.configurePgStatStatements ["pg_stat_statements"])
          # TODO: upstream, this probably requires a new entry in passthru to pick if the object name doesn't match the plugin name or there are multiple
          # https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/services/databases/postgresql.nix#L81
          (
            let
              # NOTE: move into extensions passthru.libName when upstreaming
              getSoOrFallback = ext:
                {
                  postgis = "postgis-3";
                }.${
                  ext
                } or ext;
            in
              lib.mkIf cfg.preloadAllInstalledExtensions (map getSoOrFallback cfgInstalledExtensions)
          )
        ];
        upgrade.stopServices = with config.services;
          lib.mkMerge [
            (lib.mkIf (atuin.enable && atuin.database.createLocally) ["atuin"])
            (lib.mkIf (gancio.enable && gancio.settings.db.dialect == "postgres") ["gancio"])
            (lib.mkIf (gitea.enable && gitea.database.socket == "/run/postgresql") ["gitea"])
            (lib.mkIf (grafana.enable && grafana.settings.database.host == "/run/postgresql") ["grafana"])
            (lib.mkIf (healthchecks.enable && healthchecks.settings.DB_HOST == "/run/postgresql") ["healthchecks"])
            (lib.mkIf (hedgedoc.enable && hedgedoc.settings.db.host == "/run/postgresql") ["hedgedoc"])
            # @ means to connect to localhost
            (lib.mkIf (home-assistant.enable && (lib.hasPrefix "postgresql://@/" home-assistant.config.recorder.db_url or "")) ["home-assistant"])
            # if host= is omitted, hydra defaults to connect to localhost
            (lib.mkIf (hydra.enable && (!lib.hasInfix ";host=" hydra.dbi)) [
              "hydra-evaluator"
              "hydra-notify"
              "hydra-send-stats"
              "hydra-update-gc-roots.service"
              "hydra-update-gc-roots.timer"
              "hydra-queue-runner"
              "hydra-server"
            ])
            (lib.mkIf (mastodon.enable && mastodon.database.host == "/run/postgresql") ["mastodon-sidekiq-all" "mastodon-streaming.target" "mastodon-web"])
            # assume that when host is set, which is not the default, the database is none local
            (lib.mkIf (matrix-synapse.enable && (!lib.hasAttr "host" matrix-synapse.settings.database.args)) ["matrix-synapse"])
            (lib.mkIf (mediagoblin.enable && lib.hasPrefix "postgresql:///" mediagoblin.settings.mediagoblin.sql_engine) ["mediagoblin-celeryd" "mediagoblin-paster"])
            (lib.mkIf (mediawiki.enable && mediawiki.database.socket == "/run/postgresql") ["phpfpm-mediawiki"])
            (lib.mkIf (miniflux.enable && miniflux.createDatabaseLocally) ["miniflux"])
            (lib.mkIf (mobilizon.enable && mobilizon.settings.":mobilizon"."Mobilizon.Storage.Repo".socket_dir == "/run/postgresql") ["mobilizon"])
            (lib.mkIf (nextcloud.notify_push.enable && nextcloud.notify_push.dbhost == "/run/postgresql") ["nextcloud-notify_push"])
            (lib.mkIf (nextcloud.enable && nextcloud.config.dbhost == "/run/postgresql") ["phpfpm-nextcloud"])
            (lib.mkIf (pretalx.enable && pretalx.settings.database.host == "/run/postgresql") ["pretalx-web" "pretalx-worker"])
            (lib.mkIf (vaultwarden.enable && (lib.hasInfix "?host=/run/postgresql" vaultwarden.config.DATABASE_URL)) ["vaultwarden"])
          ];
      };

      postgresqlBackup = lib.mkMerge [
        ({
            databases = lib.mkIf (cfg.recommendedDefaults || cfgb.databasesExcept != []) (lib.subtractLists cfgb.databasesExcept config.services.postgresql.databases);
          }
          // lib.optionalAttrs hasPGdumpAllOptionsAndPostgresqlSetup {
            backupAll = lib.mkIf (cfgb.backupAllExcept != []) true;
            pgdumpAllOptions = lib.concatMapStringsSep " " (db: "--exclude-database=${db}") cfgb.backupAllExcept;
          })

        (lib.mkIf cfg.recommendedDefaults {
          compression = "zstd";
          compressionLevel = 9;
          pgdumpOptions = "--create --clean";
        })
      ];
    };

    systemd = {
      # TODO: drop the mkMerge when support for 25.05 is removed and we always have postgresql and postgresql-setup
      services = lib.mkMerge [
        {
          postgresql.preStart =
            lib.mkIf cfg.preventDowngrade
            /*
            bash
            */
            ''
              found_current=false
              for dir in $(find /var/lib/postgresql/ -mindepth 1 -maxdepth 1 -type d -not -name ".*" | sort --version-sort); do
                if [[ $found_current == true ]]; then
                  echo "Found directory ''${dir} which is newer than the current major postgres version ${currentMajorVersion}, aborting startup due to ${opt.preventDowngrade}"
                  exit 10
                fi

                if [[ $(basename "$dir") == ${currentMajorVersion} ]]; then
                  found_current=true
                  continue
                fi
              done
            '';
        }

        {
          "postgresql${lib.optionalString hasPGdumpAllOptionsAndPostgresqlSetup "-setup"}" = {
            postStart = let
              psql = "psql --port=${toString cfg.settings.port}";
            in
              lib.mkMerge [
                (lib.mkIf cfg.refreshCollation (lib.mkBefore
                  /*
                  bash
                  */
                  ''
                    ### TODO: clean up when dropping support for 25.05
                    # copied from upstream due to the lack of extensibility
                    # TODO: improve this upstream?

                    while ! ${psql} -d postgres -c "" 2> /dev/null; do
                      if ! kill -0 "$MAINPID"; then exit 1; fi
                      sleep 0.1
                    done
                    ###

                    ${psql} -tAc 'ALTER DATABASE "template1" REFRESH COLLATION VERSION'
                  ''))

                (lib.concatMapStrings
                  (user:
                    lib.optionalString (user.ensurePasswordFile != null)
                    /*
                    psql
                    */
                    ''
                      # TODO: use psql when dropping support for 25.05
                      ${psql} -tA <<'EOF'
                        DO $$
                        DECLARE password TEXT;
                        BEGIN
                          password := trim(both from replace(pg_read_file('${user.ensurePasswordFile}'), E'\n', '''));
                          EXECUTE format('ALTER ROLE ${user.name} WITH PASSWORD '''%s''';', password);
                        END $$;
                      EOF
                    '')
                  cfg.ensureUsers)

                # install/update pg_stat_statements extension in all databases
                # based on https://git.catgirl.cloud/999eagle/dotfiles-nix/-/blob/main/modules/system/server/postgres/default.nix#L294-302
                (lib.mkIf (cfg.installAllAvailableExtensions || cfg.configurePgStatStatements) (lib.concatStrings (map
                  (
                    db: (
                      lib.concatMapStringsSep "\n"
                      (ext: let
                        extUpdateStatement = name:
                          {
                            # pg_repack cannot be updated but reinstalling it is safe
                            "pg_repack" = "DROP EXTENSION pg_repack CASCADE; CREATE EXTENSION pg_repack";
                            "postgis" = "SELECT postgis_extensions_upgrade()";
                          }.${
                            name
                          } or ''ALTER EXTENSION "${ext}" UPDATE'';
                      in
                        /*
                        bash
                        */
                        ''
                          # TODO: use psql when dropping support for 25.05
                          ${psql} -tAd '${db}' -c 'CREATE EXTENSION IF NOT EXISTS "${ext}"'
                          ${psql} -tAd '${db}' -c '${extUpdateStatement ext}'
                        '')
                      cfgInstalledExtensions
                    )
                  )
                  cfg.databases)))

                (lib.mkIf cfg.refreshCollation (lib.concatStrings (map
                  (db:
                    /*
                    bash
                    */
                    ''
                      # TODO: use psql when dropping support for 25.05
                      ${psql} -tAc 'ALTER DATABASE "${db}" REFRESH COLLATION VERSION'
                    '')
                  cfg.databases)))
              ];

            # reduce downtime for dependent services
            stopIfChanged = lib.mkIf cfg.recommendedDefaults false;
          };

          postgresql-pg-repack = lib.mkIf cfg.vacuumAnalyzeTimer.enable {
            description = "Repack all PostgreSQL databases";
            serviceConfig = {
              ExecStart = "${lib.getExe cfg.package.pkgs.pg_repack} --port=${builtins.toString cfg.settings.port} --all";
              User = "postgres";
            };
          };

          postgresql-vacuum-analyze = lib.mkIf cfg.vacuumAnalyzeTimer.enable {
            description = "Vacuum and analyze all PostgreSQL databases";
            serviceConfig = {
              ExecStart = "${lib.getExe' cfg.package "psql"} --port=${builtins.toString cfg.settings.port} -tAc 'VACUUM ANALYZE'";
              User = "postgres";
            };
          };
        }
      ];

      timers = let
        mkTimerConfig = name:
          lib.mkMerge [
            (lib.mkDefault opt."${name}".timerConfig.default)
            cfg."${name}".timerConfig
          ];
        postgresqlTarget =
          if lib.hasAttr "postgresql" config.systemd.targets
          then "postgresql.target"
          else "postgresql.service";
      in {
        postgresql-pg-repack = lib.mkIf cfg.pgRepackTimer.enable {
          after = [postgresqlTarget];
          timerConfig = mkTimerConfig "pgRepackTimer";
          wantedBy = ["timers.target"];
        };
        postgresql-vacuum-analyze = lib.mkIf cfg.vacuumAnalyzeTimer.enable {
          after = [postgresqlTarget];
          timerConfig = mkTimerConfig "vacuumAnalyzeTimer";
          wantedBy = ["timers.target"];
        };
      };
    };
  };
}
