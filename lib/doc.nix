{ lib, pkgs, ... }:

rec {
  mkOptionsJSON = modules: let
    inherit (lib.evalModules {
      modules = lib.singleton {
        config._module.check = false;
      } ++ modules;
    }) options;
    filteredOptions = lib.filterAttrs (key: _: key != "_module") options;
  in pkgs.nixosOptionsDoc {
    options = filteredOptions;
    warningsAreErrors = false;
  };

  # based on https://github.com/j-brn/nixos-vfio/blob/master/lib/mkModuleDoc.nix
  mkModuleDoc = { modules, urlPrefix }: let
    url = lib.escape [ ":" "." "-" ] urlPrefix;
  in pkgs.runCommand "options.md" { } /* bash */ ''
    mkdir $out
    cat ${(mkOptionsJSON modules).optionsCommonMark} \
      | sed -r -e 's|\[/nix/store/.+\-source/(.+\.nix)\]|[\1]|g' \
        -e 's|\[/nix/store/.+\-source/(.+)\]|[\1/default\.nix]|g' \
        -e 's|\[flake\\.nix\\#nixosModules\\.(\w+)\/default\.nix\]|\[modules\/\1\/default\.nix\]|g' \
        -e 's|file\:///nix/store/.+\-source/(.+\.nix)|${url}\1|g' \
        -e 's|file\:///nix/store/.+\-source/(.+)\)|${url}/\1/default\.nix\)|g' \
      > $out/options.md
  '';

  mkMdBook = { projectName, moduleDoc }: with pkgs; stdenv.mkDerivation {
    name = "${projectName}-docs";
    nativeBuildInputs = [ mdbook ];
    buildCommand = ''
      mkdir src

      cp ${pkgs.substituteAll {
        src = ./book.toml;
        inherit projectName;
      }} book.toml
      echo -e "# Summary\n\n- [Options](options.md)" > src/SUMMARY.md
      ln -s ${moduleDoc}/options.md ./src

      mdbook build
      mv book/html $out
    '';
  };
}
