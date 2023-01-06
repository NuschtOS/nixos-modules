{ config, lib, pkgs, ... }:

let
  cfg = config.services.postgresql.upgrade;
in
{
  options.services.postgresql.upgrade = {
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
        The package to which should be updated.
        After running upgrade-pg-cluster this must be set in services.postgresql.package.
      '';
    };

    stopServices = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      example = [ "hedgedoc" "hydra" "nginx" ];
      description = lib.mdDoc "Systemd services to stop when upgrade is started.";
    };
  };

  config = {
    environment.systemPackages = lib.optional (cfg.newPackage != config.services.postgresql.package) [(
      let
        newData = "/var/lib/postgresql/${cfg.newPackage.psqlSchema}";
        newBin = "${cfg.newPackage}/bin";
        oldData = config.services.postgresql.dataDir;
        oldBin = "${config.services.postgresql.package}/bin";
      in
      pkgs.writeScriptBin "upgrade-pg-cluster" /* bash */ ''
        set -eux

        systemctl stop --wait postgresql ${lib.concatStringsSep " " cfg.stopServices}

        install -d -m 0700 -o postgres -g postgres "${newData}"
        cd "${newData}"
        sudo -u postgres "${newBin}/initdb" -D "${newData}"

        sudo -u postgres "${newBin}/pg_upgrade" \
          --old-datadir "${oldData}" --new-datadir "${newData}" \
          --old-bindir ${oldBin} --new-bindir ${newBin} \
          ${lib.concatStringsSep " " cfg.extraArgs} \
          "$@"
      ''
    )];
  };
}
