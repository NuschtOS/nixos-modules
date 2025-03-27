{ config, lib, libS, pkgs, ... }:

let
  cfg = config.nix;

  # based on https://gist.github.com/Ma27/6650d10f772511931647d3189b3eb1d7
  diffBoot = /* bash */ ''
    if [[ "''${NIXOS_ACTION-}" == boot && -e /run/current-system && -e "''${1-}" ]]; then
      (
        unset PS4
        set -x
        ${lib.getExe cfg.package} --extra-experimental-features nix-command store diff-closures /run/current-system "''${1-}"
      )
    fi
  '';
in
{
  options.nix = {
    deleteChannels = lib.mkEnableOption "" // { description = "Whether to delete all channels on a system activation and switch."; };

    deleteUserProfiles = lib.mkEnableOption "" // { description = "Whether to delete all user profiles on a system activation and switch."; };

    diffSystem = libS.mkOpinionatedOption "diff system closure on activation and switch";

    recommendedDefaults = libS.mkOpinionatedOption "set recommended default settings";

    remoteBuilder = {
      enable = lib.mkEnableOption "" // {
        description = ''
          Whether to configure a restricted user for nix remote building on this host.

          To use the remote builder on another NixOS machine, you need to configure the following there:

          ```nix
          nix.buildMachines = {
            hostName = "hostname.example.com";
            maxJobs = 4;
            protocol = "ssh-ng";
            speedFactor = 2;
            sshUser = "nix-remote-builder";
            supportedFeatures = [ "big-parallel" ];
            systems = [ "x86_64-linux" "i686-linux" ];
          };
          ```
        '';
      };

      sshPublicKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        example = [ "ssh-ed25519 AAA....tGz user" ];
        description = "SSH public keys accepted by the remote build user.";
      };

      name = lib.mkOption {
        type = lib.types.str;
        default = "nix-remote-builder";
        description = "Name of the user used for remote building.";
      };
    };
  };

  config = {
    boot.loader = {
      grub.extraInstallCommands = lib.mkIf cfg.diffSystem diffBoot;
      systemd-boot.extraInstallCommands = lib.mkIf cfg.diffSystem diffBoot;
    };

    nix.settings = {
      builders-use-substitutes = lib.mkIf cfg.recommendedDefaults true;
      connect-timeout = lib.mkIf cfg.recommendedDefaults 20;
      experimental-features = lib.mkIf cfg.recommendedDefaults [ "nix-command" "flakes" ];
      trusted-users = lib.mkIf cfg.remoteBuilder.enable [ cfg.remoteBuilder.name ];
    };

    # flakes require a git in PATH
    programs.git.enable = lib.mkIf cfg.recommendedDefaults true;

    # based on https://github.com/numtide/srvos/blob/main/nixos/roles/nix-remote-builder.nix
    # and https://discourse.nixos.org/t/wrapper-to-restrict-builder-access-through-ssh-worth-upstreaming/25834
    users.users.${cfg.remoteBuilder.name} = lib.mkIf cfg.remoteBuilder.enable {
      group = "nogroup";
      isNormalUser = true;
      openssh.authorizedKeys.keys = map
        (key:
          let
            wrapper-dispatch-ssh-nix = pkgs.writeShellScriptBin "wrapper-dispatch-ssh-nix" /* bash */ ''
              case $SSH_ORIGINAL_COMMAND in
                "nix-daemon --stdio")
                  exec ${lib.getExe' cfg.package "nix-daemon"} --stdio
                  ;;
                "nix-store --serve --write")
                  exec ${lib.getExe' cfg.package "nix-store"} --serve --write
                  ;;
                # used by nixos-rebuild --target-host ... --build-host ...
                "nix-store -r")
                  exec ${lib.getExe' cfg.package "nix-store"} -r
                  ;;
                *)
                  echo "Access is only allowed for nix remote building, not running command \"$SSH_ORIGINAL_COMMAND\"" 1>&2
                  exit 1
              esac
            '';

          in
          "restrict,pty,command=\"${lib.getExe wrapper-dispatch-ssh-nix}\" ${key}"
        )
        cfg.remoteBuilder.sshPublicKeys;
    };

    system = {
      activationScripts = {
        deleteChannels = lib.mkIf cfg.deleteChannels /* bash */ ''
          echo "Deleting all channels..."
          rm -rfv /root/{.local/state/nix/defexpr,.nix-channels,.nix-defexpr} /home/*/{.local/state/nix/defexpr,.nix-channels,.nix-defexpr} /nix/var/nix/profiles/per-user/*/channels* || true
        '';

        deleteUserProfiles = lib.mkIf cfg.deleteUserProfiles /* bash */ ''
          echo "Deleting all user profiles..."
          rm -rfv /root/{.local/state/nix/profile,.nix-profile} /home/*/{.local/state/nix/profile,.nix-profile} /nix/var/nix/profiles/per-user/*/profile* || true
        '';

        diff-system = lib.mkIf cfg.diffSystem {
          supportsDryActivation = true;
          text = /* bash */ ''
            if [[ -e /run/current-system && -e $systemConfig ]]; then
              echo
              echo nix diff new system against /run/current-system
              (
                unset PS4
                set -x
                ${lib.getExe cfg.package} --extra-experimental-features nix-command store diff-closures /run/current-system $systemConfig || true
              )
              echo
            fi
          '';
        };
      };

      build.installBootLoader = lib.mkIf cfg.diffSystem (lib.mkMerge [
        (lib.mkIf config.boot.isContainer (pkgs.writeShellScript "diff-closures-on-nspawn" diffBoot))
        (lib.mkIf (config.boot.loader.external.enable && !config.boot.isContainer) (lib.mkForce (pkgs.writeShellScript "install-bootloader-external" ''
          ${diffBoot}
          exec ${config.boot.loader.external.installHook} "$@"
        '')))
      ]);
    };
  };
}
