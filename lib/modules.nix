{ config, lib, ... }:

{
  mkOpinionatedOption = text: lib.mkOption {
    type = lib.types.bool;
    default = config.opinionatedDefaults;
    description = "Whether to ${text}.";
  };

  mkRecursiveDefault = lib.mapAttrsRecursive (_: lib.mkDefault);
}
