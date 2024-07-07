# NixOS Modules

Shared and opinionated NixOS modules

## Usage

Add or merge the following settings to your `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NuschtOS/nuschtpkgs/nixos-unstable";
    nixos-modules = {
      url = "github:NuschtOS/nixos-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { nixos-modules }: {
    nixosConfigurations.HOSTNAME = {
      modules = [
       nixos-modules.nixosModule
    ];
  };
}
```

If your `nixpkgs` input is named differently, update the `follows` to your name accordingly.

By using `nixos-modules.nixosModule`, all available modules are imported.
It is also possible to only import a subset of modules.
Under `nixos-modules.nixosModules.<name>` we expose all modules available in the modules directory.

> [!NOTE]
> Sometimes we use options from yet-to-be-merged Nixpkgs pull requests.
> We offer a nixpkgs fork named [nüschtpkgs](https://github.com/NuschtOS/nuschtpkgs) to close that gap.
> We offer the latest stable branch and unstable and it is daily rebased.

## Design

* Modules should never change the configuration without setting an option
* Unless the global overwrite ``opinionatedDefaults = true`` is set which activates most settings.
  Unless you know what you are doing, you shouldn't really set this option.

## Similar projects

* <https://github.com/numtide/srvos>
* <https://gitea.c3d2.de/C3D2/nix-user-module>
