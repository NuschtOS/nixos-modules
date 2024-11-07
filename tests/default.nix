{ lib, pkgs, self, system }:

let
  mkTest = { module ? { } }: lib.nixosSystem {
    modules = [
      self.nixosModule
      # include a very basic config which contains fileSystem, etc. to avoid many assertions
      ({ modulesPath, ... }: {
        imports = lib.singleton "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix";
      })
      module
    ];
    inherit system;
  };
in
lib.mapAttrs (name: value: value.config.system.build.toplevel) ({
  no-config = mkTest { };

  # https://github.com/NuschtOS/nixos-modules/issues/2
  acme-staging = mkTest {
    module = {
      security.acme.staging = true;
    };
  };

  matrix-synapse-no-nginx = mkTest {
    module = {
      services.matrix-synapse = {
        enable = true;
        domain = "example.org";
        element-web = {
          enable = true;
          domain = "example.org";
        };
      };
    };
  };

  # https://github.com/NuschtOS/nixos-modules/issues/160
  matrix-element-same-domain = mkTest {
    module = {
      services = {
        matrix-synapse = {
          enable = true;
          domain = "example.org";
          element-web = {
            enable = true;
            domain = "example.org";
          };
        };

        nginx.enable = true;
      };
    };
  };
}
