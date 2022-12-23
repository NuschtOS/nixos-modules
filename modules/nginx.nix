{ config, lib, ... }:

let
  cfg = config.services.nginx;
in
{
  options.services.nginx.openFirewall = lib.mkOption {
    type = lib.types.bool;
    default = config.opinionatedDefaults;
    description = lib.mdDoc "Wether to open the firewall port for the http (80) and https (443) default ports.";
  };

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 80 443 ];
  };
}
