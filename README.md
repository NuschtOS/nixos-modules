# NixOS Modules

Opinionated, shared NixOS configurations.

## Usage

Add or merge the following settings to your `flake.nix`:

```nix
{
  inputs = {
    nixos-modules.url = "github:SuperSandro2000/nixos-modules";
  };

  outputs = { nixos-modules }: {
    nixosConfigurations.HOSTNAME = {
      modules = [
       nixos-modules.nixosModule
    ];
  };
}
```

## Design

* Modules should never change the configuration without setting an option
* Unless the global overwrite ``opinionatedDefaults = true`` is set which activates most settings.

## Similar projects

* <https://github.com/numtide/srvos>
* <https://gitea.c3d2.de/C3D2/nix-user-module>
