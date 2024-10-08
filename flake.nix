{
  description = "Opinionated shared nixos configurations";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    # if changed, also update .github/workflows/flake-eval.yaml
    nixpkgs.url = "github:NuschtOS/nuschtpkgs/nixos-unstable";
    search = {
      url = "github:nuschtos/search";
      inputs = {
        flake-utils.follows = "flake-utils";
        nixpkgs.follows = "nixpkgs";
      };
    };
  };

  outputs = { self, flake-utils, nixpkgs, search, ... }:
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
        inherit (lib'.modules) mkOpinionatedOption mkRecursiveDefault;
        inherit (lib'.ssh) mkPubKey;
      };

      nixosConfigurations.test = lib.nixosSystem {
        modules = [
          self.nixosModule
          ({ modulesPath, ... }: {
            imports = lib.singleton "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix";
          })
        ];
        system = "x86_64-linux";
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
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      packages = {
        default = self.packages.${system}.debugging;

        debugging = pkgs.symlinkJoin {
          name = "debugging-tools";
          paths = import ./lib/debug-pkgs.nix pkgs;
        };

        search-page = search.packages.${system}.mkSearch {
          modules = [
            ({ config, lib, ... }: {
              _module.args = {
                libS = self.lib { inherit config lib; };
                inherit pkgs;
              };
              imports = [
                (pkgs.path + "/nixos/modules/misc/extra-arguments.nix")
              ];
            })
            self.nixosModule
          ];
          title = "NixOS Modules Search";
          urlPrefix = "https://github.com/NuschtOS/nixos-modules/tree/main/";
        };
      };
    });
}
