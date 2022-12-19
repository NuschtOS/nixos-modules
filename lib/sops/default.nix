{ config, lib }:

{
  permissionForUser = name: {
    owner = config.users.users.${name}.name;
    group = config.users.groups.${name}.name;
  };
}
