{ lib, ... }:

{
  mkUserGroupOption = lib.mkOption {
    type = with lib.types; nullOr str;
    default = null;
    description = lib.mdDoc "Restrict logins to users in this group";
  };
}
