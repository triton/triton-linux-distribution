{config, pkgs, nix, modprobe, nssModulesPath}:

let 

  makeJob = import ../upstart-jobs/make-job.nix {
    inherit (pkgs) runCommand;
  };

  optional = cond: service: pkgs.lib.optional cond (makeJob service);

  requiredTTYs =
    (config.services.mingetty.ttys)
    ++ [10] /* !!! sync with syslog.conf */ ;

in

import ../upstart-jobs/gather.nix {
  inherit (pkgs) runCommand;

  jobs = map makeJob [
    # Syslogd.
    (import ../upstart-jobs/syslogd.nix {
      inherit (pkgs) sysklogd;
    })

    # The udev daemon creates devices nodes and runs programs when
    # hardware events occur.
    (import ../upstart-jobs/udev.nix {
      inherit (pkgs) stdenv writeText substituteAll udev procps;
      inherit (pkgs.lib) cleanSource;
      firmwareDirs =
        pkgs.lib.optional (config.networking.enableIntel2200BGFirmware) pkgs.ipw2200fw
	++
	(config.services.udev.addFirmware);
      extraUdevPkgs =
        pkgs.lib.optional (config.services.hal.enable) pkgs.hal;
    })
      
    # Makes LVM logical volumes available. 
    (import ../upstart-jobs/lvm.nix {
      inherit modprobe;
      inherit (pkgs) lvm2 devicemapper;
    })
      
    # Activate software RAID arrays.
    (import ../upstart-jobs/swraid.nix {
      inherit modprobe;
      inherit (pkgs) mdadm;
    })
      
    # Hardware scan; loads modules for PCI devices.
    (import ../upstart-jobs/hardware-scan.nix {
      inherit modprobe;
      doHardwareScan = config.boot.hardwareScan;
      kernelModules = config.boot.kernelModules;
    })
      
    # Mount file systems.
    (import ../upstart-jobs/filesystems.nix {
      inherit (pkgs) utillinux e2fsprogs;
      fileSystems = config.fileSystems;
    })

    # Swapping.
    (import ../upstart-jobs/swap.nix {
      inherit (pkgs) utillinux library;
      swapDevices = config.swapDevices;
    })

    # Network interfaces.
    (import ../upstart-jobs/network-interfaces.nix {
      inherit modprobe;
      inherit (pkgs) nettools wirelesstools bash writeText;
      nameservers = config.networking.nameservers;
      defaultGateway = config.networking.defaultGateway;
      interfaces = config.networking.interfaces;
      localCommands = config.networking.localCommands;
    })
      
    # Nix daemon - required for multi-user Nix.
    (import ../upstart-jobs/nix-daemon.nix {
      inherit nix;
      inherit (pkgs) openssl;
    })

    # Cron daemon.
    (import ../upstart-jobs/cron.nix {
      inherit (pkgs) cron;
    })

    # Name service cache daemon.
    (import ../upstart-jobs/nscd.nix {
      inherit (pkgs) glibc;
      inherit nssModulesPath;
    })

    # Console font and keyboard maps.
    (import ../upstart-jobs/kbd.nix {
      inherit (pkgs) glibc kbd gzip;
      ttyNumbers = requiredTTYs;
      defaultLocale = config.i18n.defaultLocale;
      consoleFont = config.i18n.consoleFont;
      consoleKeyMap = config.i18n.consoleKeyMap;
    })

    # Handles the maintenance/stalled event (single-user shell).
    (import ../upstart-jobs/maintenance-shell.nix {
      inherit (pkgs) bash;
    })

    # Ctrl-alt-delete action.
    (import ../upstart-jobs/ctrl-alt-delete.nix)

  ]

  # DHCP client.
  ++ optional config.networking.useDHCP
    (import ../upstart-jobs/dhclient.nix {
      inherit (pkgs) nettools dhcp lib;
      interfaces = config.networking.interfaces;
    })

  # ifplugd daemon for monitoring Ethernet cables.
  ++ optional config.networking.interfaceMonitor.enable
    (import ../upstart-jobs/ifplugd.nix {
      inherit (pkgs) ifplugd writeScript bash;
      inherit config;
    })

  # DHCP server.
  ++ optional config.services.dhcpd.enable
    (import ../upstart-jobs/dhcpd.nix {
      inherit (pkgs) dhcp;
      configFile = config.services.dhcpd.configFile;
      interfaces = config.services.dhcpd.interfaces;
    })

  # SSH daemon.
  ++ optional config.services.sshd.enable
    (import ../upstart-jobs/sshd.nix {
      inherit (pkgs) writeText openssh glibc;
      inherit (pkgs.xorg) xauth;
      inherit nssModulesPath;
      forwardX11 = config.services.sshd.forwardX11;
      allowSFTP = config.services.sshd.allowSFTP;
    })

  # NTP daemon.
  ++ optional config.services.ntp.enable
    (import ../upstart-jobs/ntpd.nix {
      inherit modprobe;
      inherit (pkgs) ntp glibc writeText;
      servers = config.services.ntp.servers;
    })

  # X server.
  ++ optional config.services.xserver.enable
    (import ../upstart-jobs/xserver.nix {
      inherit config;
      inherit (pkgs) writeText lib xterm slim xorg mesa
        gnome compiz feh kdebase kdelibs xkeyboard_config
        openssh x11_ssh_askpass nvidiaDrivers synaptics;
      stdenv = pkgs.stdenvNewSetupScript;
      libX11 = pkgs.xlibs.libX11;
      libXext = pkgs.xlibs.libXext;
      fontDirectories = import ../system/fonts.nix {inherit pkgs config;};
      isClone = config.services.xserver.isClone;
    })

  # Apache httpd.
  ++ optional config.services.httpd.enable
    (import ../upstart-jobs/httpd.nix {
      inherit config pkgs;
      inherit (pkgs) glibc;
    })

  # Samba service.
  ++ optional config.services.samba.enable
    (import ../upstart-jobs/samba.nix {
      inherit pkgs;
      inherit (pkgs) glibc samba;
    })

  # CUPS (printing) daemon.
  ++ optional config.services.printing.enable
    (import ../upstart-jobs/cupsd.nix {
      inherit (pkgs) writeText cups;
    })

  # Gateway6
  ++ optional config.services.gw6c.enable
    (import ../upstart-jobs/gw6c.nix {
      inherit config pkgs;
    })

  # X Font Server
  ++ optional config.services.xfs.enable
  (import ../upstart-jobs/xfs.nix {
  	inherit config pkgs;
  })

  ++ optional config.services.ircdHybrid.enable
    (import ../upstart-jobs/ircd-hybrid.nix {
      inherit config pkgs;
    })


  # ALSA sound support.
  ++ optional config.sound.enable
    (import ../upstart-jobs/alsa.nix {
      inherit modprobe;
      inherit (pkgs) alsaUtils;
    })

  # D-Bus system-wide daemon.
  ++ optional config.services.dbus.enable
    (import ../upstart-jobs/dbus.nix {
      inherit (pkgs) stdenv dbus;
      dbusServices =
        pkgs.lib.optional (config.services.hal.enable) pkgs.hal;
    })

  # HAL daemon.
  ++ optional config.services.hal.enable
    (import ../upstart-jobs/hal.nix {
      inherit (pkgs) stdenv hal;
    })

  # Nagios system/network monitoring daemon.
  ++ optional config.services.nagios.enable
    (import ../upstart-jobs/nagios {
      inherit config pkgs;
    })

  # Handles the reboot/halt events.
  ++ (map
    (event: makeJob (import ../upstart-jobs/halt.nix {
      inherit (pkgs) bash utillinux;
      inherit event;
    }))
    ["reboot" "halt" "system-halt" "power-off"]
  )
    
  # The terminals on ttyX.
  ++ (map 
    (ttyNumber: makeJob (import ../upstart-jobs/mingetty.nix {
        inherit (pkgs) mingetty;
        inherit ttyNumber;
        loginProgram = "${pkgs.pam_login}/bin/login";
    }))
    (config.services.mingetty.ttys)
  )

  # Transparent TTY backgrounds.
  ++ optional config.services.ttyBackgrounds.enable
    (import ../upstart-jobs/tty-backgrounds.nix {
      inherit (pkgs) stdenv splashutils;
      
      backgrounds =
      
        let
        
          specificThemes =
            config.services.ttyBackgrounds.defaultSpecificThemes
            ++ config.services.ttyBackgrounds.specificThemes;
            
          overridenTTYs = map (x: x.tty) specificThemes;

          # Use the default theme for all the mingetty ttys and for the
          # syslog tty, except those for which a specific theme is
          # specified.
          defaultTTYs =
            pkgs.library.filter (x: !(pkgs.library.elem x overridenTTYs)) requiredTTYs;

        in      
          (map (ttyNumber: {
            tty = ttyNumber;
            theme = config.services.ttyBackgrounds.defaultTheme;
          }) defaultTTYs)
          ++ specificThemes;
          
    })

  # User-defined events.
  ++ (map makeJob (config.services.extraJobs))

  # For the built-in logd job.
  ++ [(makeJob { jobDrv = pkgs.upstart; })];
  
}
