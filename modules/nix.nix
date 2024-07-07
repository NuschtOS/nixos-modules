{ config, lib, libS, pkgs, ... }:

let
  cfg = config.nix;

  # based on https://gist.github.com/Ma27/6650d10f772511931647d3189b3eb1d7
  diffBoot = /* bash */ ''
    if [[ "''${NIXOS_ACTION-}" == boot && -e /run/current-system && -e "''${1-}" ]]; then
      (
        unset PS4
        set -x
        ${lib.getExe config.nix.package} --extra-experimental-features nix-command store diff-closures /run/current-system "''${1-}"
      )
    fi
  '';
in
{
  options.nix = {
    deleteChannels = lib.mkEnableOption "" // { description = "Whether to delete all channels on a system switch."; };

    deleteUserProfiles = lib.mkEnableOption "" // { description = "Whether to delete all user profiles on a system switch."; };

    diffSystem = libS.mkOpinionatedOption "system closure diffing on updates";

    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";

    remoteBuilder = {
      enable = lib.mkEnableOption "restricted nix remote builder";

      sshPublicKeys = lib.mkOption {
        description = "SSH public keys accepted by the remote build user.";
        type = lib.types.listOf lib.types.str;
      };

      name = lib.mkOption {
        description = "Name of the user used for remote building.";
        type = lib.types.str;
        readOnly = true;
        default = "nix-remote-builder";
      };
    };
  };

  config = {
    boot.loader = {
      grub.extraInstallCommands = lib.mkIf cfg.diffSystem diffBoot;
      systemd-boot.extraInstallCommands = lib.mkIf cfg.diffSystem diffBoot;
    };

    environment.systemPackages = lib.mkIf cfg.recommendedDefaults (with pkgs; lib.mkBefore [ git ]);

    # based on https://github.com/numtide/srvos/blob/main/nixos/roles/nix-remote-builder.nix
    # and https://discourse.nixos.org/t/wrapper-to-restrict-builder-access-through-ssh-worth-upstreaming/25834
    nix.settings = {
      builders-use-substitutes = lib.mkIf cfg.recommendedDefaults true;
      connect-timeout = lib.mkIf cfg.recommendedDefaults 20;
      experimental-features = lib.mkIf cfg.recommendedDefaults [ "nix-command" "flakes" ];
      trusted-users = lib.mkIf cfg.remoteBuilder.enable (lib.mkOptionDefault [ cfg.remoteBuilder.name ]);
    };

    users.users.${cfg.remoteBuilder.name} = lib.mkIf cfg.remoteBuilder.enable {
      group = "nogroup";
      isNormalUser = true;
      openssh.authorizedKeys.keys = map
        (key:
          let
            wrapper-dispatch-ssh-nix = pkgs.writeShellScriptBin "wrapper-dispatch-ssh-nix" /* bash */ ''
              case $SSH_ORIGINAL_COMMAND in
                "nix-daemon --stdio")
                  exec ${config.nix.package}/bin/nix-daemon --stdio
                  ;;
                "nix-store --serve --write")
                  exec ${config.nix.package}/bin/nix-store --serve --write
                  ;;
                *)
                  echo "Access is only allowed for nix remote building, not running command \"$SSH_ORIGINAL_COMMAND\"" 1>&2
                  exit 1
              esac
            '';

          in
          "restrict,pty,command=\"${lib.getExe wrapper-dispatch-ssh-nix}\" ${key}"
        )
        config.nix.remoteBuilder.sshPublicKeys;
    };

    system = {
      activationScripts = {
        deleteChannels = lib.mkIf cfg.deleteChannels /* bash */ ''
          echo "Deleting all channels..."
          rm -rfv /root/{.nix-channels,.nix-defexpr} /home/*/{.nix-channels,.nix-defexpr} /nix/var/nix/profiles/per-user/*/channels* || true
        '';

        deleteUserProfiles = lib.mkIf cfg.deleteUserProfiles /* bash */ ''
          echo "Deleting all user profiles..."
          rm -rfv /root/.nix-profile /home/*/.nix-profile /nix/var/nix/profiles/per-user/*/profile* || true
        '';

        diff-system = lib.mkIf cfg.diffSystem {
          supportsDryActivation = true;
          text = /* bash */ ''
            if [[ -e /run/current-system && -e $systemConfig ]]; then
              echo System package diff:
              (
                unset PS4
                set -x
                ${lib.getExe config.nix.package} --extra-experimental-features nix-command store diff-closures /run/current-system $systemConfig || true
              )
            fi
          '';
        };
      };

      build.installBootLoader = lib.mkIf cfg.diffSystem (lib.mkMerge [
        (lib.mkIf config.boot.isContainer (pkgs.writeShellScript "diff-closures-on-nspawn" diffBoot))
        (lib.mkIf (config.boot.loader.external.enable && !config.boot.isContainer) (lib.mkForce (pkgs.writeShellScript "install-bootloader-external" ''
          ${diffBoot}
          exec ${config.boot.loader.external.installHook}
        '')))
      ]);
    };
  };
}
