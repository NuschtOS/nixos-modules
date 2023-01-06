{ config, lib, ... }:

{
  mkOpinionatedOption = text: lib.mkOption {
    type = lib.types.bool;
    default = config.opinionatedDefaults;
    description = lib.mdDoc "Wether to ${text}.";
  };

  mkRecursiveDefault = lib.mapAttrsRecursive (_path: value: lib.mkDefault value);
}
