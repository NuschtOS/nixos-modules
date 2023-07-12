{ config, lib, libS, pkgs, ... }:

let
  cfg = config.services.mastodon;
  cfgl = cfg.ldap;
  inherit (config.security) ldap;
in
{
  options.services.mastodon = {
    ldap = {
      enable = lib.mkEnableOption (lib.mdDoc "login only via LDAP");

      userGroup = libS.ldap.mkUserGroupOption;
    };

    enableBirdUITheme = lib.mkEnableOption (lib.mdDoc "Bird UI Theme");
  };

  config.services.mastodon = {
    package = lib.mkIf cfg.enableBirdUITheme (pkgs.mastodon.overrideAttrs (_: with pkgs; let
      src = fetchFromGitHub {
        owner = "mstdn";
        repo = "Bird-UI-Theme-Admins";
        rev = "a050e72cc2508f60c5d9710ce49f81fe3ddccaaa";
        hash = "sha256-Oio6pOGSAE6jpuE3r8Il0khXAWN905fnFYvZrLFn/Is=";
      };
    in {
      mastodonModules = mastodon.mastodonModules.overrideAttrs (oldAttrs: {
        pname = "mastodon-birdui-theme";

        nativeBuildInputs = oldAttrs.nativeBuildInputs ++ [
          rsync
          xorg.lndir
        ];

        postPatch = ''
          rsync -r ${src}/mastodon/ .
        '';
      });

      postBuild = ''
        cp ${src}/mastodon/config/themes.yml config/themes.yml
      '';
    }));

    extraConfig = lib.mkIf cfgl.enable {
      LDAP_ENABLED = "true";
      LDAP_BASE = ldap.userBaseDN;
      LDAP_BIND_DN = ldap.bindDN;
      LDAP_HOST = ldap.domainName;
      LDAP_METHOD = "simple_tls";
      LDAP_PORT = toString ldap.port;
      LDAP_UID = ldap.userField;
      # convert .,- (space) in LDAP usernames to underscore, otherwise those users cannot log in
      LDAP_UID_CONVERSION_ENABLED = "true";
      LDAP_SEARCH_FILTER = ldap.searchFilterWithGroupFilter cfgl.userGroup "(|(%{uid}=%{email})(%{mail}=%{email}))";
    };
  };

  config.services.portunus.seedSettings.groups = lib.optional (cfgl.userGroup != null) {
    long_name = "Mastodon Users";
    name = cfgl.userGroup;
    permissions = { };
  };
}
