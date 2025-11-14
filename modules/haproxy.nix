{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.haproxy;
in
{
  options = {
    services.haproxy = {
      compileWithAWSlc = libS.mkOpinionatedOption "compile nginx with aws-lc as crypto library";
    };
  };

  config = lib.mkIf cfg.enable {
    services.haproxy = {
      package = lib.mkIf cfg.compileWithAWSlc (pkgs.haproxy.override { sslLibrary = "aws-lc"; });

      config = lib.mkBefore (''
        global
          ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
      '' + lib.optionalString (!cfg.compileWithAWSlc) ''
          ssl-dh-param-file ${config.security.dhparams.params.haproxy.path}
      '');
    };
  };
}
