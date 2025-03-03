# This module continues the upstream removed option environment.noXlibs

{ config, lib, options, pkgs, ... }:

let
  cfg = config.environment.noGraphicsPackages;
in
{
  meta.maintainers = [ lib.maintainers.SuperSandro2000 ];

  options = {
    environment.noGraphicsPackages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        This is an advanced option that switches off options in the default configuration that require GUI libraries
        and adds overlays to remove such dependencies in some packages.
        This includes client-side font configuration and SSH forwarding of X11 authentication.
        Thus, you do *not* want to enable this option on a graphical system or if you want to run X11 programs via SSH.

        ::: {.warning}
        The added overlays cause package rebuilds due to cache misses.
        Also some packages might fail to build due to the added overlays.
        When enabling this option you should be able to recognize such build failures and act on them accordingly.
        :::
      '';
    };
  };

  config = {
    assertions = lib.mkIf cfg [
      # copied from lib.mkRemovedOptionModule
      (let
        optionName = [ "environment" "noXlibs" ];
        replacementInstructions = "This option got renamed to environment.noGraphicsPackages. Please make sure to properly read the description of the option if you want to continue to use it.";
        opt = lib.getAttrFromPath optionName options;
      in {
        assertion = !opt.isDefined;
        message = ''
          The option definition `${lib.showOption optionName}' in ${lib.showFiles opt.files} no longer has any effect; please remove it.
          ${replacementInstructions}
        '';
      })

      {
        assertion = !config.services.graphical-desktop.enable && !config.services.xserver.enable;
        message = "environment.noGraphicsPackages requires that no graphical desktop is being used! Please unset this option.";
      }
    ];

    fonts.fontconfig.enable = lib.mkIf cfg false;

    nixpkgs.overlays = lib.singleton (lib.const (prev: (lib.mapAttrs (name: value: if cfg then value else prev.${name}) {
      beam = prev.beam_nox;
      cairo = prev.cairo.override { x11Support = false; };
      dbus = prev.dbus.override { x11Support = false; };
      fastfetch = prev.fastfetch.override { vulkanSupport = false; waylandSupport = false; x11Support = false; };
      ffmpeg = prev.ffmpeg.override { ffmpegVariant = "headless"; };
      ffmpeg_4 = prev.ffmpeg_4.override { ffmpegVariant = "headless"; };
      ffmpeg_6 = prev.ffmpeg_6.override { ffmpegVariant = "headless"; };
      ffmpeg_7 = prev.ffmpeg_7.override { ffmpegVariant = "headless"; };
      # dep of graphviz, libXpm is optional for Xpm support
      gd = prev.gd.override { withXorg = false; };
      ghostscript = prev.ghostscript.override { cupsSupport = false; x11Support = false; };
      gjs = (prev.gjs.override { installTests = false; }).overrideAttrs { doCheck = false; }; # avoid test dependency on gtk3
      gobject-introspection = prev.gobject-introspection.override { x11Support = false; };
      gpg-tui = prev.gpg-tui.override { x11Support = false; };
      gpsd = prev.gpsd.override { guiSupport = false; };
      graphviz = prev.graphviz-nox;
      gst_all_1 = prev.gst_all_1 // {
        gst-plugins-bad = prev.gst_all_1.gst-plugins-bad.override { guiSupport = false; };
        gst-plugins-base = prev.gst_all_1.gst-plugins-base.override { enableGl = false; enableWayland = false; enableX11 = false; };
        gst-plugins-good = prev.gst_all_1.gst-plugins-good.override { enableWayland = false; enableX11 = false; gtkSupport = false; qt5Support = false; qt6Support = false; };
        gst-plugins-rs = prev.gst_all_1.gst-plugins-rs.override { withGtkPlugins = false; };
      };
      imagemagick = prev.imagemagick.override { libX11Support = false; libXtSupport = false; };
      imagemagickBig = prev.imagemagickBig.override { libX11Support = false; libXtSupport = false; };
      intel-vaapi-driver = prev.intel-vaapi-driver.override { enableGui = false; };
      libdevil = prev.libdevil-nox;
      libextractor = prev.libextractor.override { gtkSupport = false; };
      libplacebo = prev.libplacebo.override { vulkanSupport = false; };
      libva = prev.libva-minimal;
      limesuite = prev.limesuite.override { withGui = false; };
      mc = prev.mc.override { x11Support = false; };
      # TODO: remove when https://github.com/NixOS/nixpkgs/pull/344318 is merged
      mesa = (prev.mesa.override { eglPlatforms = [ ]; }).overrideAttrs ({ mesonFlags, ... }:{
        mesonFlags = mesonFlags ++ [
          (lib.mesonEnable "gallium-vdpau" false)
          (lib.mesonEnable "glx" false)
          (lib.mesonEnable "xlib-lease" false)
        ];
      });
      mpv-unwrapped = prev.mpv-unwrapped.override ({
        drmSupport = false;
        sdl2Support = false;
        vulkanSupport = false;
        waylandSupport = false;
        x11Support = false;
      } // lib.optionalAttrs (prev.mpv-unwrapped.override.__functionArgs?screenSaverSupport) {
        screenSaverSupport = false;
      });
      msmtp = prev.msmtp.override { withKeyring = false; };
      mupdf = prev.mupdf.override { enableGL = false; enableX11 = false; };
      neofetch = prev.neofetch.override { x11Support = false; };
      networkmanager-fortisslvpn = prev.networkmanager-fortisslvpn.override { withGnome = false; };
      networkmanager-iodine = prev.networkmanager-iodine.override { withGnome = false; };
      networkmanager-l2tp = prev.networkmanager-l2tp.override { withGnome = false; };
      networkmanager-openconnect = prev.networkmanager-openconnect.override { withGnome = false; };
      networkmanager-openvpn = prev.networkmanager-openvpn.override { withGnome = false; };
      networkmanager-sstp = prev.networkmanager-vpnc.override { withGnome = false; };
      networkmanager-vpnc = prev.networkmanager-vpnc.override { withGnome = false; };
      pango = prev.pango.override { x11Support = false; };
      pinentry-curses = prev.pinentry-curses.override { withLibsecret = false; };
      pinentry-tty = prev.pinentry-tty.override { withLibsecret = false; };
      pipewire = prev.pipewire.override { vulkanSupport = false; x11Support = false; };
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (python-final: python-prev: {
          # tk feature requires wayland which fails to compile
          matplotlib = python-prev.matplotlib.override { enableTk = false; };
        })
      ];
      qemu = prev.qemu.override { gtkSupport = false; spiceSupport = false; sdlSupport = false; };
      qrencode = prev.qrencode.overrideAttrs (_: { doCheck = false; });
      qt5 = prev.qt5.overrideScope (lib.const (prev': {
        qtbase = prev'.qtbase.override { withGtk3 = false; withQttranslation = false; };
      }));
      stoken = prev.stoken.override { withGTK3 = false; };
      # avoid kernel rebuild through swtpm -> tpm2-tss -> systemd -> util-linux -> hexdump
      swtpm = let
        gobject-introspection = prev.gobject-introspection.override { inherit (prev) cairo; };
        glib = prev.glib.override { inherit gobject-introspection; };
      in prev.swtpm.override {
        inherit glib;
        json-glib = prev.json-glib.override {
          inherit glib gobject-introspection;
        };
      };
      # translateManpages -> perlPackages.po4a -> texlive-combined-basic -> texlive-core-big -> libX11
      util-linux = prev.util-linux.override { translateManpages = false; };
      vim-full = prev.vim-full.override { guiSupport = false; };
      vte = prev.vte.override { gtkVersion = null; };
      # TODO: upstream as toggle
      vulkan-loader = prev.vulkan-loader.override { wayland = null; };
      wayland = prev.wayland.override { withDocumentation = false; };
      zbar = prev.zbar.override { enableVideo = false; withXorg = false; };
    })));

    programs.ssh.setXAuthLocation = lib.mkIf cfg false;

    security.pam.services.su.forwardXAuth = lib.mkIf cfg (lib.mkForce false);
  };
}
