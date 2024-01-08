{
  description = "Opinionated shared nixos configurations";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, flake-utils, nixpkgs, ... }:
    let
      inherit (nixpkgs) lib;
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
      lib = args: let
        lib' = importDirToKey "lib" args;
      in lib' // {
        # some functions get promoted to be directly under libS
        inherit (lib'.doc) mkModuleDoc mkMdBook;
        inherit (lib'.modules) mkOpinionatedOption mkRecursiveDefault;
        inherit (lib'.ssh) mkPubKey;
      };

      # NOTE: requires libS to be imported once which can be done like:
      # _module.args.libS = lib.mkOverride 1001 (nixos-modules.lib { inherit lib config; });
      nixosModules = lib.foldr (a: b: a // b) { } (map
        (name: {
          "${lib.removeSuffix ".nix" name}" = {
            imports = [
              # this must match https://gitea.c3d2.de/c3d2/nix-user-module/src/branch/master/flake.nix#L17 aka modules/default.nix,
              # otherwise the module system does not dedupe the import
              ./modules/default.nix
              ./modules/${name}
            ];
          };
        })
        (ls "modules")
      );

      nixosModule = { config, lib, ... }: {
        _module.args.libS = lib.mkOverride 1000 (self.lib { inherit lib config; });
        imports = fileList "modules";
      };
    } // flake-utils.lib.eachDefaultSystem (system: let
      libS = self.lib { config = { }; inherit lib; pkgs = nixpkgs.legacyPackages.${system}; };
    in {
      packages = rec {
        options-doc-md = libS.mkModuleDoc {
          modules = [
            ({ config, lib, ... }: {
              _module.args.libS = self.lib { inherit config lib; };
            })
            self.nixosModule
          ];
          urlPrefix = "https://github.com/SuperSandro2000/nixos-modules/tree/master/";
        };

        options-doc = libS.mkMdBook {
          projectName = "nixos-modules";
          moduleDoc = options-doc-md;
        };
      };
    });
}
