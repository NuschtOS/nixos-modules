{ config, lib, libS, ... }:

let
  cfg = config.services.gitea;
in
{
  options = {
    services.gitea.recommendedDefaults = libS.mkOpinionatedOption "set recommended, secure default settings";
  };

  config = lib.mkIf cfg.enable {
    services.gitea = lib.mkIf cfg.recommendedDefaults (libS.modules.mkRecursiveDefault {
      rootUrl = "https://${config.services.gitea.domain}/";
      settings = {
        cors = {
          ALLOW_DOMAIN = config.services.gitea.domain;
          ENABLED = true;
          SCHEME = "https";
        };
        other.SHOW_FOOTER_VERSION = false;
        repository.ACCESS_CONTROL_ALLOW_ORIGIN = config.services.gitea.domain;
        server = {
          ENABLE_GZIP = true;
          SSH_SERVER_CIPHERS = "chacha20-poly1305@openssh.com, aes256-gcm@openssh.com, aes128-gcm@openssh.com";
          SSH_SERVER_KEY_EXCHANGES = "curve25519-sha256@libssh.org, ecdh-sha2-nistp521, ecdh-sha2-nistp384, ecdh-sha2-nistp256, diffie-hellman-group14-sha1";
          SSH_SERVER_MACS = "hmac-sha2-256-etm@openssh.com, hmac-sha2-256, hmac-sha1";
        };
        session = {
          COOKIE_SECURE = true;
          PROVIDER = "db";
          SAME_SITE = "strict";
          SESSION_LIFE_TIME = 604800; # 7 days
        };
        "ssh.minimum_key_sizes" = {
          ECDSA = -1;
          RSA = 4095;
        };
        time.DEFAULT_UI_LOCATION = config.time.timeZone;
        update_checker.ENABLED = false;
      };
    });
  };
}
