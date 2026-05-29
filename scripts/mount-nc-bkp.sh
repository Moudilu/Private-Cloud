#!/bin/bash

# Provide the mountpoint of the backup as argument. Otherwhise the cloud backup is used
BACKUP_LOCATION=${1:-"remote-nc-bkp:backup/$(hostname)/srv/nc-bkp"}

echo "Mounting borg backup from $BACKUP_LOCATION ..."

# if the repository contains a colon, it must a cloud location and must be mounted by rclone
if [[ "$BACKUP_LOCATION" == *:* ]] ; then
    REMOTE_BKP_MOUNTPOINT="$(mktemp -d)"
    echo "Mounting cloud backup folder to $REMOTE_BKP_MOUNTPOINT"
    if [[ -z "$RCLONE_CONFIG_PASS" ]]; then
        echo "Enter your rclone password if you have one."
        echo "To silence prompts for rclone configuration password, set the environment variable RCLONE_CONFIG_PASS"
    fi
    rclone mount "$BACKUP_LOCATION" "$REMOTE_BKP_MOUNTPOINT" --vfs-cache-mode=full --daemon
    BORG_REPOSITORY="$REMOTE_BKP_MOUNTPOINT"
else
    # for local paths, no special operation is needed
    BORG_REPOSITORY="$BACKUP_LOCATION"
fi

BORG_MOUNTPOINT="$(mktemp -d)"

# Check if sudo is required for accessing the borg backup
if [[ -w "$BORG_REPOSITORY/borg" ]] ; then
    SUDO=""
    MOUNT_OPTIONS="ro,uid=$(id -u),gid=$(id -g)"
else
    SUDO="sudo"
    MOUNT_OPTIONS="ro,uid=$(id -u),gid=$(id -g),allow_other"
fi

cat <<EOF
Mounting backup to "$BORG_MOUNTPOINT"

The warning about the changed location can be safely ignored.
The backup is mounted read-only.

EOF

# Mount the backup with borg
$SUDO borg mount -o ${MOUNT_OPTIONS} "$BORG_REPOSITORY/borg" "$BORG_MOUNTPOINT"

# wait until user is done
if [ "$EUID" -eq 0 ] ; then
    echo "Opening shell to examine the backup. When done, exit the shell."
    (cd "$BORG_MOUNTPOINT" && $SHELL)
elif [ -x "$(command -v xdg-open)" ]; then
    xdg-open "$BORG_MOUNTPOINT"
    read -sp "When done, close all open programs accessing the backup and press ENTER here"
    echo
fi


# Clean up
$SUDO fusermount -zu "$BORG_MOUNTPOINT" && rm -fd "$BORG_MOUNTPOINT" # since the mount is readonly, lazy unmount should be safe

if [ -n "$REMOTE_BKP_MOUNTPOINT" ] ; then
    $SUDO fusermount -zu "$REMOTE_BKP_MOUNTPOINT" && rm -fd "$REMOTE_BKP_MOUNTPOINT"
fi

echo "Cleaned up"
