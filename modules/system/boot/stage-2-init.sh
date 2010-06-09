#! @shell@

# !!! copied from stage 1; remove duplication


# If no `systemConfig' parameter is specified on the kernel command
# line, use a fallback.
systemConfig=/nix/var/nix/profiles/system


# Print a greeting.
echo
echo -e "\e[1;32m<<< NixOS Stage 2 >>>\e[0m"
echo


# Set the PATH.
setPath() {
    local dirs="$1"
    export PATH=/empty
    for i in $dirs; do
        PATH=$PATH:$i/bin
        if test -e $i/sbin; then
            PATH=$PATH:$i/sbin
        fi
    done
}

setPath "@path@"


# Normally, stage 1 mounts the root filesystem read/writable.
# However, in some environments (such as Amazon EC2), stage 2 is
# executed directly, and the root is read-only.  So make it writable
# here.
mount -n -o remount,rw none /


# Mount special file systems.  Note that /dev, /proc and /sys are
# already mounted by `switch_root' in the initrd.
mkdir -m 0755 -p /etc
test -e /etc/fstab || touch /etc/fstab # to shut up mount
test -s /etc/mtab && rm /etc/mtab # while installing a symlink is created (see man mount), if it's still there for whateever reason remove it
rm -f /etc/mtab* # not that we care about stale locks

rm -f /etc/mtab
cat /proc/mounts > /etc/mtab


# Process the kernel command line.
for o in $(cat /proc/cmdline); do
    case $o in
        debugtrace)
            # Show each command.
            set -x
            ;;
        debug2)
            echo "Debug shell called from @out@"
            exec @shell@
            ;;
        S|s|single)
            # !!! argh, can't pass a startup event to Upstart yet.
            exec @shell@
            ;;
        safemode)
            safeMode=1
            ;;
        systemConfig=*)
            set -- $(IFS==; echo $o)
            systemConfig=$2
            ;;
        resume=*)
            set -- $(IFS==; echo $o)
            resumeDevice=$2
            ;;
    esac
done


# More special file systems, initialise required directories.
mkdir -m 0777 /dev/shm
mount -t tmpfs -o "rw,nosuid,nodev,size=@devShmSize@" tmpfs /dev/shm
mkdir -m 0755 -p /dev/pts
mount -t devpts -o mode=0600,gid=@ttyGid@ none /dev/pts 
[ -e /proc/bus/usb ] && mount -t usbfs none /proc/bus/usb # UML doesn't have USB by default
mkdir -m 01777 -p /tmp 
mkdir -m 0755 -p /var
mkdir -m 0755 -p /nix/var
mkdir -m 0700 -p /root
mkdir -m 0755 -p /bin # for the /bin/sh symlink
mkdir -m 0755 -p /home
mkdir -m 0755 -p /etc/nixos


# Miscellaneous boot time cleanup.
rm -rf /var/run
rm -rf /var/lock
rm -rf /var/log/upstart

#echo -n "cleaning \`/tmp'..."
#rm -rf --one-file-system /tmp/*
#echo " done"


# This is a good time to clean up /nix/var/nix/chroots.  Doing an `rm
# -rf' on it isn't safe in general because it can contain bind mounts
# to /nix/store and other places.  But after rebooting these are all
# gone, of course.
rm -rf /nix/var/nix/chroots # recreated in activate-configuration.sh


# Use a tmpfs for /var/run to ensure that / or /var can be unmounted
# or at least remounted read-only during shutdown.  (Upstart 0.6
# apparently uses nscd to do some name lookups, resulting in it
# holding some mmap mapping to deleted files in /var/run/nscd.
# Similarly, portmap and statd have open files in /var/run and are
# needed during shutdown to unmount NFS volumes.)
mkdir -m 0755 -p /var/run
mount -t tmpfs -o "mode=755" none /var/run


# Clear the resume device.
if test -n "$resumeDevice"; then
    mkswap "$resumeDevice" || echo 'Failed to clear saved image.'
fi


# Run the script that performs all configuration activation that does
# not have to be done at boot time.
echo "running activation script..."
@activateConfiguration@ "$systemConfig"


# Record the boot configuration.  !!! Should this be a GC root?
if test -n "$systemConfig"; then
    ln -sfn "$systemConfig" /var/run/booted-system
fi


# Ensure that the module tools can find the kernel modules.
export MODULE_DIR=@kernel@/lib/modules/


# Run any user-specified commands.
@shell@ @postBootCommands@


# For debugging Upstart.
#@shell@ --login < /dev/console > /dev/console 2>&1 &


# Start Upstart's init.
echo "starting Upstart..."
PATH=/var/run/current-system/upstart/sbin exec init
