{
  description = "Opinionated shared nixos configurations";

  inputs = {
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  };

  outputs = { self, nixpkgs-lib, ... }:
    let
      inherit (nixpkgs-lib) lib;
      ls = dir: lib.attrNames (builtins.readDir (./. + "/${dir}"));
      fileList = dir: map (file: ./. + "/${dir}/${file}") (ls dir);
      importDirToKey = dir: args: lib.listToAttrs (map
        (file: {
          name = lib.removeSuffix ".nix" file;
          value = import (./. + "/${dir}/${file}") args;
        })
        (ls dir)
      );
    in
    {
      lib = args:
        let
          lib' = importDirToKey "lib" args;
        in
        (lib' // {
          inherit (lib'.modules) mkOpinionatedOption mkRecursiveDefault;
          inherit (lib'.ssh) mkPubKey;
        });

      nixosModules = args: importDirToKey "modules" args;
      nixosModule = { config, ... }@args: {
        _module.args = lib.optionalAttrs (args ? libS) {
          libS = self.lib { inherit lib config; };
        };

        imports = fileList "modules";
      };
    };
}
