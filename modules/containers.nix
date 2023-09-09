{ config, lib, libS, ... }:

let
  cfg = config.virtualisation;
  cfgd = cfg.docker;
  cfgp = cfg.podman;
in
{
  options.virtualisation = {
    docker = {
      aggresiveAutoPrune = libS.mkOpinionatedOption "configure aggresive auto prune which removes everything unreferenced by running containers. This includes named volumes and mounts should be used instead";

      recommendedDefaults = libS.mkOpinionatedOption "set recommended and maintenance reducing default settings";
    };

    podman.recommendedDefaults = libS.mkOpinionatedOption "set recommended and maintenance reducing default settings";
  };

  config = {
    virtualisation = {
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
          iptables = useIPTables;
          ip6tables = useIPTables;
          ipv6 = true;
          # userland proxy is slow, does not give back ports and if iptables/nftables is avaible just worsefgd.aggresiveAutoPrune
          userland-proxy = false;
        };
        autoPrune = lib.mkIf cfgd.aggresiveAutoPrune {
          enable = true;
          flags = [
            "--all"
            "--external"
            "--force"
            "--volumes"
          ];
        };
      };

      podman = {
        autoPrune.enable = lib.mkIf cfgp.recommendedDefaults true;
        defaultNetwork.settings.dns_enabled = lib.mkIf cfgp.recommendedDefaults true;
      };
    };
  };
}
