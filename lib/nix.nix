{ lib, ... }:

{
  # taken from https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/misc/nix-daemon.nix#L828-L832
  # a builder can run code for `gcc.arch` and inferior architectures
  gcc-system-features = arch: [ "gccarch-${arch}" ]
    ++ map (x: "gccarch-${x}") lib.systems.architectures.inferiors.${arch};
}
