[
  ./config/debug-info.nix
  ./config/fonts/corefonts.nix
  ./config/fonts/fontconfig.nix
  ./config/fonts/fontdir.nix
  ./config/fonts/fonts.nix
  ./config/fonts/ghostscript.nix
  ./config/gtk-exe-env.nix
  ./config/i18n.nix
  ./config/krb5.nix
  ./config/ldap.nix
  ./config/networking.nix
  ./config/nsswitch.nix
  ./config/power-management.nix
  ./config/pulseaudio.nix
  ./config/qt-plugin-env.nix
  ./config/shells-environment.nix
  ./config/swap.nix
  ./config/sysctl.nix
  ./config/system-environment.nix
  ./config/system-path.nix
  ./config/timezone.nix
  ./config/unix-odbc-drivers.nix
  ./config/users-groups.nix
  ./config/zram.nix
  ./hardware/all-firmware.nix
  ./hardware/cpu/amd-microcode.nix
  ./hardware/cpu/intel-microcode.nix
  ./hardware/ksm.nix
  ./hardware/network/b43.nix
  ./hardware/network/intel-2100bg.nix
  ./hardware/network/intel-2200bg.nix
  ./hardware/network/intel-3945abg.nix
  ./hardware/network/mellanox.nix
  ./hardware/network/ralink.nix
  ./hardware/network/rtl8192c.nix
  ./hardware/opengl.nix
  ./hardware/pcmcia.nix
  ./hardware/video/webcam/facetimehd.nix
  ./installer/tools/auto-upgrade.nix
  ./installer/tools/tools.nix
  ./misc/assertions.nix
  ./misc/crashdump.nix
  ./misc/extra-arguments.nix
  ./misc/ids.nix
  ./misc/lib.nix
  ./misc/locate.nix
  ./misc/meta.nix
  ./misc/nixos.nix
  ./misc/nixpkgs.nix
  ./misc/passthru.nix
  ./misc/version.nix
  ./programs/bash/bash.nix
  ./programs/command-not-found/command-not-found.nix
  ./programs/dconf.nix
  ./programs/environment.nix
  ./programs/fish.nix
  ./programs/ibus.nix
  ./programs/light.nix
  ./programs/man.nix
  ./programs/shadow.nix
  ./programs/shell.nix
  ./programs/ssh.nix
  ./programs/ssmtp.nix
  ./programs/uim.nix
  ./programs/zsh/zsh.nix
  ./rename.nix
  ./security/acme.nix
  ./security/audit.nix
  ./security/ca.nix
  ./security/grsecurity.nix
  ./security/pam.nix
  ./security/pam_usb.nix
  ./security/pam_mount.nix
  ./security/polkit.nix
  ./security/rtkit.nix
  ./security/setuid-wrappers.nix
  ./security/sudo.nix
  ./services/backup/mysql-backup.nix
  ./services/backup/postgresql-backup.nix
  ./services/backup/tarsnap.nix
  ./services/continuous-integration/jenkins/default.nix
  ./services/continuous-integration/jenkins/slave.nix
  ./services/continuous-integration/jenkins/job-builder.nix
  ./services/databases/hbase.nix
  ./services/databases/influxdb.nix
  ./services/databases/memcached.nix
  ./services/databases/mongodb.nix
  ./services/databases/mysql.nix
  ./services/databases/openldap.nix
  ./services/databases/opentsdb.nix
  ./services/databases/postgresql.nix
  ./services/databases/redis.nix
  ./services/desktops/profile-sync-daemon.nix
  ./services/desktops/telepathy.nix
  ./services/hardware/acpid.nix
  ./services/hardware/actkbd.nix
  ./services/hardware/amd-hybrid-graphics.nix
  ./services/hardware/bluetooth.nix
  ./services/hardware/freefall.nix
  ./services/hardware/irqbalance.nix
  ./services/hardware/nvidia-optimus.nix
  ./services/hardware/pcscd.nix
  ./services/hardware/sane.nix
  ./services/hardware/tcsd.nix
  ./services/hardware/tlp.nix
  ./services/hardware/udev.nix
  ./services/hardware/upower.nix
  ./services/hardware/thermald.nix
  ./services/logging/klogd.nix
  ./services/logging/logcheck.nix
  ./services/logging/logrotate.nix
  ./services/logging/logstash.nix
  ./services/logging/rsyslogd.nix
  ./services/logging/syslogd.nix
  ./services/logging/syslog-ng.nix
  ./services/mail/dovecot.nix
  ./services/mail/mail.nix
  ./services/mail/opensmtpd.nix
  ./services/mail/postfix.nix
  ./services/mail/postsrsd.nix
  ./services/mail/spamassassin.nix
  ./services/misc/apache-kafka.nix
  ./services/misc/autofs.nix
  ./services/misc/confd.nix
  ./services/misc/etcd.nix
  ./services/misc/gpsd.nix
  ./services/misc/matrix-synapse.nix
  ./services/misc/mesos-master.nix
  ./services/misc/mesos-slave.nix
  ./services/misc/nix-daemon.nix
  ./services/misc/nix-gc.nix
  ./services/misc/nixos-manual.nix
  ./services/misc/nix-ssh-serve.nix
  ./services/misc/svnserve.nix
  ./services/misc/synergy.nix
  ./services/misc/uhub.nix
  ./services/misc/zookeeper.nix
  ./services/monitoring/apcupsd.nix
  ./services/monitoring/cadvisor.nix
  ./services/monitoring/collectd.nix
  ./services/monitoring/das_watchdog.nix
  ./services/monitoring/dd-agent.nix
  ./services/monitoring/grafana.nix
  ./services/monitoring/graphite.nix
  ./services/monitoring/ups.nix
  ./services/monitoring/uptime.nix
  ./services/network-filesystems/drbd.nix
  ./services/network-filesystems/nfsd.nix
  ./services/network-filesystems/rsyncd.nix
  ./services/network-filesystems/samba.nix
  ./services/networking/aiccu.nix
  ./services/networking/asterisk.nix
  ./services/networking/atftpd.nix
  ./services/networking/avahi-daemon.nix
  ./services/networking/bind.nix
  ./services/networking/autossh.nix
  ./services/networking/bird.nix
  ./services/networking/btsync.nix
  ./services/networking/charybdis.nix
  ./services/networking/chrony.nix
  ./services/networking/cjdns.nix
  ./services/networking/cntlm.nix
  ./services/networking/connman.nix
  ./services/networking/consul.nix
  ./services/networking/conntrackd.nix
  ./services/networking/ddclient.nix
  ./services/networking/dhcpcd.nix
  ./services/networking/dhcpd.nix
  ./services/networking/dnschain.nix
  ./services/networking/dnscrypt-proxy.nix
  ./services/networking/dnsmasq.nix
  ./services/networking/docker-registry-server.nix
  ./services/networking/ejabberd.nix
  ./services/networking/fan.nix
  ./services/networking/firefox/sync-server.nix
  ./services/networking/firewall.nix
  ./services/networking/git-daemon.nix
  ./services/networking/haproxy.nix
  ./services/networking/heyefi.nix
  ./services/networking/hostapd.nix
  ./services/networking/i2pd.nix
  ./services/networking/i2p.nix
  ./services/networking/iodined.nix
  ./services/networking/ipfs.nix
  ./services/networking/ipfs-cluster.nix
  ./services/networking/ircd-hybrid/default.nix
  ./services/networking/minidlna.nix
  ./services/networking/miniupnpd.nix
  ./services/networking/mstpd.nix
  ./services/networking/murmur.nix
  ./services/networking/namecoind.nix
  ./services/networking/nat.nix
  ./services/networking/networkmanager.nix
  ./services/networking/ngircd.nix
  ./services/networking/nix-serve.nix
  ./services/networking/nsd.nix
  ./services/networking/ntopng.nix
  ./services/networking/ntpd.nix
  ./services/networking/nylon.nix
  ./services/networking/oidentd.nix
  ./services/networking/openfire.nix
  ./services/networking/openntpd.nix
  ./services/networking/openvpn.nix
  ./services/networking/ostinato.nix
  ./services/networking/polipo.nix
  ./services/networking/privoxy.nix
  ./services/networking/quassel.nix
  ./services/networking/racoon.nix
  ./services/networking/radicale.nix
  ./services/networking/radvd.nix
  ./services/networking/rdnssd.nix
  ./services/networking/rpcbind.nix
  ./services/networking/skydns.nix
  ./services/networking/shout.nix
  ./services/networking/ssh/sshd.nix
  ./services/networking/strongswan.nix
  ./services/networking/supplicant.nix
  ./services/networking/syncthing.nix
  ./services/networking/teamspeak3.nix
  ./services/networking/tinc.nix
  ./services/networking/tftpd.nix
  ./services/networking/tlsdated.nix
  ./services/networking/unbound.nix
  ./services/networking/unifi.nix
  ./services/networking/vsftpd.nix
  ./services/networking/wakeonlan.nix
  ./services/networking/wicd.nix
  ./services/networking/wpa_supplicant.nix
  ./services/networking/xinetd.nix
  ./services/networking/znc.nix
  ./services/scheduling/atd.nix
  ./services/scheduling/chronos.nix
  ./services/scheduling/cron.nix
  ./services/scheduling/fcron.nix
  ./services/scheduling/marathon.nix
  ./services/search/elasticsearch.nix
  ./services/search/kibana.nix
  ./services/security/fail2ban.nix
  ./services/security/fprintd.nix
  ./services/security/frandom.nix
  ./services/security/hologram.nix
  ./services/security/physlock.nix
  ./services/system/kerberos.nix
  ./services/system/nscd.nix
  ./services/system/uptimed.nix
  ./services/ttys/agetty.nix
  ./services/ttys/gpm.nix
  ./services/ttys/kmscon.nix
  #./services/web-servers/apache-httpd/default.nix
  ./services/web-servers/fcgiwrap.nix
  ./services/web-servers/phpfpm.nix
  ./services/web-servers/tomcat.nix
  ./services/x11/desktop-managers/default.nix
  ./services/x11/display-managers/auto.nix
  ./services/x11/display-managers/default.nix
  ./services/x11/display-managers/gdm.nix
  ./services/x11/display-managers/lightdm.nix
  ./services/x11/display-managers/sddm.nix
  ./services/x11/hardware/multitouch.nix
  ./services/x11/hardware/synaptics.nix
  ./services/x11/hardware/wacom.nix
  ./services/x11/window-managers/default.nix
  ./services/x11/window-managers/metacity.nix
  ./services/x11/window-managers/none.nix
  ./services/x11/window-managers/xmonad.nix
  ./services/x11/xfs.nix
  ./services/x11/xserver.nix

  ../../pkgs/all-pkgs/a/accountsservice/system.nix
  ../../services/a/alsa
  ../../services/a/at-spi2-core
  ../../services/b/bumblebee
  ../../services/c/cups
  ../../services/d/dbus
  ../../services/d/dconf
  ../../services/d/deluge
  ../../services/e/evolution-data-server
  ../../services/f/fleet
  ../../services/g/geoclue
  ../../services/g/gnome-documents
  ../../services/g/gnome-keyring
  ../../services/g/gnome-online-accounts
  ../../services/g/gnome-online-miners
  ../../services/g/gnome-user-share
  ../../services/g/gvfs
  ../../services/k/kubernetes
  ../../services/m/mpd
  ../../services/n/nautilus
  ../../services/n/nginx
  ../../services/n/nvidia-drivers
  ../../services/p/plex-media-server
  ../../services/s/seahorse
  ../../services/s/sushi
  ../../services/t/tracker
  ../../services/u/udisks

  ./system/activation/activation-script.nix
  ./system/activation/top-level.nix
  ./system/boot/coredump.nix
  ./system/boot/emergency-mode.nix
  ./system/boot/initrd-network.nix
  ./system/boot/initrd-ssh.nix
  ./system/boot/kernel.nix
  ./system/boot/kexec.nix
  ./system/boot/loader/efi.nix
  ./system/boot/loader/generations-dir/generations-dir.nix
  ./system/boot/loader/generic-extlinux-compatible
  ./system/boot/loader/grub/grub.nix
  ./system/boot/loader/grub/ipxe.nix
  ./system/boot/loader/grub/memtest.nix
  ./system/boot/loader/gummiboot/gummiboot.nix
  ./system/boot/loader/init-script/init-script.nix
  ./system/boot/loader/loader.nix
  ./system/boot/loader/raspberrypi/raspberrypi.nix
  ./system/boot/luksroot.nix
  ./system/boot/modprobe.nix
  ./system/boot/networkd.nix
  ./system/boot/resolved.nix
  ./system/boot/shutdown.nix
  ./system/boot/stage-1.nix
  ./system/boot/stage-2.nix
  ./system/boot/systemd.nix
  ./system/boot/timesyncd.nix
  ./system/boot/tmp.nix
  ./system/etc/etc.nix
  ./tasks/cpu-freq.nix
  ./tasks/encrypted-devices.nix
  ./tasks/filesystems.nix
  ./tasks/filesystems/bcache.nix
  ./tasks/filesystems/btrfs.nix
  ./tasks/filesystems/cifs.nix
  ./tasks/filesystems/exfat.nix
  ./tasks/filesystems/ext.nix
  ./tasks/filesystems/f2fs.nix
  ./tasks/filesystems/jfs.nix
  ./tasks/filesystems/nfs.nix
  ./tasks/filesystems/ntfs.nix
  ./tasks/filesystems/vboxsf.nix
  ./tasks/filesystems/vfat.nix
  ./tasks/filesystems/xfs.nix
  ./tasks/filesystems/zfs.nix
  ./tasks/kbd.nix
  ./tasks/lvm.nix
  ./tasks/network-interfaces.nix
  ./tasks/network-interfaces-systemd.nix
  ./tasks/network-interfaces-scripted.nix
  ./tasks/scsi-link-power-management.nix
  ./tasks/swraid.nix
  ./tasks/trackpoint.nix
  ./testing/service-runner.nix
  ./virtualisation/container-config.nix
  ./virtualisation/containers.nix
  ./virtualisation/docker.nix
  ./virtualisation/libvirtd.nix
  ./virtualisation/lxc.nix
  ./virtualisation/lxd.nix
  ./virtualisation/openvswitch.nix
  ./virtualisation/parallels-guest.nix
  ./virtualisation/rkt.nix
  ./virtualisation/virtualbox-guest.nix
  ./virtualisation/virtualbox-host.nix
]
