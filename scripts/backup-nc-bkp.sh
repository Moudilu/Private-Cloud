#!/usr/bin/bash

#################################################
# Sync Nextcloud backup to other drives
#
# The destination where to sync the backup to can be an rclone remote or a local path.
# If it is omitted, the remote 'remote-nc-bkp' is used.
#
# Credits to the following sources which helped me developing this script:
#  https://www.reddit.com/r/linuxadmin/comments/gh591f/comment/fq7rz44/?context=3
#  https://github.com/nextcloud/all-in-one/discussions/2247
#  https://github.com/nextcloud/all-in-one#sync-the-backup-regularly-to-another-drive
#################################################

SOURCE_DIRECTORY="/srv/nc-bkp"
DESTINATION="${1:-remote-nc-bkp}"

TARGET_DIRECTORY="backup/$(hostname)/nc-bkp"

STATS_DIR=/var/lib/private-cloud/stats
TEXTFILE_COLLECTOR_DIR=/var/lib/prometheus/node-exporter

#################################################
# Validation of environment
#################################################
if [ "$EUID" -ne 0 ]; then
    echo "Script has to be run as root"
    output 1
fi
if ! [ -d "$SOURCE_DIRECTORY" ]; then
    echo "The source directory does not exist."
    exit 1
fi
if [ -z "$(ls -A "$SOURCE_DIRECTORY/")" ]; then
    echo "The source directory is empty, which is not allowed."
    exit 1
fi
if [[ $DESTINATION == */* ]]; then
    # The destination contains a directory separator, it is a local path
    RCLONE_REMOTE_SEPARATOR="/"
    DESTINATION_FILE_STRING=${DESTINATION//\//-} # replace slashes with dashes, for use in filenames
    if ! install -m 755 -d "$DESTINATION/$TARGET_DIRECTORY" ; then
        echo "Could not create target directory."
        exit 1
    fi
else
    # The destination is a rclone remote
    RCLONE_REMOTE_SEPARATOR=":"
    DESTINATION_FILE_STRING=$DESTINATION
fi

#################################################
# Acquire lock on backup
#################################################
# Test existence of lock.roster, and test existence and otherwhise create aio-lockfile in one command (atomically). For this, the option noclobber must be set.
# If any of the files exist, wait until they are deleted (possibly infinitely), and then try again to create the lockfile
set -o noclobber
while [ -f "$SOURCE_DIRECTORY/lock.roster" ] || ! { > "$SOURCE_DIRECTORY/aio-lockfile" ; } &> /dev/null ; do
    if [ -f "$SOURCE_DIRECTORY/lock.roster" ] ; then
        echo "The backup archive is currently being modified. Waiting until it is deleted."
        inotifywait -e delete_self -qq "$SOURCE_DIRECTORY/lock.roster"
        echo "The backup archive was closed. Continue backup."
    fi

    if [ -f "$SOURCE_DIRECTORY/aio-lockfile" ] ; then
        echo "The aio-lockfile already exists. Waiting until it is deleted."
        inotifywait -e delete_self -qq "$SOURCE_DIRECTORY/aio-lockfile"
        echo "The aio-lockfile was deleted. Continue backup."
    fi
done
set +o noclobber

#################################################
# Run backup
#################################################
START_TIME="$(date +%s)"
# TODO: add options --rc --rc-enable-metrics, scrape them. E.g. by running rclone as a background process, curling the metrics into some textfile collector file. See https://stackoverflow.com/questions/1570262/get-exit-code-of-a-background-process on how to run process in background, wait until it completes and get its exit status
RCLONE_CONFIG_PASS=`cat /etc/rclone.configpass` rclone sync "$SOURCE_DIRECTORY/" "${DESTINATION}${RCLONE_REMOTE_SEPARATOR}${TARGET_DIRECTORY}" --exclude aio-lockfile --create-empty-src-dirs
EXIT_CODE=$?
END_TIME="$(date +%s)"

#################################################
# Report metrics, logging & cleanup
#################################################
# Update the prometheus metrics textfile and the stats with some metrics
# Load the stats, initialize with default values if they don't exist yet
if [ -f "${STATS_DIR}/${DESTINATION_FILE_STRING}.stats" ]; then
    source "${STATS_DIR}/${DESTINATION_FILE_STRING}.stats"
else
    SUCCESSFUL_BACKUP_RUNS=0
fi
if [ ${EXIT_CODE} -eq 0 ] ; then
    SUCCESSFUL_BACKUP_RUNS=$((${SUCCESSFUL_BACKUP_RUNS} + 1))
fi
cat << EOF > "${STATS_DIR}/${DESTINATION_FILE_STRING}.stats"
SUCCESSFUL_BACKUP_RUNS=${SUCCESSFUL_BACKUP_RUNS}
EOF

LAST_BACKUP_SIZE=$(du -bs "${SOURCE_DIRECTORY}" | cut -f1)

cat << EOF > "${TEXTFILE_COLLECTOR_DIR}/nextcloud-backup-${DESTINATION_FILE_STRING}.prom.$$"
# HELP nextcloud_backup_sync_duration_seconds backup duration in seconds
# TYPE nextcloud_backup_sync_duration_seconds gauge
nextcloud_backup_sync_duration_seconds{remote="${DESTINATION}"} $((${END_TIME} - ${START_TIME}))

# HELP nextcloud_backup_sync_last_run_seconds timestamp of when the last backup job finished 
# TYPE nextcloud_backup_sync_last_run_seconds counter
nextcloud_backup_sync_last_run_seconds{remote="${DESTINATION}"} ${END_TIME}

# HELP nextcloud_backup_sync_bytes size of the backup 
# TYPE nextcloud_backup_sync_bytes gauge
nextcloud_backup_sync_bytes{remote="${DESTINATION}"} ${LAST_BACKUP_SIZE}

# HELP nextcloud_backup_sync_exit_code exit code of the last backup job (0 = success)
# TYPE nextcloud_backup_sync_exit_code gauge
nextcloud_backup_sync_exit_code{remote="${DESTINATION}"} ${EXIT_CODE}

# HELP nextcloud_backup_sync_successful_backup_count increments with every succesfull backup sync
# TYPE nextcloud_backup_sync_successful_backup_count counter
nextcloud_backup_sync_successful_backup_count{remote="${DESTINATION}"} ${SUCCESSFUL_BACKUP_RUNS}
EOF
# Rename the temporary file atomically.
# This avoids the node exporter seeing half a file.
mv "${TEXTFILE_COLLECTOR_DIR}/nextcloud-backup-${DESTINATION_FILE_STRING}.prom.$$" \
  "${TEXTFILE_COLLECTOR_DIR}/nextcloud-backup-${DESTINATION_FILE_STRING}.prom"

if [ ${EXIT_CODE} -eq 0 ] ; then
    if docker ps --format "{{.Names}}" | grep "^nextcloud-aio-nextcloud$"; then
        docker exec -en nextcloud-aio-nextcloud bash /notify.sh "Backup to $DESTINATION successful!" "Synchronised the backup repository successfully to $DESTINATION."
    else
        echo "Synchronised the backup repository successfully to $DESTINATION."
    fi
else
    if docker ps --format "{{.Names}}" | grep "^nextcloud-aio-nextcloud$"; then
        docker exec -en nextcloud-aio-nextcloud bash /notify.sh "Backup to $DESTINATION failed." "Failed to synchronise the backup repository to $DESTINATION."
    else
        echo "Failed to synchronise the backup repository to $DESTINATION."
    fi
fi

rm "$SOURCE_DIRECTORY/aio-lockfile"
exit $EXIT_CODE