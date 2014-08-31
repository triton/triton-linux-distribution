use strict;
use warnings;
use Class::Struct;
use XML::LibXML;
use File::Basename;
use File::Path;
use File::stat;
use File::Copy;
use POSIX;
use Cwd;

my $defaultConfig = $ARGV[1] or die;

my $dom = XML::LibXML->load_xml(location => $ARGV[0]);

sub get { my ($name) = @_; return $dom->findvalue("/expr/attrs/attr[\@name = '$name']/*/\@value"); }

sub readFile {
    my ($fn) = @_; local $/ = undef;
    open FILE, "<$fn" or return undef; my $s = <FILE>; close FILE;
    local $/ = "\n"; chomp $s; return $s;
}

sub writeFile {
    my ($fn, $s) = @_;
    open FILE, ">$fn" or die "cannot create $fn: $!\n";
    print FILE $s or die;
    close FILE or die;
}

sub runCommand {
    my ($cmd) = @_;
    open FILE, "$cmd 2>/dev/null |" or die "Failed to execute: $cmd\n";
    my @ret = <FILE>;
    close FILE;
    return ($?, @ret);
}

my $grub = get("grub");
my $grubVersion = int(get("version"));
my $extraConfig = get("extraConfig");
my $extraPrepareConfig = get("extraPrepareConfig");
my $extraPerEntryConfig = get("extraPerEntryConfig");
my $extraEntries = get("extraEntries");
my $extraEntriesBeforeNixOS = get("extraEntriesBeforeNixOS") eq "true";
my $splashImage = get("splashImage");
my $configurationLimit = int(get("configurationLimit"));
my $copyKernels = get("copyKernels") eq "true";
my $timeout = int(get("timeout"));
my $defaultEntry = int(get("default"));
my $fsIdentifier = get("fsIdentifier");
$ENV{'PATH'} = get("path");

die "unsupported GRUB version\n" if $grubVersion != 1 && $grubVersion != 2;

print STDERR "updating GRUB $grubVersion menu...\n";

mkpath("/boot/grub", 0, 0700);

# Discover whether /boot is on the same filesystem as / and
# /nix/store.  If not, then all kernels and initrds must be copied to
# /boot.
if (stat("/boot")->dev != stat("/nix/store")->dev) {
    $copyKernels = 1;
}

# Discover information about the location of /boot
struct(Fs => {
    device => '$',
    type => '$',
    mount => '$',
});
sub GetFs {
    my ($dir) = @_;
    my ($status, @dfOut) = runCommand("df -T $dir");
    if ($status != 0 || $#dfOut != 1) {
        die "Failed to retrieve output about $dir from `df`";
    }
    my @boot = split(/[ \n\t]+/, $dfOut[1]);
    return Fs->new(device => $boot[0], type => $boot[1], mount => $boot[6]);
}
struct (Grub => {
    path => '$',
    search => '$',
});
my $driveid = 1;
sub GrubFs {
    my ($dir) = @_;
    my $fs = GetFs($dir);
    my $path = "/" . substr($dir, length($fs->mount));
    my $search = "";

    if ($grubVersion > 1) {
        # ZFS is completely separate logic as zpools are always identified by a label
        # or custom UUID
        if ($fs->type eq 'zfs') {
            my $sid = index($fs->device, '/');

            if ($sid < 0) {
                $search = '--label ' . $fs->device;
                $path = '/@' . $path;
            } else {
                $search = '--label ' . substr($fs->device, 0, $sid);
                $path = '/' . substr($fs->device, $sid) . '/@' . $path;
            }
        } else {
            my %types = ('uuid' => '--fs-uuid', 'label' => '--label');

            if ($fsIdentifier eq 'provided') {
                # If the provided dev is identifying the partition using a label or uuid,
                # we should get the label / uuid and do a proper search
                my @matches = $fs->device =~ m/\/dev\/disk\/by-(label|uuid)\/(.*)/;
                if ($#matches > 1) {
                    die "Too many matched devices"
                } elsif ($#matches == 1) {
                    $search = "$types{$matches[0]} $matches[1]"
                }
            } else {
                # Determine the identifying type
                $search = $types{$fsIdentifier} . ' ';

                # Based on the type pull in the identifier from the system
                my ($status, @devInfo) = runCommand("blkid -o export @{[$fs->device]}");
                if ($status != 0) {
                    die "Failed to get blkid info for @{[$fs->device]}";
                }
                my @matches = join("", @devInfo) =~ m/@{[uc $fsIdentifier]}=([^\n]*)/;
                if ($#matches != 0) {
                    die "Couldn't find a $types{$fsIdentifier} for @{[$fs->device]}\n"
                }
                $search .= $matches[0];
            }

            # BTRFS is a special case in that we need to fix the referrenced path based on subvolumes
            if ($fs->type eq 'btrfs') {
                my ($status, @info) = runCommand("btrfs subvol show @{[$fs->mount]}");
                if ($status != 0) {
                    die "Failed to retreive subvolume info for @{[$fs->mount]}";
                }
                my @subvols = join("", @info) =~ m/Name:[ \t\n]*([^ \t\n]*)/;
                if ($#subvols > 0) {
                    die "Btrfs subvol name for @{[$fs->device]} listed multiple times in mount\n"
                } elsif ($#subvols == 0) {
                    $path = "/$subvols[0]$path";
                }
            }
        }
        if (not $search eq "") {
            $search = "search --set=drive$driveid " . $search;
            $path = "(\$drive$driveid)$path";
            $driveid += 1;
        }
    }
    return Grub->new(path => $path, search => $search);
}
my $grubBoot = GrubFs("/boot");
my $grubStore = GrubFs("/nix/store");

# We don't need to copy if we can read the kernels directly
if ($grubStore->search ne "") {
    $copyKernels = 0;
}

# Generate the header.
my $conf .= "# Automatically generated.  DO NOT EDIT THIS FILE!\n";

if ($grubVersion == 1) {
    $conf .= "
        default $defaultEntry
        timeout $timeout
    ";
    if ($splashImage) {
        copy $splashImage, "/boot/background.xpm.gz" or die "cannot copy $splashImage to /boot\n";
        $conf .= "splashimage " . $grubBoot->path . "/background.xpm.gz\n";
    }
}

else {
    $conf .= "
        " . $grubBoot->search . "
        " . $grubStore->search . "
        if [ -s \$prefix/grubenv ]; then
          load_env
        fi

        # ‘grub-reboot’ sets a one-time saved entry, which we process here and
        # then delete.
        if [ \"\${saved_entry}\" ]; then
          # The next line *has* to look exactly like this, otherwise KDM's
          # reboot feature won't work properly with GRUB 2.
          set default=\"\${saved_entry}\"
          set saved_entry=
          set prev_saved_entry=
          save_env saved_entry
          save_env prev_saved_entry
          set timeout=1
        else
          set default=$defaultEntry
          set timeout=$timeout
        fi

        if loadfont " . $grubBoot->path . "/grub/fonts/unicode.pf2; then
          set gfxmode=640x480
          insmod gfxterm
          insmod vbe
          terminal_output gfxterm
        fi
    ";

    if ($splashImage) {
        # FIXME: GRUB 1.97 doesn't resize the background image if it
        # doesn't match the video resolution.
        copy $splashImage, "/boot/background.png" or die "cannot copy $splashImage to /boot\n";
        $conf .= "
            insmod png
            if background_image " . $grubBoot->path . "/background.png; then
              set color_normal=white/black
              set color_highlight=black/white
            else
              set menu_color_normal=cyan/blue
              set menu_color_highlight=white/blue
            fi
        ";
    }
}

$conf .= "$extraConfig\n";


# Generate the menu entries.
$conf .= "\n";

my %copied;
mkpath("/boot/kernels", 0, 0755) if $copyKernels;

sub copyToKernelsDir {
    my ($path) = @_;
    return $grubStore->path . substr($path, length("/nix")) unless $copyKernels;
    $path =~ /\/nix\/store\/(.*)/ or die;
    my $name = $1; $name =~ s/\//-/g;
    my $dst = "/boot/kernels/$name";
    # Don't copy the file if $dst already exists.  This means that we
    # have to create $dst atomically to prevent partially copied
    # kernels or initrd if this script is ever interrupted.
    if (! -e $dst) {
        my $tmp = "$dst.tmp";
        copy $path, $tmp or die "cannot copy $path to $tmp\n";
        rename $tmp, $dst or die "cannot rename $tmp to $dst\n";
    }
    $copied{$dst} = 1;
    return $grubBoot->path . "/kernels/$name";
}

sub addEntry {
    my ($name, $path) = @_;
    return unless -e "$path/kernel" && -e "$path/initrd";

    my $kernel = copyToKernelsDir(Cwd::abs_path("$path/kernel"));
    my $initrd = copyToKernelsDir(Cwd::abs_path("$path/initrd"));
    my $xen = -e "$path/xen.gz" ? copyToKernelsDir(Cwd::abs_path("$path/xen.gz")) : undef;

    # FIXME: $confName

    my $kernelParams =
        "systemConfig=" . Cwd::abs_path($path) . " " .
        "init=" . Cwd::abs_path("$path/init") . " " .
        readFile("$path/kernel-params");
    my $xenParams = $xen && -e "$path/xen-params" ? readFile("$path/xen-params") : "";

    if ($grubVersion == 1) {
        $conf .= "title $name\n";
        $conf .= "  $extraPerEntryConfig\n" if $extraPerEntryConfig;
        $conf .= "  kernel $xen $xenParams\n" if $xen;
        $conf .= "  " . ($xen ? "module" : "kernel") . " $kernel $kernelParams\n";
        $conf .= "  " . ($xen ? "module" : "initrd") . " $initrd\n\n";
    } else {
        $conf .= "menuentry \"$name\" {\n";
        $conf .= $grubBoot->search . "\n";
        $conf .= $grubStore->search . "\n";
        $conf .= "  $extraPerEntryConfig\n" if $extraPerEntryConfig;
        $conf .= "  multiboot $xen $xenParams\n" if $xen;
        $conf .= "  " . ($xen ? "module" : "linux") . " $kernel $kernelParams\n";
        $conf .= "  " . ($xen ? "module" : "initrd") . " $initrd\n";
        $conf .= "}\n\n";
    }
}


# Add default entries.
$conf .= "$extraEntries\n" if $extraEntriesBeforeNixOS;

addEntry("NixOS - Default", $defaultConfig);

$conf .= "$extraEntries\n" unless $extraEntriesBeforeNixOS;

# extraEntries could refer to @bootRoot@, which we have to substitute
$conf =~ s/\@bootRoot\@/$grubBoot->path/g;

# Emit submenus for all system profiles.
sub addProfile {
    my ($profile, $description) = @_;

    # Add entries for all generations of this profile.
    $conf .= "submenu \"$description\" {\n" if $grubVersion == 2;

    sub nrFromGen { my ($x) = @_; $x =~ /\/\w+-(\d+)-link/; return $1; }

    my @links = sort
        { nrFromGen($b) <=> nrFromGen($a) }
        (glob "$profile-*-link");

    my $curEntry = 0;
    foreach my $link (@links) {
        last if $curEntry++ >= $configurationLimit;
        my $date = strftime("%F", localtime(lstat($link)->mtime));
        my $version =
            -e "$link/nixos-version"
            ? readFile("$link/nixos-version")
            : basename((glob(dirname(Cwd::abs_path("$link/kernel")) . "/lib/modules/*"))[0]);
        addEntry("NixOS - Configuration " . nrFromGen($link) . " ($date - $version)", $link);
    }

    $conf .= "}\n" if $grubVersion == 2;
}

addProfile "/nix/var/nix/profiles/system", "NixOS - All configurations";

if ($grubVersion == 2) {
    for my $profile (glob "/nix/var/nix/profiles/system-profiles/*") {
        my $name = basename($profile);
        next unless $name =~ /^\w+$/;
        addProfile $profile, "NixOS - Profile '$name'";
    }
}

# Run extraPrepareConfig in sh
if ($extraPrepareConfig ne "") {
  system((get("shell"), "-c", $extraPrepareConfig));
}

# Atomically update the GRUB config.
my $confFile = $grubVersion == 1 ? "/boot/grub/menu.lst" : "/boot/grub/grub.cfg";
my $tmpFile = $confFile . ".tmp";
writeFile($tmpFile, $conf);
rename $tmpFile, $confFile or die "cannot rename $tmpFile to $confFile\n";


# Remove obsolete files from /boot/kernels.
foreach my $fn (glob "/boot/kernels/*") {
    next if defined $copied{$fn};
    print STDERR "removing obsolete file $fn\n";
    unlink $fn;
}


# Install GRUB if the version changed from the last time we installed
# it.  FIXME: shouldn't we reinstall if ‘devices’ changed?
my $prevVersion = readFile("/boot/grub/version") // "";
if (($ENV{'NIXOS_INSTALL_GRUB'} // "") eq "1" || get("fullVersion") ne $prevVersion) {
    foreach my $dev ($dom->findnodes('/expr/attrs/attr[@name = "devices"]/list/string/@value')) {
        $dev = $dev->findvalue(".") or die;
        next if $dev eq "nodev";
        print STDERR "installing the GRUB $grubVersion boot loader on $dev...\n";
        system("$grub/sbin/grub-install", "--recheck", Cwd::abs_path($dev)) == 0
            or die "$0: installation of GRUB on $dev failed\n";
    }
    writeFile("/boot/grub/version", get("fullVersion"));
}
