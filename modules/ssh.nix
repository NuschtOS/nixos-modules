{ config, lib, libS, pkgs, ... }:

let
  cfgP = config.programs.ssh;
  cfgS = config.services.openssh;

  sshKeygen = lib.getExe' cfgP.package "ssh-keygen";
in
{
  options = {
    programs.ssh = {
      addPopularKnownHosts = libS.mkOpinionatedOption "add ssh public keys of popular websites to known_hosts";
      addHelpOnHostkeyMismatch = libS.mkOpinionatedOption "show a ssh-keygen command to remove mismatching ssh knownhosts entries";
      recommendedDefaults = libS.mkOpinionatedOption "set recommend and secure default settings";
    };

    services.openssh = {
      fixPermissions = libS.mkOpinionatedOption "fix host key permissions to prevent lock outs";
      recommendedDefaults = libS.mkOpinionatedOption "set recommend and secure default settings";
      regenerateWeakRSAHostKey = libS.mkOpinionatedOption "regenerate weak (less than 4096 bits) RSA host keys.";
    };
  };

  config = {
    # TODO: there is no programs.ssh.enable, what to use instead?
    programs.ssh = {
      extraConfig = lib.mkIf cfgP.recommendedDefaults /* sshconfig */ ''
        # hard complain about wrong knownHosts
        StrictHostKeyChecking accept-new
        # make automated host key rotation possible
        UpdateHostKeys yes
        # fetch host keys via DNS and trust them
        VerifyHostKeyDNS yes
      '';
      knownHosts = lib.mkIf cfgP.addPopularKnownHosts (lib.mkMerge [
        # Codeberg
        (libS.mkPubKey "codeberg.org" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABAQC8hZi7K1/2E2uBX8gwPRJAHvRAob+3Sn+y2hxiEhN0buv1igjYFTgFO2qQD8vLfU/HT/P/rqvEeTvaDfY1y/vcvQ8+YuUYyTwE2UaVU5aJv89y6PEZBYycaJCPdGIfZlLMmjilh/Sk8IWSEK6dQr+g686lu5cSWrFW60ixWpHpEVB26eRWin3lKYWSQGMwwKv4LwmW3ouqqs4Z4vsqRFqXJ/eCi3yhpT+nOjljXvZKiYTpYajqUC48IHAxTWugrKe1vXWOPxVXXMQEPsaIRc2hpK+v1LmfB7GnEGvF1UAKnEZbUuiD9PBEeD5a1MZQIzcoPWCrTxipEpuXQ5Tni4mN")
        (libS.mkPubKey "codeberg.org" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBL2pDxWr18SoiDJCGZ5LmxPygTlPu+cCKSkpqkvCyQzl5xmIMeKNdfdBpfbCGDPoZQghePzFZkKJNR/v9Win3Sc=")
        (libS.mkPubKey "codeberg.org" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIIVIC02vnjFyL+I4RHfvIGNtOgJMe769VTF1VR4EB3ZB")
        # GitHub
        # https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints
        (libS.mkPubKey "github.com" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=")
        (libS.mkPubKey "github.com" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=")
        (libS.mkPubKey "github.com" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl")
        # GitLab
        (libS.mkPubKey "gitlab.com" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABAQCsj2bNKTBSpIYDEGk9KxsGh3mySTRgMtXL583qmBpzeQ+jqCMRgBqB98u3z++J1sKlXHWfM9dyhSevkMwSbhoR8XIq/U0tCNyokEi/ueaBMCvbcTHhO7FcwzY92WK4Yt0aGROY5qX2UKSeOvuP4D6TPqKF1onrSzH9bx9XUf2lEdWT/ia1NEKjunUqu1xOB/StKDHMoX4/OKyIzuS0q/T1zOATthvasJFoPrAjkohTyaDUz2LN5JoH839hViyEG82yB+MjcFV5MU3N1l1QL3cVUCh93xSaua1N85qivl+siMkPGbO5xR/En4iEY6K2XPASUEMaieWVNTRCtJ4S8H+9")
        (libS.mkPubKey "gitlab.com" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBFSMqzJeV9rUzU4kWitGjeR4PWSa29SPqJ1fVkhtj3Hw9xjLVXVYrU9QlYWrOLXBpQ6KWjbjTDTdDkoohFzgbEY=")
        (libS.mkPubKey "gitlab.com" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIAfuCHKVTjquxvt6CM6tdG4SLp1Btn/nOeHHE5UOzRdf")
        # OpenWrt Git
        (libS.mkPubKey "git.openwrt.org" "ssh-rsa" "AAAAB3NzaC1yc2EAAAABIwAAAQEAtnM1w/A1uRZqZuYHhw4ASOe9mr3J2qKAa9K9zR8jG+B+NQVtYlIBSkmCFyP6OuydCmoRZ5Gs1I9pl/hEyi7ieEi6g9yww/JbV322cw04Tli46enIYDG1bnSxF6Qt4aXqvPhcObI3z/1Z3XR6weS1fiLDzLvzq+w1gNM77xExD4Mh27LTPkdwOWjkGa5joNx3EQUC3rzwxUqE4fhOT2Ii93h8FSAUXY9C32jkJj9x7vfaJEsCacs6YTiUKKxyzEB+TvFZdUtGtoRThX7UVICUCD2th/r3UeSp8ItWPg/KqzSg2pRfWeYszlVoD59JZ6YCupSjjRqZddghQc94Hev7oQ==")
        (libS.mkPubKey "git.openwrt.org" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBASOHg+tghASiZF0ClxYb/HEhUcqnD43I86YatRZSUsXNWLEd8yOzjOJExDHHaKtmZtQ/jfEMmoYbCjdEDOYm5g=")
        (libS.mkPubKey "git.openwrt.org" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIJZFpKQMaLM8bG9lAPfEpTBExrzuiTKMni7PgktmDbJe")
        # SourceHut
        (libS.mkPubKey "git.sr.ht" "ssh-rsa" "AAAAB3NzaC1yc2EAAAADAQABAAABAQDZ+l/lvYmaeOAPeijHL8d4794Am0MOvmXPyvHTtrqvgmvCJB8pen/qkQX2S1fgl9VkMGSNxbp7NF7HmKgs5ajTGV9mB5A5zq+161lcp5+f1qmn3Dp1MWKp/AzejWXKW+dwPBd3kkudDBA1fa3uK6g1gK5nLw3qcuv/V4emX9zv3P2ZNlq9XRvBxGY2KzaCyCXVkL48RVTTJJnYbVdRuq8/jQkDRA8lHvGvKI+jqnljmZi2aIrK9OGT2gkCtfyTw2GvNDV6aZ0bEza7nDLU/I+xmByAOO79R1Uk4EYCvSc1WXDZqhiuO2sZRmVxa0pQSBDn1DB3rpvqPYW+UvKB3SOz")
        (libS.mkPubKey "git.sr.ht" "ecdsa-sha2-nistp256" "AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBCj6y+cJlqK3BHZRLZuM+KP2zGPrh4H66DacfliU1E2DHAd1GGwF4g1jwu3L8gOZUTIvUptqWTkmglpYhFp4Iy4=")
        (libS.mkPubKey "git.sr.ht" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIMZvRd4EtM7R+IHVMWmDkVU3VLQTSwQDSAvW0t2Tkj60")
        # Hetzner StorageBox
        # https://docs.hetzner.com/storage/storage-box/general/#ssh-host-keys
        # port 22
        (libS.mkPubKey "*.your-storagebox.de" "ssh-rsa" "AAAAB3NzaC1yc2EAAAABIwAAAQEA5EB5p/5Hp3hGW1oHok+PIOH9Pbn7cnUiGmUEBrCVjnAw+HrKyN8bYVV0dIGllswYXwkG/+bgiBlE6IVIBAq+JwVWu1Sss3KarHY3OvFJUXZoZyRRg/Gc/+LRCE7lyKpwWQ70dbelGRyyJFH36eNv6ySXoUYtGkwlU5IVaHPApOxe4LHPZa/qhSRbPo2hwoh0orCtgejRebNtW5nlx00DNFgsvn8Svz2cIYLxsPVzKgUxs8Zxsxgn+Q/UvR7uq4AbAhyBMLxv7DjJ1pc7PJocuTno2Rw9uMZi1gkjbnmiOh6TTXIEWbnroyIhwc8555uto9melEUmWNQ+C+PwAK+MPw==")
        # port 23
        (libS.mkPubKey "*.your-storagebox.de" "ecdsa-sha2-nistp521" "AAAAE2VjZHNhLXNoYTItbmlzdHA1MjEAAAAIbmlzdHA1MjEAAACFBAGK0po6usux4Qv2d8zKZN1dDvbWjxKkGsx7XwFdSUCnF19Q8psHEUWR7C/LtSQ5crU/g+tQVRBtSgoUcE8T+FWp5wBxKvWG2X9gD+s9/4zRmDeSJR77W6gSA/+hpOZoSE+4KgNdnbYSNtbZH/dN74EG7GLb/gcIpbUUzPNXpfKl7mQitw==")
        (libS.mkPubKey "*.your-storagebox.de" "ssh-rsa" "AAAAB3NzaC1yc2EAAAABIwAAAQEA5EB5p/5Hp3hGW1oHok+PIOH9Pbn7cnUiGmUEBrCVjnAw+HrKyN8bYVV0dIGllswYXwkG/+bgiBlE6IVIBAq+JwVWu1Sss3KarHY3OvFJUXZoZyRRg/Gc/+LRCE7lyKpwWQ70dbelGRyyJFH36eNv6ySXoUYtGkwlU5IVaHPApOxe4LHPZa/qhSRbPo2hwoh0orCtgejRebNtW5nlx00DNFgsvn8Svz2cIYLxsPVzKgUxs8Zxsxgn+Q/UvR7uq4AbAhyBMLxv7DjJ1pc7PJocuTno2Rw9uMZi1gkjbnmiOh6TTXIEWbnroyIhwc8555uto9melEUmWNQ+C+PwAK+MPw==")
        (libS.mkPubKey "*.your-storagebox.de" "ssh-ed25519" "AAAAC3NzaC1lZDI1NTE5AAAAIICf9svRenC/PLKIL9nk6K/pxQgoiFC41wTNvoIncOxs")
      ]);
      package = lib.mkIf cfgP.addHelpOnHostkeyMismatch (pkgs.openssh.overrideAttrs ({ patches, ... }: {
        patches = patches ++ [
          (pkgs.fetchpatch {
            urls =
              let
                version = "1%259.9p1-1";
              in
              [
                "https://salsa.debian.org/ssh-team/openssh/-/raw/debian/${version}/debian/patches/mention-ssh-keygen-on-keychange.patch"
              ];
            hash = "sha256-OZPOHwQkclUAjG3ShfYX66sbW2ahXPgsV6XNfzl9SIg=";
          })
        ];

        # takes to long and unstable requires openssh to work to advance
        doCheck = false;
      }));
    };

    services.openssh = lib.mkIf cfgS.recommendedDefaults {
      settings = {
        # following ssh-audit: nixos default minus 2048 bit modules (diffie-hellman-group-exchange-sha256)
        KexAlgorithms = [
          "mlkem768x25519-sha256"
          "sntrup761x25519-sha512"
          "sntrup761x25519-sha512@openssh.com"
          "curve25519-sha256"
          "curve25519-sha256@libssh.org"
        ];
        # following ssh-audit: nixos defaults minus encrypt-and-MAC
        Macs = [
          "hmac-sha2-512-etm@openssh.com"
          "hmac-sha2-256-etm@openssh.com"
          "umac-128-etm@openssh.com"
        ];
        RequiredRSASize = 4095;
      };
    };

    system.activationScripts.regenerateWeakRSAHostKey = lib.mkIf cfgS.regenerateWeakRSAHostKey /* bash */ ''
      if [[ -e /etc/ssh/ssh_host_rsa_key && $(${sshKeygen} -l -f /etc/ssh/ssh_host_rsa_key | ${lib.getExe pkgs.gawk} '{print $1}') != 4096 ]]; then
        echo "Regenerating OpenSSH RSA hostkey that had less than 4096 bits..."
        rm -f /etc/ssh/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key.pub
        ${sshKeygen} -t rsa -b 4096 -N "" -f /etc/ssh/ssh_host_rsa_key
      fi
    '';

    systemd.tmpfiles.rules = lib.mkIf (cfgS.enable && cfgS.fixPermissions) [
      "d /etc 0755 root root -"
      "d /etc/ssh 0755 root root -"
      "f /etc/ssh/ssh_host_ed25519_key 0700 root root -"
      "f /etc/ssh/ssh_host_ed25519_key.pub 0744 root root -"
      "f /etc/ssh/ssh_host_rsa_key 0700 root root -"
      "f /etc/ssh/ssh_host_rsa_key.pub 0744 root root -"
    ];
  };
}
