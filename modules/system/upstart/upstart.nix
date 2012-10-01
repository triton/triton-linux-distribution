{ config, pkgs, ... }:

with pkgs.lib;
with import ../boot/systemd-unit-options.nix { inherit config pkgs; };

let

  userExists = u:
    (u == "") || any (uu: uu.name == u) (attrValues config.users.extraUsers);

  groupExists = g:
    (g == "") || any (gg: gg.name == g) (attrValues config.users.extraGroups);

  makeJobScript = name: content: "${pkgs.writeScriptBin name content}/bin/${name}";

  # From a job description, generate an systemd unit file.
  makeUnit = job:

    let
      hasMain = job.script != "" || job.exec != "";

      env = config.system.upstartEnvironment // job.environment;

      preStartScript = makeJobScript "${job.name}-pre-start.sh"
        ''
          #! ${pkgs.stdenv.shell} -e
          ${job.preStart}
        '';

      startScript = makeJobScript "${job.name}-start.sh"
        ''
          #! ${pkgs.stdenv.shell} -e
          ${if job.script != "" then job.script else ''
            exec ${job.exec}
          ''}
        '';

      postStartScript = makeJobScript "${job.name}-post-start.sh"
        ''
          #! ${pkgs.stdenv.shell} -e
          ${job.postStart}
        '';

      preStopScript = makeJobScript "${job.name}-pre-stop.sh"
        ''
          #! ${pkgs.stdenv.shell} -e
          ${job.preStop}
        '';

      postStopScript = makeJobScript "${job.name}-post-stop.sh"
        ''
          #! ${pkgs.stdenv.shell} -e
          ${job.postStop}
        '';
    in {

      inherit (job) description requires wants before partOf environment path restartIfChanged unitConfig;

      after =
        (if job.startOn == "stopped udevtrigger" then [ "systemd-udev-settle.service" ] else
         if job.startOn == "started udev" then [ "systemd-udev.service" ] else
         if job.startOn == "started network-interfaces" then [ "network-interfaces.service" ] else
         if job.startOn == "started networking" then [ "network.target" ] else
         if job.startOn == "ip-up" then [] else
         if job.startOn == "" || job.startOn == "startup" then [] else
         builtins.trace "Warning: job ‘${job.name}’ has unknown startOn value ‘${job.startOn}’." []
        ) ++ job.after;

      wantedBy =
        (if job.startOn == "" then [] else
         if job.startOn == "ip-up" then [ "ip-up.target" ] else
         [ "multi-user.target" ]) ++ job.wantedBy;

      serviceConfig =
        job.serviceConfig
        // optionalAttrs (job.preStart != "" && (job.script != "" || job.exec != ""))
          { ExecStartPre = preStartScript; }
        // optionalAttrs (job.script != "" || job.exec != "")
          { ExecStart = startScript; }
        // optionalAttrs (job.postStart != "")
          { ExecStartPost = postStartScript; }
        // optionalAttrs (job.preStop != "")
          { ExecStop = preStopScript; }
        // optionalAttrs (job.postStop != "")
          { ExecStopPost = postStopScript; }
        // (if job.script == "" && job.exec == "" then { Type = "oneshot"; RemainAfterExit = true; } else
            if job.daemonType == "fork" then { Type = "forking"; GuessMainPID = true; } else
            if job.daemonType == "none" then { } else
            throw "invalid daemon type `${job.daemonType}'")
        // optionalAttrs (!job.task && job.respawn)
          { Restart = "always"; };
    };


  jobOptions = serviceOptions // {

    name = mkOption {
      # !!! The type should ensure that this could be a filename.
      type = types.string;
      example = "sshd";
      description = ''
        Name of the Upstart job.
      '';
    };

    startOn = mkOption {
      # !!! Re-enable this once we're on Upstart >= 0.6.
      #type = types.string;
      default = "";
      description = ''
        The Upstart event that triggers this job to be started.
        If empty, the job will not start automatically.
      '';
    };

    stopOn = mkOption {
      type = types.string;
      default = "starting shutdown";
      description = ''
        The Upstart event that triggers this job to be stopped.
      '';
    };

    postStart = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed after the job is started (i.e. after
        the job's main process is started), but before the job is
        considered “running”.
      '';
    };

    preStop = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed before the job is stopped
        (i.e. before Upstart kills the job's main process).  This can
        be used to cleanly shut down a daemon.
      '';
    };

    postStop = mkOption {
      type = types.string;
      default = "";
      description = ''
        Shell commands executed after the job has stopped
        (i.e. after the job's main process has terminated).
      '';
    };

    exec = mkOption {
      type = types.string;
      default = "";
      description = ''
        Command to start the job's main process.  If empty, the
        job has no main process, but can still have pre/post-start
        and pre/post-stop scripts, and is considered “running”
        until it is stopped.
      '';
    };

    respawn = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Whether to restart the job automatically if its process
        ends unexpectedly.
      '';
    };

    task = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether this job is a task rather than a service.  Tasks
        are executed only once, while services are restarted when
        they exit.
      '';
    };

    daemonType = mkOption {
      type = types.string;
      default = "none";
      description = ''
        Determines how Upstart detects when a daemon should be
        considered “running”.  The value <literal>none</literal> means
        that the daemon is considered ready immediately.  The value
        <literal>fork</literal> means that the daemon will fork once.
        The value <literal>daemon</literal> means that the daemon will
        fork twice.  The value <literal>stop</literal> means that the
        daemon will raise the SIGSTOP signal to indicate readiness.
      '';
    };

    setuid = mkOption {
      type = types.string;
      check = userExists;
      default = "";
      description = ''
        Run the daemon as a different user.
      '';
    };

    setgid = mkOption {
      type = types.string;
      check = groupExists;
      default = "";
      description = ''
        Run the daemon as a different group.
      '';
    };

    path = mkOption {
      default = [];
      description = ''
        Packages added to the job's <envar>PATH</envar> environment variable.
        Both the <filename>bin</filename> and <filename>sbin</filename>
        subdirectories of each package are added.
      '';
    };

  };


  upstartJob = { name, config, ... }: {

    options = {

      unit = mkOption {
        default = makeUnit config;
        description = "Generated definition of the systemd unit corresponding to this job.";
      };

    };

    config = {

      # The default name is the name extracted from the attribute path.
      name = mkDefaultValue name;

    };

  };

in

{

  ###### interface

  options = {

    jobs = mkOption {
      default = {};
      description = ''
        This option defines the system jobs started and managed by the
        Upstart daemon.
      '';
      type = types.loaOf types.optionSet;
      options = [ jobOptions upstartJob ];
    };

    system.upstartEnvironment = mkOption {
      type = types.attrs;
      default = {};
      example = { TZ = "CET"; };
      description = ''
        Environment variables passed to <emphasis>all</emphasis> Upstart jobs.
      '';
    };

  };


  ###### implementation

  config = {

    boot.systemd.services =
      flip mapAttrs' config.jobs (name: job:
        nameValuePair job.name job.unit);

  };

}
