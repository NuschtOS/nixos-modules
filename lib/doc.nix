{ lib, pkgs, ... }:

{
  # based on https://github.com/j-brn/nixos-vfio/blob/master/lib/mkModuleDoc.nix
  mkModuleDoc = { module, urlPrefix }: let
    inherit (lib.evalModules {
      modules = [ {
        config._module.check = false;
      } module ];
    }) options;
    filteredOptions = lib.filterAttrs (key: _: key != "_module") options;
    docs = pkgs.nixosOptionsDoc {
      options = filteredOptions;
      warningsAreErrors = false;
    };
    url = lib.escape [ ":" "." "-" ] urlPrefix;
  in pkgs.runCommand "options.md" { } /* bash */ ''
    mkdir $out
    cat ${docs.optionsCommonMark} \
      | sed -r -e 's|\[/nix/store/.+\-source/(.+\.nix)\]|[\1]|g' \
        -e 's|\[/nix/store/.+\-source/(.+)\]|[\1/default\.nix]|g' \
        -e 's|\[flake\\.nix\\#nixosModules\\.(\w+)\/default\.nix\]|\[modules\/\1\/default\.nix\]|g' \
        -e 's|file\:///nix/store/.+\-source/(.+\.nix)|${url}\1|g' \
        -e 's|file\:///nix/store/.+\-source/(.+)\)|${url}/\1/default\.nix\)|g' \
      > $out/options.md
  '';
}
