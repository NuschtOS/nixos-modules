{ config, lib, ... }:

let 
  cfg = config.services.portunus;
in
{
  options.services.portunus = {
    externalIp4 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv4 of portunus instance. This is used in the addToHosts option.";
    };

    externalIp6 = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      description = lib.mdDoc "Internal IPv6 of portunus instance. This is used in the addToHosts option.";
    };

    addToHosts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = lib.mdDoc "Wether to add a hosts entry for the portunus domain pointing to externalIp";
    };
  };

  config = lib.mkIf config.services.portunus.addToHosts {
    networking.hosts =  {
      ${cfg.externalIp4} = [ cfg.domain ];
      ${cfg.externalIp6} = [ cfg.domain ];
  };
}
