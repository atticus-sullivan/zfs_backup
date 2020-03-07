#!/bin/bash
#Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;44m'
NC='\033[0;0m'

###########################################FUNCTIONS-START############################################################
myExit(){
	read -r muell
	return

  echo -e "\n Trying to export the Pool anyway"
  if ! zpool export "$backupPool"
  then
    printf " ${RED}Error:${NC} Backup-device couldn't been exported \n"
  else
    printf " ${GREEN}Successful${NC} \n"
  fi
  exit
}

destroySnap(){
  if ! zfs destroy "$1"
  then
    printf "${RED}Error:${NC} Unable to destroy the old Snapshot. -> exit \n"
    myExit
  else
    printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), destroyed $1\n"
  fi
}

createSnap(){
  if ! zfs snapshot "$1"
  then
    printf "${RED}Error:${NC} Snapshot couldn't be created -> exit \n"
    myExit
  else
    printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), created $1\n"
  fi
}

replicateSnap(){
  printf "Replicate $1 > $2\nDo ${RED}not${NC} interrupt this process!!!\n"

  if [[ "$3" == 1 ]]
  then
    gnome-terminal -e "watch zpool iostat"
  else
    echo "To watch the progress run \"watch sudo zpool iostat\" in a extra terminal"
  fi

  if ! zfs send "$1" | zfs recv "$2" -F
  then
    printf "${RED}Error:${NC} Replication \033[1;31mfailed${NC} -> exit\n"
    myExit
  else
    printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), $1 > $2\n\n"
  fi
}
###########################################FUNCTIONS-END############################################################

###########################################CHECK-PARAMTETERS########################################################
execFunc(){
	i=1
	gui=0
	for argument in "$@"
	do
	  echo "Argument ${i}: \"$argument\""
	
	  if [[ "$argument" == "--gui" ]]
	  then
	    gui=1
	    echo "Executing script for with a gui environment"
	  fi
	done
	###########################################CHECK-PARAMTETERS-END###################################################
	
	###########################################EXECUTE-SCRIPT##########################################################
	stat=$(cat /media/daten/scripts/zfs-bash/stat.txt)
	if [[ "$stat" == "1" ]]
	then
	  bakSet=bak1
	  echo "2" > /media/daten/scripts/zfs-bash/stat.txt #########nur ein Backup vorerst, sonst muss auf den index des nächsten datasets gesetzt werden
	elif [[ "$stat" == "2" ]]
	then
	  bakSet=bak2
	  echo "1" > /media/daten/scripts/zfs-bash/stat.txt
	else
	  printf "${RED}Error:${NC} kein gültiger Wert in /media/daten/scripts/zfs-bash/stat.txt -> exit \n"
	  exit
	fi
	
	echo -e "BackupDataSet ist \"$bakSet\""
	read -rp "Press Enter to continue " muell
	
	##Variables
	backupPool="backup"
	poolSnapshot="replication"
	arraySets=("data/home/lukas" "data/daten" "data/daten/downloads" "data/daten/filme")
	#backSet von oben
	
	#import
	printf "\n${BLUE}Import the Backup-Device${NC}\n"
	if ! zpool import $backupPool
	then
	  printf "${RED}Error:${NC} Unable to import the BackupPool ($backupPool), make shure the device is connected and isn't imorted -> exit \n"
	  exit
	else
	  printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T")\n\n"
	fi
	
	#calc space needed
	needed=0
	for processing in "${arraySets[@]}"
	do
	  tmp=$(zfs list -p | grep "$processing " | tr -s " " | cut -d " " -f 4)
	  needed=$(( 10#$needed + 10#$tmp ))
	done
	
	#fields bei zfs list: 1.Name    2.used     3.avail     4.refer     5.mountpoint
	
	freeSpaceOnBackup=$(zfs list -p | grep "$backupPool " | tr -s " " | cut -d " " -f 3)
	
	#debug-start
	#zfs list -p
	#echo "zfs list -p | grep ${backupPool}/${bakSet} "
	#zfs list -p | grep "${backupPool}/${bakSet} "
	#zfs list -p | grep "${backupPool}/${bakSet} " | tr -s " " | cut -d " " -f 2
	#myExit
	#debug-end
	
	freeSpaceOnBackup=$(( freeSpaceOnBackup + $(zfs list -p | grep "${backupPool}/${bakSet} " | tr -s " " | cut -d " " -f 2) )) #zieht den Platz ab der vom Backup verbraucht wird, das eh überschrieben wird (sollten keine Snapshots vorhanden sein, also kann die avail-Spalte verwendet werden)
	
	divisionForGb=1000000000
	if [[ "$freeSpaceOnBackup" -lt "$needed" ]]
	then
	  printf "${RED}Error:${NC} Too much data to backup, the targetPool($backupPool) is too full ($backupPool has $(( 10#${freeSpaceOnBackup} / 10#${divisionForGb} )),$(((10#${freeSpaceOnBackup}%10#${divisionForGb})*10/10#${divisionForGb} )) GB (exactly ${freeSpaceOnBackup} bytes) left but there is $(( 10#${needed} / 10#${divisionForGb} )),$(((10#${needed}%10#${divisionForGb})*10/10#${divisionForGb} )) GB (exactly ${needed} bytes) to be backedUp) -> exit\n"
	  myExit
	else
	  printf "${GREEN}Successful:${NC} Enough place on BackupPool ($backupPool has $(( 10#${freeSpaceOnBackup} / 10#${divisionForGb} )),$(((10#${freeSpaceOnBackup}%10#${divisionForGb})*10/10#${divisionForGb} )) GB ($freeSpaceOnBackup Bytes) left, there is $(( 10#${needed} / 10#${divisionForGb} )),$(((10#${needed}%10#${divisionForGb})*10/10#${divisionForGb} )) GB ($needed Bytes) to be backedUp)   \n"
	fi
	
	#Destroy Old Backup Snapshot 
	printf "\n${BLUE}Destroy old Backup Snapshot${NC}\n"
	
	for processing in "${arraySets[@]}"
	do :
	  destroySnap "${backupPool}/${bakSet}/${processing#*/}@${poolSnapshot}"
	done
	
	#create snapshot
	printf "\n${BLUE}Create current Snapshot to replicate${NC}\n"
	for processing in "${arraySets[@]}"
	do
	  createSnap "${processing}@${poolSnapshot}"
	done
	
	#Replication
	printf "\n${BLUE}Start Replication${NC}\n"
	for processing in "${arraySets[@]}"
	do
	  echo -e "\n\n"
	  zpool iostat
	  replicateSnap "${processing}@${poolSnapshot}" "${backupPool}/${bakSet}/${processing#*/}" "$gui"
	done
	
	#Destroy source Snapshot
	printf "${BLUE}Destroy Source Snapshot: ${backupPool}/${bakSet}@${poolSnapshot}${NC}\n"
	for processing in "${arraySets[@]}"
	do
	  destroySnap "${processing}@${poolSnapshot}"
	done
	
	#export
	printf "\n${BLUE}Export Backup device${NC}\n"
	if ! zpool export $backupPool
	then
	  printf "${RED}Error:${NC} Backup-device couldn't been exported \n"
	  exit
	else
	  printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), exported $backupPool\n"
	fi
	
	printf "\nAll Tasks are ${GREEN}successfully${NC} done at $(date "+%Y-%m-%d %T")\n"
	
	date +%m > /media/daten/scripts/zfs-bash/backupDone.txt #To remember when the last Backup took place (for the reminder to do Backups)
	###########################################EXECUTE-SCRIPT-END######################################################
	exit
}

path="/media/daten/scripts/zfs-bash/"

mv "${path}/backups.log.0" "${path}/backups.log.1"
mv "${path}/backups.log" "${path}/backups.log.0"

execFunc noGui | tee /media/daten/scripts/zfs-bash/backup.log
