#!/bin/bash
#Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;44m'
NC='\033[0;0m'

path="$(readlink -f "${0%/*}")" # collect the path from how the script was called and canonicalize the path
#############################################LOAD-CONFIG##############################################################
# global variables with respect to configuration are stored in the backup.cfg file
if [[ -f ./backup.cfg ]]
then
	source ./backup.cfg
fi

if [[ ! (-v backupPool && -v requiredPools && -v poolSnapshot && -v arraySets) ]]
then
	printf "${RED}Error:${NC} "
	printf "%s\n" \
		"Global variables are missing, most probably some settings in the 'backup.cfg' are missing." \
		"       See the 'backup.cfg.def' for an example." \
		"       List of needed variables: backupPool, requiredPools, poolSnapshot, arraySets"
	exit 2
else
	echo "Everything set"
fi

###########################################FUNCTIONS-START############################################################
myExit(){
  read -p "enter: " -r muell

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
    printf "${RED}Error:${NC} Snapshot for $1 couldn't be created -> exit \n"
    myExit
  else
    printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), created $1\n"
  fi
}

replicateSnap(){
	printf "Replicate $1 > $2\nDo ${RED}not${NC} interrupt this process!!!\n"

	echo "To watch the progress run \"watch sudo zpool iostat\" in a extra terminal"

	if ! zfs send "$1" | zfs recv "$2" -F
	then
		printf "${RED}Error:${NC} Replication \033[1;31mfailed${NC} -> exit\n"
		myExit
	else
		printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T"), $1 > $2\n\n"
	fi
}
###########################################FUNCTIONS-END############################################################

###########################################EXECUTE-SCRIPT##########################################################
execFunc(){

	stat=$(cat ${path}/stat.txt)
	if [[ ! ( "$stat" =~ ^[0-9]+$  && "$stat" -ge 0 %% "$stat" -lt "${#backupDsNames[@]}" ) ]]
	then
		printf "${RED}Error:${NC} no valid value for ${path}/stat.txt -> exit\n       This shouldn't have happened if you didn't modify the file" #TODO @Gala hint für unerfahrene user hier?
		exit 1
	fi
	echo "$(( (stat + 1) % ${#backupDsNames[@]} ))" > ${path}/stat.txt
	bakSet="${backupDsNames[stat]}"
	
	echo -e "BackupDataSet is \"$bakSet\""
	read -rp "Press Enter to continue (ctrl+C to abort) " muell
	
	# echo ${arraySets[*]%%/*} | tr " " "\n" | sort -u

	#import
	printf "\n${BLUE}Import Devices${NC}\n"
	for pool in "${requiredPools[@]}"
	do
		if ! zpool import $pool
		then
			printf "${RED}Error:${NC} Unable to import the pool ($pool), make shure the device is connected and isn't imorted -> exit \n"
			exit
		else
			printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T")\n\n"
		fi
	done
	
	#calc space needed
	needed=0
	for processing in "${arraySets[@]}"
	do
	  tmp=$(zfs list -p | grep "$processing " | tr -s " " | cut -d " " -f 4)
	  needed=$(( 10#$needed + 10#$tmp ))
	done
	
	#fields in zfs list: 1.Name    2.used     3.avail     4.refer     5.mountpoint
	
	freeSpaceOnBackup=$(zfs list -p | grep "$backupPool " | tr -s " " | cut -d " " -f 3)
	
	#debug-start
	#zfs list -p
	#echo "zfs list -p | grep ${backupPool}/${bakSet} "
	#zfs list -p | grep "${backupPool}/${bakSet} "
	#zfs list -p | grep "${backupPool}/${bakSet} " | tr -s " " | cut -d " " -f 2
	#myExit
	#debug-end

	# subtracts the space used by the backup which will get overwritten (since no additional snapshots should be available, the avail column can be used
	freeSpaceOnBackup=$(( freeSpaceOnBackup + $(zfs list -p | grep "${backupPool}/${bakSet} " | tr -s " " | cut -d " " -f 2) ))
	
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
	  replicateSnap "${processing}@${poolSnapshot}" "${backupPool}/${bakSet}/${processing#*/}"
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
	
	date +%m > ${path}/backupDone.txt #To remember when the last Backup took place (for the reminder to do Backups)
	###########################################EXECUTE-SCRIPT-END######################################################
	exit
}

path="/media/daten/coding/zfs-bash"

# check if started with sudo
if [[ "$EUID" -ne 0 ]]
then
	printf "%s\n" "This script has to be run as root (sudo)"
	exit 1
fi

mv "${path}/backup.log.0" "${path}/backup.log.1"
mv "${path}/backup.log" "${path}/backup.log.0"

execFunc noGui | tee ${path}/backup.log
