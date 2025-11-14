{ config, lib, libS, ... }:

let
  cfg = config.services.chrony;
in
{
  options = {
    networking.recommendedTimeServers = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to configure recommended stratum 1 time servers.";
    };

    services.chrony = {
      configureServer = libS.mkOpinionatedOption "configure recommended server settings";

      openFirewall = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to open the firewall for the ntp protocol of chrony.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    networking = {
      firewall = lib.mkIf cfg.openFirewall {
        allowedTCPPorts = [ 123 ];
        allowedUDPPorts = [ 123 ];
      };
      recommendedTimeServers = lib.mkIf cfg.configureServer (lib.mkDefault true);
      timeServers = lib.mkIf config.networking.recommendedTimeServers [
        "ntp0.fau.de"
        "ntp1.hetzner.de"
        "ntps1-0.eecsit.tu-berlin.de"
        "ntps1-0.fh-mainz.de"
        "ptbtime1.ptb.de"
        "rustime01.rus.uni-stuttgart.de"
        "zeit.fu-berlin.de"
      ];
    };

    services.chrony = lib.mkIf cfg.configureServer {
      openFirewall = true;
      extraConfig = ''
        allow
      '';
    };
  };
}
