#!/bin/bash

REMOTE_BKP_MOUNTPOINT="/tmp/cloud-nc-bkp"
BORG_MOUNTPOINT="/tmp/unencr-cloud-nc-bkp"

# Mount cloud backup
mkdir "$REMOTE_BKP_MOUNTPOINT"
echo "Mounting cloud backup folder to $REMOTE_BKP_MOUNTPOINT"
if [[ -z "$RCLONE_CONFIG_PASS" ]]; then
    echo "To silence prompts for rclone configuration password, set the environment variable RCLONE_CONFIG_PASS"
fi
rclone mount "remote-nc-bkp:" "$REMOTE_BKP_MOUNTPOINT" --vfs-cache-mode=full --daemon 

# Open explorer
mkdir "$BORG_MOUNTPOINT"
if [ -x "$(command -v xdg-open)" ]; then
    xdg-open "$BORG_MOUNTPOINT"
fi

cat <<EOF
Mounting unencrypted backup to "$BORG_MOUNTPOINT"

Enter the password for your backup. The warning that the repository
was previously located somewhere else can be ignored safely.
After entering the password, wait a bit and hit F5 in
the file explorer to see the files. You'll need some patience, loading
the directory structure for the first time takes a while.
The backup is mounted read-only.
When you're done, hit Ctrl+C in this window.

EOF

# Mount the backup with borg
borg mount --foreground -o ro,uid=$(id -u),gid=$(id -g) "$REMOTE_BKP_MOUNTPOINT/borg" "$BORG_MOUNTPOINT"

# Clean up
fusermount -u "$REMOTE_BKP_MOUNTPOINT"
rm -r "$REMOTE_BKP_MOUNTPOINT"
rm -r "$BORG_MOUNTPOINT"
echo "Cleaned up"
