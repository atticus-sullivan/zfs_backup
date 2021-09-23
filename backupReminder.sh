#!/bin/bash

path="$(readlink -f "${0%/*}")" # collect the path from how the script was called and canonicalize the path

lastBackupDone="$(cat "${path}/backupDone.txt")"
now="$(date +%s)"
daysAgo="$(( (10#$now - 10#$lastBackupDone) / (60*60*24) ))"

printf "Last backup is $daysAgo days ago\n"

if [[ "$daysAgo" -ge "$1" ]]
then
    notify-send "Backups" "Please make a backup again"
fi
exit 0
