#! @perl@

use strict;
use warnings;
use File::Basename;
use File::Slurp;
use Cwd 'abs_path';

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

die "This is not a NixOS installation (/etc/NIXOS is missing)!\n" unless -f "/etc/NIXOS";

# Install or update the bootloader.
if ($action eq "switch" || $action eq "boot") {
    system("@installBootLoader@ @out@") == 0 or exit 1;
    exit 0 if $action eq "boot";
}

# Check if we can activate the new configuration.
my $oldVersion = read_file("/run/current-system/init-interface-version", err_mode => 'quiet') // "";
my $newVersion = read_file("@out@/init-interface-version");

if ($newVersion ne $oldVersion) {
    print STDERR <<EOF;
Warning: the new NixOS configuration has an ‘init’ that is
incompatible with the current configuration.  The new configuration
won\'t take effect until you reboot the system.
EOF
    exit 100;
}

# Ignore SIGHUP so that we're not killed if we're running on (say)
# virtual console 1 and we restart the "tty1" unit.
$SIG{PIPE} = "IGNORE";

sub getActiveUnits {
    # FIXME: use D-Bus or whatever to query this, since parsing the
    # output of list-units is likely to break.
    my $lines = `@systemd@/bin/systemctl list-units --full`;
    my $res = {};
    foreach my $line (split '\n', $lines) {
        chomp $line;
        last if $line eq "";
        $line =~ /^(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s/ or next;
        next if $1 eq "UNIT";
        $res->{$1} = { load => $2, state => $3, substate => $4 };
    }
    return $res;
}

sub parseFstab {
    my ($filename) = @_;
    my %res;
    foreach my $line (read_file($filename, err_mode => 'quiet')) {
        chomp $line;
        $line =~ s/#.*//;
        next if $line =~ /^\s*$/;
        my @xs = split / /, $line;
        $res{$xs[1]} = { device => $xs[0], fsType => $xs[2], options => $xs[3] // "" };
    }
    return %res;
}

sub parseUnit {
    my ($filename) = @_;
    my $info = {};
    foreach my $line (read_file($filename)) {
        # FIXME: not quite correct.
        $line =~ /^([^=]+)=(.*)$/ or next;
        $info->{$1} = $2;
    }
    return $info;
}

sub boolIsTrue {
    my ($s) = @_;
    return $s eq "yes" || $s eq "true";
}

# Forget about previously failed services.
system("@systemd@/bin/systemctl", "reset-failed");

# Stop all services that no longer exist or have changed in the new
# configuration.
my (@unitsToStop, @unitsToSkip);
my $activePrev = getActiveUnits;
while (my ($unit, $state) = each %{$activePrev}) {
    my $baseUnit = $unit;
    # Recognise template instances.
    $baseUnit = "$1\@.$2" if $unit =~ /^(.*)@[^\.]*\.(.*)$/;
    my $prevUnitFile = "/etc/systemd/system/$baseUnit";
    my $newUnitFile = "@out@/etc/systemd/system/$baseUnit";
    if (-e $prevUnitFile && ($state->{state} eq "active" || $state->{state} eq "activating")) {
        if (! -e $newUnitFile) {
            push @unitsToStop, $unit;
        } elsif ($unit =~ /\.target$/) {
            # Cause all active target units to be restarted below.
            # This should start most changed units we stop here as
            # well as any new dependencies (including new mounts and
            # swap devices).
            my $unitInfo = parseUnit($newUnitFile);
            unless (boolIsTrue($unitInfo->{'RefuseManualStart'} // "false")) {
                write_file($restartListFile, { append => 1 }, "$unit\n");
            }
        } elsif (abs_path($prevUnitFile) ne abs_path($newUnitFile)) {
            if ($unit eq "sysinit.target" || $unit eq "basic.target" || $unit eq "multi-user.target" || $unit eq "graphical.target") {
                # Do nothing.  These cannot be restarted directly.
            } elsif ($unit =~ /\.mount$/) {
                # Reload the changed mount unit to force a remount.
                write_file($reloadListFile, { append => 1 }, "$unit\n");
            } elsif ($unit =~ /\.socket$/ || $unit =~ /\.path$/) {
                # FIXME: do something?
            } else {
                my $unitInfo = parseUnit($newUnitFile);
                if (!boolIsTrue($unitInfo->{'X-RestartIfChanged'} // "true")) {
                    push @unitsToSkip, $unit;
                } else {
                    # Record that this unit needs to be started below.  We
                    # write this to a file to ensure that the service gets
                    # restarted if we're interrupted.
                    write_file($restartListFile, { append => 1 }, "$unit\n");
                    push @unitsToStop, $unit;
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

# Compare the previous and new fstab to figure out which filesystems
# need a remount or need to be unmounted.  New filesystems are mounted
# automatically by starting local-fs.target.  Also handles swap
# devices.  FIXME: might be nicer if we generated units for all
# mounts; then we could unify this with the unit checking code above.
my %prevFstab = parseFstab "/etc/fstab";
my %newFstab = parseFstab "@out@/etc/fstab";
foreach my $mountPoint (keys %prevFstab) {
    my $prev = $prevFstab{$mountPoint};
    my $new = $newFstab{$mountPoint};
    my $unit = pathToUnitName($mountPoint). ".mount" if $prev->{fsType} ne "swap";
    if (!defined $new) {
        if ($prev->{fsType} eq "swap") {
            # Swap entry disappeared, so turn it off.  Can't use
            # "systemctl stop" here because systemd has lots of alias
            # units that prevent a stop from actually calling
            # "swapoff".
            system("@utillinux@/sbin/swapoff", $prev->{device});
        } else {
            # Filesystem entry disappeared, so unmount it.
            push @unitsToStop, $unit;
        }
    } elsif ($prev->{fsType} ne $new->{fsType} || $prev->{device} ne $new->{device}) {
        # Filesystem type or device changed, so unmount and mount it.
        write_file($restartListFile, { append => 1 }, "$unit\n");
        push @unitsToStop, $unit;
    } elsif ($prev->{options} ne $new->{options}) {
        # Mount options changes, so remount it.
        write_file($reloadListFile, { append => 1 }, "$unit\n");
    }
}

if (scalar @unitsToStop > 0) {
    print STDERR "stopping the following units: ", join(", ", sort(@unitsToStop)), "\n";
    system("@systemd@/bin/systemctl", "stop", "--", @unitsToStop); # FIXME: ignore errors?
}

print STDERR "NOT restarting the following units: ", join(", ", sort(@unitsToSkip)), "\n"
    if scalar @unitsToSkip > 0;

# Activate the new configuration (i.e., update /etc, make accounts,
# and so on).
my $res = 0;
print STDERR "activating the configuration...\n";
system("@out@/activate", "@out@") == 0 or $res = 2;

# FIXME: Re-exec systemd if necessary.

# Make systemd reload its units.
system("@systemd@/bin/systemctl", "daemon-reload") == 0 or $res = 3;

sub unique {
    my %unique = map { $_, 1 } @_;
    return sort(keys(%unique));
}

# Start all active targets, as well as changed units we stopped above.
# The latter is necessary because some may not be dependencies of the
# targets (i.e., they were manually started).  FIXME: detect units
# that are symlinks to other units.  We shouldn't start both at the
# same time because we'll get a "Failed to add path to set" error from
# systemd.
my @start = unique("default.target", split('\n', read_file($restartListFile, err_mode => 'quiet') // ""));
print STDERR "starting the following units: ", join(", ", @start), "\n";
system("@systemd@/bin/systemctl", "start", "--", @start) == 0 or $res = 4;
unlink($restartListFile);

# Reload units that need it.  This includes remounting changed mount
# units.
my @reload = unique(split '\n', read_file($reloadListFile, err_mode => 'quiet') // "");
if (scalar @reload > 0) {
    print STDERR "reloading the following units: ", join(", ", @reload), "\n";
    system("@systemd@/bin/systemctl", "reload", "--", @reload) == 0 or $res = 4;
    unlink($reloadListFile);
}

# Signal dbus to reload its configuration.
system("@systemd@/bin/systemctl", "reload", "dbus.service");

# Print failed and new units.
my (@failed, @new, @restarting);
my $activeNew = getActiveUnits;
while (my ($unit, $state) = each %{$activeNew}) {
    push @failed, $unit if $state->{state} eq "failed" || $state->{substate} eq "auto-restart";
    push @new, $unit if $state->{state} ne "failed" && !defined $activePrev->{$unit};
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

exit $res;
