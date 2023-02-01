{ config, lib, libS, ... }:

let
  cfgP = config.programs.ssh;
  cfgS = config.services.openssh;
in
{
  options = {
    programs.ssh = {
      addPopularKnownHosts = libS.mkOpinionatedOption "add ssh public keys of popular websites to known_hosts";
      recommendedDefaults = libS.mkOpinionatedOption "set recommend and secure default settings";
    };

    services.openssh = {
      fixPermissions = libS.mkOpinionatedOption "fix host key permissions to prevent lock outs";
    };
  };

  config = lib.mkIf cfgP.addPopularKnownHosts {
    programs.ssh = {
      extraConfig = lib.mkIf cfgP.recommendedDefaults ''
        # hard complain about wrong knownHosts
        StrictHostKeyChecking accept-new
        # make automated host key rotation possible
        UpdateHostKeys yes
        # fetch host keys via DNS and trust them
        VerifyHostKeyDNS yes
      '';
      knownHosts = lib.mkMerge [
        (libS.mkPubKey "github.com" "ssh-rsa" "AAAAB3NzaC1yc2EAAAABIwAAAQEAq2A7hRGmdnm9tUDbO9IDSwBK6TbQa+PXYPCPy6rbTrTtw7PHkccKrpp0yVhp5HdEIcKr6pLlVDBfOLX9QUsyCOV0wzfjIJNlGEYsdlLJizHhbn2mUjvSAHQqZETYP81eFzLQNnPHt4EVVUh7VfDESU84KezmD5QlWpXLmvU31/yMf+Se8xhHTvKSCZIFImWwoG6mbUoWf9nzpIoaSjB+weqqUUmpaaasXVal72J+UX2B+2RPW3RcT0eOzQgqlJL3RKrTJvdsjE3JEAvGq3lGHSZXy28G3skua2SmVi/w4yCE6gbODqnTWlg7+wC604ydGXA8VJiS5ap43JXiUFFAaQ==")
        (libS.mkPubKey "github.com" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=")
        (libS.mkPubKey "github.com" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl")
        (libS.mkPubKey "gitlab.com" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9")
        (libS.mkPubKey "gitlab.com" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=")
        (libS.mkPubKey "gitlab.com" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf")
        (libS.mkPubKey "git.openwrt.org" "ssh-rsa" "AAAAB3NzaC1yc2EAAAABIwAAAQEAtnM1w/A1uRZqZuYHhw4ASOe9mr3J2qKAa9K9zR8jG+B+NQVtYlIBSkmCFyP6OuydCmoRZ5Gs1I9pl/hEyi7ieEi6g9yww/JbV322cw04Tli46enIYDG1bnSxF6Qt4aXqvPhcObI3z/1Z3XR6weS1fiLDzLvzq+w1gNM77xExD4Mh27LTPkdwOWjkGa5joNx3EQUC3rzwxUqE4fhOT2Ii93h8FSAUXY9C32jkJj9x7vfaJEsCacs6YTiUKKxyzEB+TvFZdUtGtoRThX7UVICUCD2th/r3UeSp8ItWPg/KqzSg2pRfWeYszlVoD59JZ6YCupSjjRqZddghQc94Hev7oQ==")
        (libS.mkPubKey "git.openwrt.org" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBASOHg+tghASiZF0ClxYb/HEhUcqnD43I86YatRZSUsXNWLEd8yOzjOJExDHHaKtmZtQ/jfEMmoYbCjdEDOYm5g=")
        (libS.mkPubKey "git.openwrt.org" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIJZFpKQMaLM8bG9lAPfEpTBExrzuiTKMni7PgktmDbJe")
        (libS.mkPubKey "git.sr.ht" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABAQDZ+l/lvYmaeOAPeijHL8d4794Am0MOvmXPyvHTtrqvgmvCJB8pen/qkQX2S1fgl9VkMGSNxbp7NF7HmKgs5ajTGV9mB5A5zq+161lcp5+f1qmn3Dp1MWKp/AzejWXKW+dwPBd3kkudDBA1fa3uK6g1gK5nLw3qcuv/V4emX9zv3P2ZNlq9XRvBxGY2KzaCyCXVkL48RVTTJJnYbVdRuq8/jQkDRA8lHvGvKI+jqnljmZi2aIrK9OGT2gkCtfyTw2GvNDV6aZ0bEza7nDLU/I+xmByAOO79R1Uk4EYCvSc1WXDZqhiuO2sZRmVxa0pQSBDn1DB3rpvqPYW+UvKB3SOz")
        (libS.mkPubKey "git.sr.ht" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCj6y+cJlqK3BHZRLZuM+KP2zGPrh4H66DacfliU1E2DHAd1GGwF4g1jwu3L8gOZUTIvUptqWTkmglpYhFp4Iy4=")
        (libS.mkPubKey "git.sr.ht" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60")
      ];
    };

    systemd.tmpfiles.rules = lib.mkIf cfgS.fixPermissions [
      "d /etc 0755 root root -"
      "d /etc/ssh 0755 root root -"
      "f /etc/ssh/ssh_host_ed25519_key 0700 root root -"
      "f /etc/ssh/ssh_host_ed25519_key.pub 0744 root root -"
      "f /etc/ssh/ssh_host_rsa_key 0700 root root -"
      "f /etc/ssh/ssh_host_rsa_key.pub 0744 root root -"
    ];
  };
}
