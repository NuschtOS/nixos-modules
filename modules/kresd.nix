{ config, lib, pkgs, ... }:

{
  config = lib.mkIf config.services.kresd.enable {
    environment.systemPackages = with pkgs; [
      (writeShellScriptBin "kresd-cli" ''
        exec ${lib.getExe socat} - UNIX-CONNECT:/run/knot-resolver/control/''${1:-1}
      '')
    ];
  };
}
