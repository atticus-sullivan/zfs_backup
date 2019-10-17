#!/bin/bash
lastBackupDone=$(cat /media/daten/scripts/zfs-bash/backupDone.txt)
if [[ 10#$lastBackupDone -ne 10#$(date +%m) ]]
then
    notify-send "Backups" "Please connect to saveSpace and run /media/daten/scripts/zfs-bash/backups.sh"
fi
exit
