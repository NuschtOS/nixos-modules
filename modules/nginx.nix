{ config, lib, ... }:

{
  options.services.nginx.openFirewall = lib.mkOption {
    description = lib.mdDoc "Wether to open the firewall port for the http (80) and https (443) default ports.";
    default = false;
    type = lib.types.bool;
  };

  config = lib.mkIf config.services.nginx.openFirewall {
    networking.firewall.allowedTCPPorts = [ 80 443 ];
  };
}
