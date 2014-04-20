#! @perl@

use strict;
use warnings;
use File::Basename;
use File::Slurp;
use Net::DBus;
use Sys::Syslog qw(:standard :macros);
use Cwd 'abs_path';

my $out = "@out@";

my $startListFile = "/run/systemd/start-list";
my $restartListFile = "/run/systemd/restart-list";
my $reloadListFile = "/run/systemd/reload-list";

my $action = shift @ARGV;

if (!defined $action || ($action ne "switch" && $action ne "boot" && $action ne "test")) {
    print STDERR <<EOF;
Usage: $0 [switch|boot|test]

switch: make the configuration the boot default and activate now
boot:   make the configuration the boot default
test:   activate the configuration, but don\'t make it the boot default
EOF
    exit 1;
}

# This is a NixOS installation if it has /etc/NIXOS or a proper
# /etc/os-release.
die "This is not a NixOS installation!\n" unless
    -f "/etc/NIXOS" || (read_file("/etc/os-release", err_mode => 'quiet') // "") =~ /ID=nixos/s;

openlog("nixos", "", LOG_USER);

# Install or update the bootloader.
if ($action eq "switch" || $action eq "boot") {
    system("@installBootLoader@ $out") == 0 or exit 1;
}

# Just in case the new configuration hangs the system, do a sync now.
system("@coreutils@/bin/sync") unless ($ENV{"NIXOS_NO_SYNC"} // "") eq "1";

exit 0 if $action eq "boot";

# Check if we can activate the new configuration.
my $oldVersion = read_file("/run/current-system/init-interface-version", err_mode => 'quiet') // "";
my $newVersion = read_file("$out/init-interface-version");

if ($newVersion ne $oldVersion) {
    print STDERR <<EOF;
Warning: the new NixOS configuration has an ‘init’ that is
incompatible with the current configuration.  The new configuration
won\'t take effect until you reboot the system.
EOF
    exit 100;
}

syslog(LOG_NOTICE, "switching to system configuration $out");

# Ignore SIGHUP so that we're not killed if we're running on (say)
# virtual console 1 and we restart the "tty1" unit.
$SIG{PIPE} = "IGNORE";

my $dbus = Net::DBus->find;
my $systemdService = $dbus->get_service('org.freedesktop.systemd1');
my $systemdManager = $systemdService->get_object('/org/freedesktop/systemd1');

sub getActiveUnits {
    my $res = {};
    foreach my $unit (@{ $systemdManager->ListUnits() }) {
        $res->{$unit->[0]} = {
            load => $unit->[2],
            state => $unit->[3],
            substate => $unit->[4]
        };
    }
    return $res;
}

sub parseFstab {
    my ($filename) = @_;
    my ($fss, $swaps);
    foreach my $line (read_file($filename, err_mode => 'quiet')) {
        chomp $line;
        $line =~ s/^\s*#.*//;
        next if $line =~ /^\s*$/;
        my @xs = split / /, $line;
        if ($xs[2] eq "swap") {
            $swaps->{$xs[0]} = { options => $xs[3] // "" };
        } else {
            $fss->{$xs[1]} = { device => $xs[0], fsType => $xs[2], options => $xs[3] // "" };
        }
    }
    return ($fss, $swaps);
}

sub parseUnit {
    my ($filename) = @_;
    my $info = {};
    parseKeyValues($info, read_file($filename));
    parseKeyValues($info, read_file("${filename}.d/overrides.conf")) if -f "${filename}.d/overrides.conf";
    return $info;
}

sub parseKeyValues {
    my $info = shift;
    foreach my $line (@_) {
        # FIXME: not quite correct.
        $line =~ /^([^=]+)=(.*)$/ or next;
        $info->{$1} = $2;
    }
}

sub boolIsTrue {
    my ($s) = @_;
    return $s eq "yes" || $s eq "true";
}

# As a fingerprint for determining whether a unit has changed, we use
# its absolute path. If it has an override file, we append *its*
# absolute path as well.
sub fingerprintUnit {
    my ($s) = @_;
    return abs_path($s) . (-f "${s}.d/overrides.conf" ? " " . abs_path "${s}.d/overrides.conf" : "");
}

# Stop all services that no longer exist or have changed in the new
# configuration.
my (@unitsToStop, @unitsToSkip);
my $activePrev = getActiveUnits;
while (my ($unit, $state) = each %{$activePrev}) {
    my $baseUnit = $unit;

    # Recognise template instances.
    $baseUnit = "$1\@.$2" if $unit =~ /^(.*)@[^\.]*\.(.*)$/;
    my $prevUnitFile = "/etc/systemd/system/$baseUnit";
    my $newUnitFile = "$out/etc/systemd/system/$baseUnit";

    my $baseName = $baseUnit;
    $baseName =~ s/\.[a-z]*$//;

    if (-e $prevUnitFile && ($state->{state} eq "active" || $state->{state} eq "activating")) {
        if (! -e $newUnitFile || abs_path($newUnitFile) eq "/dev/null") {
            push @unitsToStop, $unit;
        }

        elsif ($unit =~ /\.target$/) {
            my $unitInfo = parseUnit($newUnitFile);

            # Cause all active target units to be restarted below.
            # This should start most changed units we stop here as
            # well as any new dependencies (including new mounts and
            # swap devices).  FIXME: the suspend target is sometimes
            # active after the system has resumed, which probably
            # should not be the case.  Just ignore it.
            if ($unit ne "suspend.target" && $unit ne "hibernate.target" && $unit ne "hybrid-sleep.target") {
                unless (boolIsTrue($unitInfo->{'RefuseManualStart'} // "no")) {
                    write_file($startListFile, { append => 1 }, "$unit\n");
                }
            }

            # Stop targets that have X-StopOnReconfiguration set.
            # This is necessary to respect dependency orderings
            # involving targets: if unit X starts after target Y and
            # target Y starts after unit Z, then if X and Z have both
            # changed, then X should be restarted after Z.  However,
            # if target Y is in the "active" state, X and Z will be
            # restarted at the same time because X's dependency on Y
            # is already satisfied.  Thus, we need to stop Y first.
            # Stopping a target generally has no effect on other units
            # (unless there is a PartOf dependency), so this is just a
            # bookkeeping thing to get systemd to do the right thing.
            if (boolIsTrue($unitInfo->{'X-StopOnReconfiguration'} // "no")) {
                push @unitsToStop, $unit;
            }
        }

        elsif (fingerprintUnit($prevUnitFile) ne fingerprintUnit($newUnitFile)) {
            if ($unit eq "sysinit.target" || $unit eq "basic.target" || $unit eq "multi-user.target" || $unit eq "graphical.target") {
                # Do nothing.  These cannot be restarted directly.
            } elsif ($unit =~ /\.mount$/) {
                # Reload the changed mount unit to force a remount.
                write_file($reloadListFile, { append => 1 }, "$unit\n");
            } elsif ($unit =~ /\.socket$/ || $unit =~ /\.path$/) {
                # FIXME: do something?
            } else {
                my $unitInfo = parseUnit($newUnitFile);
                if (boolIsTrue($unitInfo->{'X-ReloadIfChanged'} // "no")) {
                    write_file($reloadListFile, { append => 1 }, "$unit\n");
                }
                elsif (!boolIsTrue($unitInfo->{'X-RestartIfChanged'} // "yes")) {
                    push @unitsToSkip, $unit;
                } else {
                    # If this unit is socket-activated, then stop the
                    # socket unit(s) as well, and restart the
                    # socket(s) instead of the service.
                    my $socketActivated = 0;
                    if ($unit =~ /\.service$/) {
                        my @sockets = split / /, ($unitInfo->{Sockets} // "");
                        if (scalar @sockets == 0) {
                            @sockets = ("$baseName.socket");
                        }
                        foreach my $socket (@sockets) {
                            if (defined $activePrev->{$socket}) {
                                push @unitsToStop, $socket;
                                write_file($startListFile, { append => 1 }, "$socket\n");
                                $socketActivated = 1;
                            }
                        }
                    }

                    if (!boolIsTrue($unitInfo->{'X-StopIfChanged'} // "yes")) {

                        # This unit should be restarted instead of
                        # stopped and started.
                        write_file($restartListFile, { append => 1 }, "$unit\n");

                    } else {

                        # If the unit is not socket-activated, record
                        # that this unit needs to be started below.
                        # We write this to a file to ensure that the
                        # service gets restarted if we're interrupted.
                        if (!$socketActivated) {
                            write_file($startListFile, { append => 1 }, "$unit\n");
                        }

                        push @unitsToStop, $unit;

                    }
                }
            }
        }
    }
}

sub pathToUnitName {
    my ($path) = @_;
    die unless substr($path, 0, 1) eq "/";
    return "-" if $path eq "/";
    $path = substr($path, 1);
    $path =~ s/\//-/g;
    # FIXME: handle - and unprintable characters.
    return $path;
}

sub unique {
    my %seen;
    my @res;
    foreach my $name (@_) {
        next if $seen{$name};
        $seen{$name} = 1;
        push @res, $name;
    }
    return @res;
}

# Compare the previous and new fstab to figure out which filesystems
# need a remount or need to be unmounted.  New filesystems are mounted
# automatically by starting local-fs.target.  FIXME: might be nicer if
# we generated units for all mounts; then we could unify this with the
# unit checking code above.
my ($prevFss, $prevSwaps) = parseFstab "/etc/fstab";
my ($newFss, $newSwaps) = parseFstab "$out/etc/fstab";
foreach my $mountPoint (keys %$prevFss) {
    my $prev = $prevFss->{$mountPoint};
    my $new = $newFss->{$mountPoint};
    my $unit = pathToUnitName($mountPoint) . ".mount";
    if (!defined $new) {
        # Filesystem entry disappeared, so unmount it.
        push @unitsToStop, $unit;
    } elsif ($prev->{fsType} ne $new->{fsType} || $prev->{device} ne $new->{device}) {
        # Filesystem type or device changed, so unmount and mount it.
        write_file($startListFile, { append => 1 }, "$unit\n");
        push @unitsToStop, $unit;
    } elsif ($prev->{options} ne $new->{options}) {
        # Mount options changes, so remount it.
        write_file($reloadListFile, { append => 1 }, "$unit\n");
    }
}

# Also handles swap devices.
foreach my $device (keys %$prevSwaps) {
    my $prev = $prevSwaps->{$device};
    my $new = $newSwaps->{$device};
    if (!defined $new) {
        # Swap entry disappeared, so turn it off.  Can't use
        # "systemctl stop" here because systemd has lots of alias
        # units that prevent a stop from actually calling
        # "swapoff".
        print STDERR "stopping swap device: $device\n";
        system("@utillinux@/sbin/swapoff", $device);
    }
    # FIXME: update swap options (i.e. its priority).
}

if (scalar @unitsToStop > 0) {
    @unitsToStop = unique(@unitsToStop);
    print STDERR "stopping the following units: ", join(", ", sort(@unitsToStop)), "\n";
    $systemdManager->StopUnit($_, "replace") for @unitsToStop;
}

print STDERR "NOT restarting the following units: ", join(", ", sort(@unitsToSkip)), "\n"
    if scalar @unitsToSkip > 0;

# Activate the new configuration (i.e., update /etc, make accounts,
# and so on).
my $res = 0;
print STDERR "activating the configuration...\n";
system("$out/activate", "$out") == 0 or $res = 2;

# Restart systemd if necessary.
if (abs_path("/proc/1/exe") ne abs_path("@systemd@/lib/systemd/systemd")) {
    print STDERR "restarting systemd...\n";

    $systemdManager->Reexecute();
}

# Forget about previously failed services.
$systemdManager->ResetFailed();

# Make systemd reload its units
$systemdManager->Reload();

# Restart changed services (those that have to be restarted rather
# than stopped and started).
my @restart = unique(split('\n', read_file($restartListFile, err_mode => 'quiet') // ""));
if (scalar @restart > 0) {
    print STDERR "restarting the following units: ", join(", ", sort(@restart)), "\n";
    $systemdManager->Restart($_, "replace") for @restart;
    unlink($restartListFile);
}

# Start all active targets, as well as changed units we stopped above.
# The latter is necessary because some may not be dependencies of the
# targets (i.e., they were manually started).  FIXME: detect units
# that are symlinks to other units.  We shouldn't start both at the
# same time because we'll get a "Failed to add path to set" error from
# systemd.
my @start = unique("default.target", "timers.target", "sockets.target", split('\n', read_file($startListFile, err_mode => 'quiet') // ""));
print STDERR "starting the following units: ", join(", ", sort(@start)), "\n";
$systemdManager->StartUnit($_, "replace") for @start;
unlink($startListFile);

# Reload units that need it.  This includes remounting changed mount
# units.
my @reload = unique(split '\n', read_file($reloadListFile, err_mode => 'quiet') // "");
if (scalar @reload > 0) {
    print STDERR "reloading the following units: ", join(", ", sort(@reload)), "\n";
    $systemdManager->ReloadUnit($_, "replace") for @reload;
    unlink($reloadListFile);
}

# Signal dbus to reload its configuration.
$systemdManager->ReloadUnit("dbus.service", "replace");

# Print failed and new units.
my (@failed, @new, @restarting);
my $activeNew = getActiveUnits;
while (my ($unit, $state) = each %{$activeNew}) {
    if ($state->{state} eq "failed") {
        push @failed, $unit;
    }
    elsif ($state->{state} eq "auto-restart") {
        # A unit in auto-restart state is a failure *if* it previously failed to start
        my $unit = $systemdManager->GetUnit($unit);

        if ($unit->ExecMainStatus ne '0') {
            push @failed, $unit;
        }
    }
    elsif ($state->{state} ne "failed" && !defined $activePrev->{$unit}) {
        push @new, $unit;
    }
}

print STDERR "the following new units were started: ", join(", ", sort(@new)), "\n"
    if scalar @new > 0;

if (scalar @failed > 0) {
    print STDERR "warning: the following units failed: ", join(", ", sort(@failed)), "\n";
    foreach my $unit (@failed) {
        print STDERR "\n";
        system("COLUMNS=1000 @systemd@/bin/systemctl status --no-pager '$unit' >&2");
    }
    $res = 4;
}

if ($res == 0) {
    syslog(LOG_NOTICE, "finished switching to system configuration $out");
} else {
    syslog(LOG_ERR, "switching to system configuration $out failed (status $res)");
}

exit $res;
