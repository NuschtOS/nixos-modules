{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.postgresql;
  cfgu = config.services.postgresql.upgrade;
in
{
  options.services.postgresql = {
    upgrade = {
      enable = libS.mkOpinionatedOption "install the upgrade-pg-cluster script to update postgres.";

      extraArgs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "--link" ];
        example = [ "--jobs=4" ];
        description = lib.mdDoc "Extra arguments to pass to pg_upgrade. See https://www.postgresql.org/docs/current/pgupgrade.html for doc.";
      };

      newPackage = (lib.mkPackageOptionMD pkgs "postgresql" {
        default = [ "postgresql_15" ];
      }) // {
        description = lib.mdDoc ''
          The postgres package to which should be updated.
          After running upgrade-pg-cluster this must be set to services.postgresql.package to complete the update.
        '';
      };

      stopServices = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        example = [ "hedgedoc" "hydra" "nginx" ];
        description = lib.mdDoc "Systemd services to stop when upgrade is started.";
      };
    };

    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.optional cfgu.enable (
      let
        newData = "/var/lib/postgresql/${cfgu.newPackage.psqlSchema}";
        newBin = "${if cfg.extraPlugins == [] then cfgu.newPackage else cfgu.newPackage.withPackages (_: cfg.extraPlugins)}/bin";
        oldData = config.services.postgresql.dataDir;
        oldBin = "${config.services.postgresql.package}/bin";
        currPkg = cfg.package;
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" /* bash */ ''
        set -eu

        echo "Current version: ${currPkg.version}"
        echo "Update version:  ${cfgu.newPackage.version}"

        if [[ ${cfgu.newPackage.version} == ${currPkg.version} ]]; then
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
          services.postgresql.package = pkgs.postgresql_${cfgu.newPackage}
              sudo -u postgres vacuumdb --all --analyze-in-stages
              ${newData}/delete_old_cluster.sh
        "
      ''
    );

    services = {
      postgresql.enableJIT = lib.mkIf cfg.recommendedDefaults true;

      postgresqlBackup = lib.mkIf cfg.recommendedDefaults {
        compression = "zstd";
        compressionLevel = 9;
        pgdumpOptions = "--create --clean";
      };
    };
  };
}
