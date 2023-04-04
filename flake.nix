{
  description = "Opinionated shared nixos configurations";

  inputs = {
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  };

  outputs = { self, nixpkgs-lib, ... }:
    let
      inherit (nixpkgs-lib) lib;
      src = builtins.filterSource (path: type: type == "directory" || lib.hasSuffix ".nix" (baseNameOf path)) ./.;
      ls = dir: lib.attrNames (builtins.readDir (src + "/${dir}"));
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
        lib' // {
          inherit (lib'.modules) mkOpinionatedOption mkRecursiveDefault;
          inherit (lib'.ssh) mkPubKey;
        };

      nixosModules = lib.foldr (a: b: a // b) { } (map
        (
          name: {
            "${lib.removeSuffix ".nix" name}" = {
              imports = [ ./modules/${name} ];
            };
          }
        )
        (ls "modules"));

      nixosModule = { config, ... }: {
        _module.args.libS = lib.mkOverride 1000 (self.lib { inherit lib config; });

        imports = fileList "modules";
      };
    };
}
