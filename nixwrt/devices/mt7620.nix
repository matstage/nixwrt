options: nixpkgs: self: super:
with nixpkgs.lib;
let
  kb = self.nixwrt.kernel;
  openwrt =  nixpkgs.fetchFromGitHub {
    owner = "openwrt";
    repo = "openwrt";
    name = "openwrt-src" ;
    rev = "252197f014932c03cea7c080d8ab90e0a963a281";
    sha256 = "1n30rhg7vwa4zq4sw1c27634wv6vdbssxa5wcplzzsbz10z8cwj9";
  };
  openwrtKernelFiles = "${openwrt}/target/linux";
  kernelVersion = [5 4 64];
  upstream = kb.fetchUpstreamKernel {
    version = kernelVersion;
    sha256 = "1vymhl6p7i06gfgpw9iv75bvga5sj5kgv46i1ykqiwv6hj9w5lxr";
  };
  listFiles = dir: builtins.attrNames (builtins.readDir dir);
  extraConfig = {
    "ASN1" = "y";
    "ASYMMETRIC_KEY_TYPE" = "y";
    "ASYMMETRIC_PUBLIC_KEY_SUBTYPE" = "y";
    "BLK_DEV_INITRD" = "n";
    "BLK_DEV_RAM" = "n";
    "CMDLINE_PARTITION" = "y";
    "CRC_CCITT" = "y";
    "CRYPTO" = "y";
    "CRYPTO_ARC4" = "y";
    "CRYPTO_CBC" = "y";
    "CRYPTO_CCM" = "y";
    "CRYPTO_CMAC" = "y";
    "CRYPTO_GCM" = "y";
    "CRYPTO_HASH_INFO" = "y";
    "CRYPTO_LIB_ARC4" = "y";
    "CRYPTO_RSA" = "y";
    "CRYPTO_SHA1" = "y";
    "DEVTMPFS" = "y";
    "ENCRYPTED_KEYS" = "y";
    "JFFS2_FS" = "n";
    "KEYS" = "y";
    "MODULES" = "y";
    "MODULE_SIG" = "y"; # enable "SYSTEM_DATA_VERIFICATION"
    "MODULE_SIG_ALL" = "y"; # enable "SYSTEM_DATA_VERIFICATION"
    "MODULE_SIG_FORMAT" = "y"; # enable "SYSTEM_DATA_VERIFICATION"
    "MODULE_SIG_SHA1" = "y"; # enable "SYSTEM_DATA_VERIFICATION"
    "PKCS7_MESSAGE_PARSER" = "y";
    "SYSTEM_DATA_VERIFICATION" = "y";
    "SYSTEM_TRUSTED_KEYRING" = "y";
    "WLAN" = "n";
    "X509_CERTIFICATE_PARSER" = "y";
  };
  checkConfig = { };
  tree = kb.patchSourceTree {
    inherit upstream openwrt;
    inherit (nixpkgs) buildPackages patchutils stdenv;
    version = kernelVersion;
    patches = lists.flatten
      [ "${openwrtKernelFiles}/ramips/patches-5.4/"
        "${openwrtKernelFiles}/generic/backport-5.4/"
        "${openwrtKernelFiles}/generic/pending-5.4/"
        (map (n: "${openwrtKernelFiles}/generic/hack-5.4/${n}")
          (builtins.filter
            (n: ! (strings.hasPrefix "230-" n))
            (listFiles "${openwrtKernelFiles}/generic/hack-5.4/")))
      ];
    files = [ "${openwrtKernelFiles}/generic/files/"
              "${openwrtKernelFiles}/ramips/files/"
              "${openwrtKernelFiles}/ramips/files-5.4/"
            ];
  };
  vmlinux = kb.makeVmlinux {
    inherit tree ;
    inherit (self.kernel) config;
    checkedConfig = checkConfig // extraConfig;
    inherit (nixpkgs) stdenv buildPackages writeText runCommand;
  };
  modules = (import ../kernel/make-backport-modules.nix) {
    inherit (nixpkgs) stdenv buildPackages runCommand writeText;
    openwrtSrc = openwrt;
    backportedSrc =
      builtins.fetchTarball {
        url = "https://cdn.kernel.org/pub/linux/kernel/projects/backports/stable/v5.8/backports-5.8-1.tar.xz";
        name = "backports-5.8.1";
        sha256 = "1r0q5a7mjkg069rdsmwvnlvxcvc51vchafbs06nc4vzrpnn148pq";
      # nixpkgs.buildPackages.callPackage ../kernel/backport.nix {
      #   donorTree = nixpkgs.fetchgit {
      #     url =
      #       "https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git";
      #     rev = "bcf876870b95592b52519ed4aafcf9d95999bc9c";
      #     sha256 = "1jffq83jzcvkvpf6afhwkaj0zlb293vlndp1r66xzx41mbnnra0x";
      #   };
      };
    klibBuild = vmlinux.modulesupport;
  };
in nixpkgs.lib.attrsets.recursiveUpdate super {
  packages = ( if super ? packages then super.packages else [] ) ++ [modules];
  busybox.applets = super.busybox.applets ++ [ "insmod" "modinfo" ];
  kernel = rec {
    inherit vmlinux tree;
    config =
      (kb.readDefconfig "${openwrtKernelFiles}/generic/config-5.4") //
      (kb.readDefconfig "${openwrtKernelFiles}/ramips/mt7620/config-5.4") //
      extraConfig;
    package =
      let fdt = kb.makeFdt {
            dts = options.dts {inherit openwrt;};
            inherit (nixpkgs) stdenv;
            inherit (nixpkgs.buildPackages) dtc;
            inherit (self.boot) commandLine;
            includes = [
              "${openwrtKernelFiles}/ramips/dts"
              "${tree}/arch/mips/boot/dts"
              "${tree}/arch/mips/boot/dts/include"
              "${tree}/include/"];
          };
      in kb.makeUimage {
        inherit vmlinux fdt;
        inherit (self.boot) entryPoint loadAddress commandLine;
        extraName = "mt7620";
        inherit (nixpkgs) patchImage stdenv;
        inherit (nixpkgs.buildPackages) lzma ubootTools;
      };
  };
  boot = {
    loadAddress = "0x80000000";
    entryPoint = "0x80000000";
    commandLine = "earlyprintk=serial,ttyS0 console=ttyS0,115200 panic=10 oops=panic init=/bin/init loglevel=8 rootfstype=squashfs";
  };
}
