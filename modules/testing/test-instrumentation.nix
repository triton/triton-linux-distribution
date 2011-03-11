# This module allows the test driver to connect to the virtual machine
# via a root shell attached to port 514.

{ config, pkgs, ... }:

with pkgs.lib;

let

  # Urgh, `socat' sets the SIGCHLD to ignore.  This wreaks havoc with
  # some programs.
  rootShell = pkgs.writeScript "shell.pl"
    ''
      #! ${pkgs.perl}/bin/perl
      $SIG{CHLD} = 'DEFAULT';
      print "\n";
      exec "/bin/sh";
    '';

in
    
{

  config = {

    jobs.backdoor =
      { startOn = "ip-up";
        stopOn = "never";
        
        script =
          ''
            export USER=root
            export HOME=/root
            export DISPLAY=:0.0
            source /etc/profile
            cd /tmp
            echo "connecting to host..." > /dev/ttyS0
            ${pkgs.socat}/bin/socat tcp:10.0.2.6:23 exec:${rootShell} 2> /dev/ttyS0 # || poweroff -f
          '';

        respawn = false;
      };

    boot.initrd.postDeviceCommands =
      ''
        # Using acpi_pm as a clock source causes the guest clock to
        # slow down under high host load.  This is usually a bad
        # thing, but for VM tests it should provide a bit more
        # determinism (e.g. if the VM runs at lower speed, then
        # timeouts in the VM should also be delayed).
        echo acpi_pm > /sys/devices/system/clocksource/clocksource0/current_clocksource
      '';
    
    boot.postBootCommands =
      ''
        # Panic on out-of-memory conditions rather than letting the
        # OOM killer randomly get rid of processes, since this leads
        # to failures that are hard to diagnose.
        echo 2 > /proc/sys/vm/panic_on_oom

        # Coverage data is written into /tmp/coverage-data.  Symlink
        # it to the host filesystem so that we don't need to copy it
        # on shutdown.
        ( eval $(cat /proc/cmdline)
          mkdir -p /hostfs/$hostTmpDir/coverage-data
          ln -sfn /hostfs/$hostTmpDir/coverage-data /tmp/coverage-data
        )

        # Mount debugfs to gain access to the kernel coverage data (if
        # available).
        mount -t debugfs none /sys/kernel/debug || true
      '';

    # If the kernel has been built with coverage instrumentation, make
    # it available under /proc/gcov.
    boot.kernelModules = [ "gcov-proc" ];

    # Panic if an error occurs in stage 1 (rather than waiting for
    # user intervention). 
    boot.kernelParams =
      [ "console=tty1" "console=ttyS0" "panic=1" "stage1panic" ];

    # `xwininfo' is used by the test driver to query open windows.
    environment.systemPackages = [ pkgs.xorg.xwininfo ];

    # Send all of /var/log/messages to the serial port.
    services.syslogd.extraConfig = "*.* /dev/ttyS0";

    # Don't run klogd.  Kernel messages appear on the serial console anyway.
    jobs.klogd.startOn = mkOverride 50 "";

    # Prevent tests from accessing the Internet.
    networking.defaultGateway = mkOverride 150 "";
    networking.nameservers = mkOverride 150 [ ];

    # Require a patch to the kernel to increase the 15s CIFS timeout.
    assertions =
      [ { assertion = config.boot.kernelPackages.kernel.features ? cifsTimeout;
          message = "VM tests require that the kernel has the CIFS timeout patch.";
        }
      ];

    system.upstartEnvironment.GCOV_PREFIX = "/tmp/coverage-data";
      
  };

}
