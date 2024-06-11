{ lib, ... }:

{
  mkUserGroupOption = lib.mkOption {
    type = with lib.types; nullOr str;
    default = null;
    description = "Restrict logins to users in this group";
  };
}
