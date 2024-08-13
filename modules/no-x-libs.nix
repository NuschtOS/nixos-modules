{ config, lib, ... }:

# this module extends the environment.noXlibs setting with yet to merge and upstream overwrites
{
  config = lib.mkIf config.environment.noXlibs {
    # nixpkgs.overlays = lib.singleton (lib.const (super: {
    # }));
  };
}
