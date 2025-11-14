# NixOS Modules

Collection of opinionated, integrated and shared NixOS modules.

This includes features like:
- Backend independent LDAP/OAuth2 abstraction with service integration (see table below)
- More opinionated integrations on top of Portunus (Simple LDAP frontend), dex and oauth2-proxy
- Easy Postgres upgrades between major versions, easy installation of extensions including `pg_stat_statements` and timer for pg_repack
- Higher level configuration of Blackbox exporter's dnsProbes and httpProbes for Prometheus
- Easy integration of Matrix Synapse, Element Web and extra Oembed providers
- Check if network kernel modules could be missing in initrd and deterministic luks unlock order
- Configure Nextcloud Apps Memories Apps and properly setup efficient preview generation
- Predone Nginx config for Minio console and object storage (S3)
- Restricted nix remote builders which can only execute remote builds

and many smaller integrations like:

- git-delta
- Harmonia Nginx
- Mailman PostgreSQL
- Nginx TCP fast open
- Mastodon Bird UI patch
- Hostname check (borrowed from srvos as module)
- Nix diff system on activation and dry-activation
- Vaultwarden Nginx and Postgres
- Strace color patch
- ... and much more!

## LDPA & OAuth service support

| Name  | LDAP | OAuth |
|-------|------|-------|
| Gitea |  ✅  |  ✅   |
| Grafana | ❌ |  ✅   |
| Hedgedoc | ✅ | ❌ |
| Home-Assistant | ✅ | ❌ |
| Mastodon | ✅ | ✅ |

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

  outputs = { nixos-modules, ... }: {
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
This requires manually providing `libS` as a module argument.
The following snippet is equal to what adding all modules is doing:
```nix
{
  _module.args.libS = lib.mkOverride 1000 (self.lib { inherit lib config; });
}
```

## Available options

Please use our [options search site](https://search.xn--nschtos-n2a.de/?scope=NixOS%20Modules) to find and browse all available options. It supports searching for option names, wildcards and can be [self hosted](https://github.com/NuschtOS/search), too.

## Compatibility note

Sometimes we use options from yet-to-be-merged Nixpkgs pull requests.
Normally that fails evaluation because lib.mkIf also checks the types if the condition is false.
This can be hacked around by using `lib.optional*` or `if ... then ... else ...` but then the option does not work.
To close that gap we offer a nixpkgs fork named [nüschtpkgs](https://github.com/NuschtOS/nuschtpkgs).
It contains the latest stable branch and unstable and it is daily rebased.
We use CI checks to ensure that the modules evaluate on the current stable and unstable branch and some selected forks.

## Design

* Modules should never change the configuration without setting an option
* Unless the global overwrite ``opinionatedDefaults = true`` is set which activates most settings.
  Unless you know what you are doing, you shouldn't really set this option.

## Similar projects

* <https://github.com/nix-community/srvos>
* <https://gitea.c3d2.de/C3D2/nix-user-module>

## Contact

For bugs and issues please open an issue in this repository.

If you want to chat about things or have ideas, feel free to join the [Matrix chat](https://matrix.to/#/#nuschtos:c3d2.de).
