{ config, lib, libS, ... }:

let
  cfg = config.virtualisation;
  cfgd = cfg.docker;
  cfgp = cfg.podman;
in
{
  options.virtualisation = {
    docker = {
      aggressiveAutoPrune = libS.mkOpinionatedOption "configure aggressive auto pruning which removes everything unreferenced by running containers. This includes named volumes and mounts should be used instead";

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and maintenance reducing default settings";
    };

    podman = {
      aggressiveAutoPrune = libS.mkOpinionatedOption "configure aggressive auto pruning which removes everything unreferenced by running containers. This includes named volumes and mounts should be used instead";

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and maintenance reducing default settings";
    };
  };

  imports = [
    (lib.mkRemovedOptionModule ["virtualisation" "docker" "aggresiveAutoPrune"] "use virtualisation.docker.aggressiveAutoPrune")
  ];

  config = {
    virtualisation = let
      autoPruneFlags = [
        "--all"
        "--volumes"
      ];
    in {
      containers.registries.search = lib.mkIf cfgp.recommendedDefaults [
        "docker.io"
        "quay.io"
        "ghcr.io"
        "gcr.io"
      ];

      docker = {
        daemon.settings = let
          useIPTables = !config.networking.nftables.enable;
        in lib.mkIf cfgd.recommendedDefaults {
          fixed-cidr-v6 = "fd00::/80"; # TODO: is this a good idea for all networks?
          iptables = lib.mkIf useIPTables true;
          ip6tables = lib.mkIf useIPTables true;
          ipv6 = true;
          # userland proxy is slow, does not give back ports and if iptables/nftables is available it is just worse
          userland-proxy = lib.mkIf useIPTables false;
        };

        autoPrune = lib.mkIf cfgd.aggressiveAutoPrune {
          enable = true;
          flags = autoPruneFlags;
        };
      };

      podman = {
        autoPrune = lib.mkIf cfgp.aggressiveAutoPrune {
          enable = true;
          flags = autoPruneFlags;
        };
        defaultNetwork.settings.dns_enabled = lib.mkIf cfgp.recommendedDefaults true;
      };
    };
  };
}
