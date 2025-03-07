#!/bin/bash

# Provide the mountpoint of the backup as argument. Otherwhise /mnt/disc-nc-bkp is used
BORG_REPOSITORY=${1:-"/media/nc-bkp-ext/backup/$(hostname)/srv/nc-bkp"}

BORG_MOUNTPOINT=/tmp/unencr-disc-nc-bkp

# If script is not run as root, need to run the borg command with sudo since the backup folder is owned by root and borg needs to write the lock file into it
if [ "$EUID" -ne 0 ] ; then
    SUDO=sudo
else
    SUDO=""
fi

# Open explorer
mkdir -p "$BORG_MOUNTPOINT"
if [ -x "$(command -v xdg-open)" ]; then
    xdg-open "$BORG_MOUNTPOINT"
fi

cat <<EOF
Mounting backup to "$BORG_MOUNTPOINT"

Enter password, then wait a bit and hit F5 in the file explorer to see the files.
The warning about the changed location can be savely ignored.
The backup is mounted read-only.
When you're done, hit Ctrl+C in this window.

EOF

# Mount the backup with borg
$SUDO borg mount --foreground -o allow_other,ro,uid=$(id -u),gid=$(id -g) "$BORG_REPOSITORY/borg" "$BORG_MOUNTPOINT"

# Clean up
rm -d "$BORG_MOUNTPOINT"
echo "Cleaned up"
echo "Press ENTER to exit"
read
