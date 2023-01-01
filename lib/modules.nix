{ lib, ... }:

{
  mkRecursiveDefault = lib.mapAttrsRecursive (path: value: lib.mkDefault value);
}
