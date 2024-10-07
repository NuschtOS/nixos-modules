{ config, lib, ... }:

let
  cfg = config.security.acme;
in
{
  options.security.acme.staging = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      If set to true, use Let's Encrypt's staging environment instead of the production one.
      The staging environment has much higher rate limits but does *not* generate fully signed certificates.
      This is great for testing when the normla rate limit is hit fast and impacts other people on the same IP.
      See <https://letsencrypt.org/docs/staging-environment> for more detail.
    '';
  };

  config = lib.mkIf cfg.staging {
    security.acme.defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";
  };
}
