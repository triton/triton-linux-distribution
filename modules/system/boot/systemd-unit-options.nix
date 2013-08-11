{ config, pkgs }:

with pkgs.lib;

rec {

  unitOptions = {

    enable = mkOption {
      default = true;
      types = types.bool;
      description = ''
        If set to false, this unit will be a symlink to
        /dev/null. This is primarily useful to prevent specific
        template instances (e.g. <literal>serial-getty@ttyS0</literal>)
        from being started.
      '';
    };

    description = mkOption {
      default = "";
      types = types.uniq types.string;
      description = "Description of this unit used in systemd messages and progress indicators.";
    };

    requires = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        Start the specified units when this unit is started, and stop
        this unit when the specified units are stopped or fail.
      '';
    };

    wants = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        Start the specified units when this unit is started.
      '';
    };

    after = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        If the specified units are started at the same time as
        this unit, delay this unit until they have started.
      '';
    };

    before = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        If the specified units are started at the same time as
        this unit, delay them until this unit has started.
      '';
    };

    bindsTo = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        Like ‘requires’, but in addition, if the specified units
        unexpectedly disappear, this unit will be stopped as well.
      '';
    };

    partOf = mkOption {
      default = [];
      types = types.listOf types.string;
      description = ''
        If the specified units are stopped or restarted, then this
        unit is stopped or restarted as well.
      '';
    };

    requiredBy = mkOption {
      default = [];
      types = types.listOf types.string;
      description = "Units that require (i.e. depend on and need to go down with) this unit.";
    };

    wantedBy = mkOption {
      default = [];
      types = types.listOf types.string;
      description = "Units that want (i.e. depend on) this unit.";
    };

    unitConfig = mkOption {
      default = {};
      example = { RequiresMountsFor = "/data"; };
      type = types.attrs;
      description = ''
        Each attribute in this set specifies an option in the
        <literal>[Unit]</literal> section of the unit.  See
        <citerefentry><refentrytitle>systemd.unit</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };

    restartTriggers = mkOption {
      default = [];
      description = ''
        An arbitrary list of items such as derivations.  If any item
        in the list changes between reconfigurations, the service will
        be restarted.
      '';
    };

  };


  serviceOptions = unitOptions // {

    environment = mkOption {
      default = {};
      type = types.attrs;
      example = { PATH = "/foo/bar/bin"; LANG = "nl_NL.UTF-8"; };
      description = "Environment variables passed to the service's processes.";
    };

    path = mkOption {
      default = [];
      apply = ps: "${makeSearchPath "bin" ps}:${makeSearchPath "sbin" ps}";
      description = ''
        Packages added to the service's <envar>PATH</envar>
        environment variable.  Both the <filename>bin</filename>
        and <filename>sbin</filename> subdirectories of each
        package are added.
      '';
    };

    serviceConfig = mkOption {
      default = {};
      example =
        { StartLimitInterval = 10;
          RestartSec = 5;
        };
      type = types.attrs;
      description = ''
        Each attribute in this set specifies an option in the
        <literal>[Service]</literal> section of the unit.  See
        <citerefentry><refentrytitle>systemd.service</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };

    script = mkOption {
      type = types.uniq types.string;
      default = "";
      description = "Shell commands executed as the service's main process.";
    };

    scriptArgs = mkOption {
      type = types.uniq types.string;
      default = "";
      description = "Arguments passed to the main process script.";
    };

    preStart = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed before the service's main process
        is started.
      '';
    };

    postStart = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed after the service's main process
        is started.
      '';
    };

    postStop = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed after the service's main process
        has exited.
      '';
    };

    restartIfChanged = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether the service should be restarted during a NixOS
        configuration switch if its definition has changed.
      '';
    };

    stopIfChanged = mkOption {
      type = types.bool;
      default = true;
      description = ''
        If set, a changed unit is restarted by calling
        <command>systemctl stop</command> in the old configuration,
        then <command>systemctl start</command> in the new one.
        Otherwise, it is restarted in a single step using
        <command>systemctl restart</command> in the new configuration.
        The latter is less correct because it runs the
        <literal>ExecStop</literal> commands from the new
        configuration.
      '';
    };

  };


  socketOptions = unitOptions // {

    listenStreams = mkOption {
      default = [];
      types = types.listOf types.string;
      example = [ "0.0.0.0:993" "/run/my-socket" ];
      description = ''
        For each item in this list, a <literal>ListenStream</literal>
        option in the <literal>[Socket]</literal> section will be created.
      '';
    };

    socketConfig = mkOption {
      default = {};
      example = { ListenStream = "/run/my-socket"; };
      type = types.attrs;
      description = ''
        Each attribute in this set specifies an option in the
        <literal>[Socket]</literal> section of the unit.  See
        <citerefentry><refentrytitle>systemd.socket</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };

  };


  timerOptions = unitOptions // {

    timerConfig = mkOption {
      default = {};
      example = { OnCalendar = "Sun 14:00:00"; Unit = "foo.service"; };
      type = types.attrs;
      description = ''
        Each attribute in this set specifies an option in the
        <literal>[Timer]</literal> section of the unit.  See
        <citerefentry><refentrytitle>systemd.timer</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> and
        <citerefentry><refentrytitle>systemd.time</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };

  };


  mountOptions = unitOptions // {

    what = mkOption {
      example = "/dev/sda1";
      type = types.uniq types.string;
      description = "Absolute path of device node, file or other resource. (Mandatory)";
    };

    where = mkOption {
      example = "/mnt";
      type = types.uniq types.string;
      description = ''
        Absolute path of a directory of the mount point.
        Will be created if it doesn't exist. (Mandatory)
      '';
    };

    type = mkOption {
      default = "";
      example = "ext4";
      type = types.uniq types.string;
      description = "File system type.";
    };

    options = mkOption {
      default = "";
      example = "noatime";
      type = types.string;
      merge = concatStringsSep ",";
      description = "Options used to mount the file system.";
    };

    mountConfig = mkOption {
      default = {};
      example = { DirectoryMode = "0775"; };
      type = types.attrs;
      description = ''
        Each attribute in this set specifies an option in the
        <literal>[Mount]</literal> section of the unit.  See
        <citerefentry><refentrytitle>systemd.mount</refentrytitle>
        <manvolnum>5</manvolnum></citerefentry> for details.
      '';
    };
  };

}
