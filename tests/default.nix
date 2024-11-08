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
} // lib.optionalAttrs (lib.versionAtLeast lib.version "24.11") {
  # https://github.com/NuschtOS/nixos-modules/issues/39
  hound-repos = mkTest {
    module = {
      services.hound = {
        enable = true;
        repos = [ "https://github.com/NuschtOS/nixos-modules.git" ];
      };
    };
  };
} // {
  grafana-no-nginx = mkTest {
    module = {
      services.grafana = {
        enable = true;
        settings.security = {
          admin_password = "secure";
          secret_key = "secure";
        };
      };
    };
  };

  matrix-nginx-with-socket = mkTest {
    module = {
      services = {
        matrix-synapse = {
          enable = true;
          domain = "example.org";
          listenOnSocket = true;
          element-web = {
            enable = true;
            domain = "example.org";
          };
        };

        nginx.enable = true;
      };
    };
  };

  matrix-no-nginx = mkTest {
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

  nextcloud-plain = mkTest {
    module = {
      services.nextcloud = {
        enable = true;
        config.adminpassFile = "/password";
        hostName = "example.com";
      };
    };
  };

  # https://github.com/NuschtOS/nixos-modules/issues/156
  renovate-plain = mkTest {
    module = {
      services.renovate = {
        enable = true;
      };
    };
  };

  vaultwarden-no-nginx = mkTest {
    module = {
      services.vaultwarden = {
        enable = true;
        domain = "example.com";
      };
    };
  };
})
