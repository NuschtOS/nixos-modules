{ lib, ... }:

{
  options.opinionatedDefaults = lib.mkEnableOption "opinionated defaults. This option is *not* recommended to be set";

  imports = [
    (lib.mkRemovedOptionModule ["debugging" "enable"] "Because we never really used it.")
  ];
}
