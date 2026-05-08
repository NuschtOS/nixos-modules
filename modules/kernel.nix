{ config, lib, ... }:

{
  options = {
    boot.recommendedKernelBlacklist = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to blacklist rarely used and insufficiently audited kernel modules to improve baseline security.";
    };
  };

  config = lib.mkIf config.boot.recommendedKernelBlacklist {
    boot.blacklistedKernelModules = [
      # Obscure network protocols
      # https://theprivacyguide1.github.io/linux_hardening_guide.html#uncommon_protocols
      "appletalk"
      "dccp"
      "ipx"
      "llc"
      "n-hdlc"
      "p8022"
      "p8023"
      "psnap"
      "sctp"
      "tipc"

      # Old or rare or insufficiently audited filesystems
      "adfs"
      "affs"
      "bfs"
      "befs"
      "cramfs"
      "efs"
      "erofs"
      "exofs"
      "freevxfs"
      "f2fs"
      "hfs"
      "hfsplus"
      "hpfs"
      "jfs"
      "jffs2"
      "minix"
      "nilfs2"
      "ntfs"
      "omfs"
      "qnx4"
      "qnx6"
      "sysv"
      "udf"
      "ufs"

      # Those had some vulnerabilities already and using kernel crypto in user land is very rare
      # copy.fail
      "af_alg"
      "algif_aead"
      "algif_hash"
      "algif_rng"
      "algif_skcipher"
      # dirtyfrag
      "esp4"
      "esp6"
      "rxrpc"
    ];
  };
}
