{
  outputs = _:
    let
      dirs = dir: builtins.attrNames (builtins.readDir (./. + "/${dir}"));
      importToAttr = dir: inputAttr: builtins.listToAttrs (map (p: { name = p; value = import (./. + "/${dir}/${p}") inputAttr; }) (dirs dir));
    in
    {
      lib = inputAttr: importToAttr "lib" inputAttr;
      nixosModules = inputAttr: importToAttr "modules" inputAttr;
      nixosModule = _: {
        imports = (dir: map (p: ./. + "/${dir}/${p}") (dirs dir)) "modules";
      };
    };
}
