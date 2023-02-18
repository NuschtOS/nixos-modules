{ config, lib, ... }:

{
  mkOpinionatedOption = text: lib.mkOption {
    type = lib.types.bool;
    default = config.opinionatedDefaults;
    description = lib.mdDoc "Whether to ${text}.";
  };

  mkRecursiveDefault = lib.mapAttrsRecursive (_: lib.mkDefault);
}
