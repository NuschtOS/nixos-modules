{ config, lib, ... }:

{
  options = {
    users.showFailedUnitsOnLogin = lib.mkEnableOption "show failed systemd units on interactive login";
  };

  config = lib.mkIf config.users.showFailedUnitsOnLogin {
    environment.interactiveShellInit = /* sh */ ''
      # raise some awareness towards failed services
      systemctl --failed --full --no-pager --quiet || true
    '';
  };
}
