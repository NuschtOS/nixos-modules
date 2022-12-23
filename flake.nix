{
  inputs = {
    nixpkgs-lib.url = "github:nix-community/nixpkgs.lib";
  };

  outputs = { nixpkgs-lib, ... }:
    let
      inherit (nixpkgs-lib) lib;
      ls = dir: lib.attrNames (builtins.readDir (./. + "/${dir}"));
      importToAttr = dir: inputAttr: lib.listToAttrs (map (file: { name = lib.removeSuffix ".nix" file; value = import (./. + "/${dir}/${file}") inputAttr; }) (ls dir));
    in
    {
      lib = inputAttr: importToAttr "lib" inputAttr;
      nixosModules = inputAttr: importToAttr "modules" inputAttr;
      nixosModule = _: {
        imports = (dir: map (file: ./. + "/${dir}/${file}") (ls dir)) "modules";
      };
    };
}
