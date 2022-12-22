{ config, lib, ... }:

{
  options.services.nginx.openFirewall = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = lib.mdDoc "Wether to open the firewall port for the http (80) and https (443) default ports.";
  };

  config = lib.mkIf config.services.nginx.enable {
    networking.firewall.allowedTCPPorts = lib.mkIf config.services.nginx.openFirewall [ 80 443 ];
  };
}
