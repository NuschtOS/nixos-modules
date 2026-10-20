{ config, lib, ... }:

{
  options = {
    users.showFailedUnitsOnLogin = lib.mkEnableOption "show failed systemd units on interactive login";
  };

  config = lib.mkIf config.users.showFailedUnitsOnLogin {
    environment.loginShellInit = /* sh */ ''
      if [[ $- == *i* ]]; then
        systemctl --failed --full --no-pager --quiet || true
        if [[ -v DBUS_SESSION_BUS_ADDRESS ]]; then
          systemctl --failed --full --no-pager --user --quiet || true
        fi
      fi
    '';
  };
}
