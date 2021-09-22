#!/bin/bash

lastBackupDone=$(cat /media/daten/scripts/zfs-bash/backupDone.txt)
if [[ 10#$lastBackupDone -ne 10#$(date +%m) ]] # a backup once a month
then
    notify-send "Backups" "Please make a backup again"
fi
exit
