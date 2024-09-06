#!/bin/bash

# Provide the mountpoint of the backup as argument. Otherwhise /mnt/disc-nc-bkp is used
DISK_MTPNT=${1:-"/mnt/disc-nc-bkp"}

BORG_MOUNTPOINT=/tmp/unencr-disc-nc-bkp

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
borg mount --foreground -o ro,uid=$(id -u),gid=$(id -g) "$DISK_MTPNT" "$BORG_MOUNTPOINT"

# Clean up
rm -r "$BORG_MOUNTPOINT"
echo "Cleaned up"
echo "Press ENTER to exit"
read


