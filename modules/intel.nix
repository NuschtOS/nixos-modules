{ lib, ... }:

{
  imports = [
    # TODO: drop with nixos 25.05
    (lib.mkRemovedOptionModule ["hardware" "intelGPU"] "Please use hardware.intelgpu from nixos-hardware instead.")
  ];
}
