#!/bin/bash
#Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;44m'
NC='\033[0;0m'

###########################################FUNCTIONS-START############################################################

myExit(){
  read -ep "enter: " -r muell 2>&1

  echo -e "\n Trying to export the Pool anyway"
  if ! zpool export "$backupPool"
  then
    printf " ${RED}Error:${NC} Backup-device couldn't been exported \n"
  else
    printf " ${GREEN}Successful${NC} \n"
  fi
  exit
}

checkConfig(){
	printf "%s\n" \
		"Would you like to check your config, before continuing?" \
		"Attention: All devices needed for backupping have to be plugged in to be able to check the config"
	read -ep "[Y]es/[n]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y"  || "$resp" == "" ]]
	then
		readarray -t requiredPools <<<$(printf "%s\n" "${arraySets[@]}" | awk -F"/" '{print $1}' | sort -u)
		requiredPools+=("${backupPool}")

		readarray -t zfsImported <<<$(zpool list | sed 's/  \+/\t/g' | awk -F $'\t' 'NR>1 {print $1}')

		for pool in "${requiredPools[@]}"
		do
			if contains "$pool" "${zfsImported[@]}"
			then # already imported pools do not have to be imported
				continue
			fi
			if ! zfs import "$pools"
			then
				printf "${RED}Error:${NC} importing $pool\n"
				return 1
			fi
		done

		for ds in arraySets
		do
			if ! zfs list "$ds" &>/dev/null
			then
				printf "${RED}Error:${NC} dataset $ds was not found\n"
				return 1
			fi
		done

		for pool in "${requiredPools[@]}"
		do
			if contains "$pool" "${zfsImported[@]}"
			then # pools previously imported shouldn't be exported
				continue
			fi
			if ! zfs export "$pools"
			then
				printf "${RED}Error:${NC} exporting $pool\n"
				return 1
			fi
		done
	fi
}

collectWriteConfig(){
	printf "Do you want to initialize? (guided config creation)\n"
	read -ep "[Y]es/[n]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y" || "$resp" == "" ]]
	then
		backupPool=""
		printf "\n"
		# TODO @Gala check ob pool existiert? Evtl nicht möglich, da nicht eingesteckt...
		read -ep "Name of the pool on which the backups should be on: " backupPool 2>&1
		printf "\n"

		printf "%s\n" \
			"Names/Paths of the datasets that should be used for the backup" \
			"e.g. 'bak1' 'bak2' -> one backup is on dataset 'bak1' and one is on 'bak2' -> the last backup is always available in addition to the current one" \
			"Note that the number of sets you specify here determines how many backups are left on the backupPool" \
			"" \
			"Give the names/paths line by line for each dataset (simply press enter to finish entering new datasets)"
		backupDsNames=()
		ds="x"
		while [[ "$ds" != "" ]]
		do
			read -ep "Name/Path: " ds 2>&1
			[[ "$ds" == "" ]] && continue
			backupDsNames+=("$ds")
		done
		printf "Datasets used for backup: "
		declare -p backupDsNames
		read -ep "Enter to continue: " muell 2>&1
		printf "\n"

		poolSnapshot=""
		read -ep "Name of the snapshot used for replication: " poolSnapshot 2>&1 # TODO @Gala "replication" als default?
		printf "\n"

		printf "%s\n" \
			"Paths of the datasets that should be backed up" \
			"Give the names/paths line by line for each dataset (simply press enter to finish entering new datasets)"
		arraySets=()
		ds="x"
		while [[ "$ds" != "" ]]
		do
			read -ep "Name/Path: " ds 2>&1
			[[ "$ds" == "" ]] && continue
			arraySets+=("$ds")
		done
		printf "Datasets that are backed up: "
		declare -p arraySets
		read -ep "Enter to continue: " muell 2>&1
		printf "\n"

		if ! checkConfig
		then
			return 1
		fi

		{
			printf "%s\n" "backupPool=\"${backupPool}\""

			printf "backupDsNames=("
			printf "\"%s\" " "${backupDsNames[@]}"
			printf ")\n\n"

			printf "%s\n\n" "poolSnapshot=\"${poolSnapshot}\""

			printf "arraySets=("
			printf "\"%s\" " "${arraySets[@]}"
			printf ")\n"
		} > ${path}/backup.cfg
	fi
	return 0
}

createBackupDS(){
	printf "%s\n" \
		"Would you like to create the datasets and snapshots nessacary to run the backup (only nessacary the first time)?" \
		"(if you have already created the backupDatasets and the snapshot per backupDataset you can skip this)"
	read -ep "[Y]es/[n]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y"  || "$resp" == "" ]]
	then
		if ! ${path}/createBackupDS.bash
		then
			printf "${RED}Error:${NC} failure in creation of the datasets -> abort"
			return 1
		fi
	fi
}

reminder(){
	printf "%s\n" \
		"Would you like to get a reminder for backing up? (requires anacron)"
	read -ep "[y]es/[N]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y" ]]
	then
		printf "Each how many days do you want to be reminded?\n"
		read -ep "days: " days 2>&1
		if [[ ! ( "$days" =~ [1-9][0-9]* ) ]]
		then
			printf "${RED}Error:${NC} days has to be an integer\n"
			return 1
		fi
		if [[ -f /etc/cron.daily/zfsBackupReminder ]]
		then
			printf "${RED}Error:${NC} '/etc/cron.daily/zfsBackupReminder' already exists\n"
			return 1
		fi
		cat > /etc/cron.daily/zfsBackupReminder << EOF
#!/bin/bash
notify-send() { # to be able to use notify-send from root
    #Detect the name of the display in use
    local display=":\$(ls /tmp/.X11-unix/* | sed 's#/tmp/.X11-unix/X##' | head -n 1)"

    #Detect the user using such display
	local user="\$(ps aux | grep '/usr/lib/Xorg' | head -n1 | awk -F ' ' '{print \$1}')"

    #Detect the id of the user
    local uid=\$(id -u \$user)

    sudo -u \$user DISPLAY=\$display DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$uid/bus notify-send "\$@"
}

lastBackupDone="\$(cat "${path}/backupDone.txt")"
now="\$(date +%s)"
daysAgo="\$(( (10#\$now - 10#\$lastBackupDone) / (60*60*24) ))"

printf "Last backup is \$daysAgo days ago\n"

if [[ "\$daysAgo" -ge "$days" ]]
then
    notify-send "Backups" "Please make a backup again"
fi
EOF
	fi
}

periodicSnaps(){
	printf "%s\n" \
		"Would you like to setup periodic snapshotting? (requires anacron)"
	read -ep "[y]es/[N]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y" ]]
	then
		if ! ${path}/snapshots.bash "${arraySets[@]}"
		then
			printf "${RED}Error:${NC} failure in setting up periodic snapshotting -> abort"
			return 1
		fi
	fi
}

init(){
	if [[ -f init ]]
	then # already initialized
		return
	fi

	if [[ ! -f ${path}/backup.cfg ]]
	then
		if ! collectWriteConfig
		then
			return 1
		fi
	fi

	if ! createBackupDS
	then
		printf "%s\n" \
			"Would you like to keep the config?"
		read -ep "[y]es/[N]o " resp 2>&1
		if [[ "$resp" == "n" || "$resp" == "N"  || "$resp" == "" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	if ! reminder
	then
		printf "%s\n" \
			"Would you like to keep the config?"
		read -ep "[Y]es/[n]o " resp 2>&1
		if [[ "$resp" == "n" || "$resp" == "N" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	if ! periodicSnaps
	then
		printf "%s\n" \
			"Would you like to keep the config?"
		read -ep "[Y]es/[n]o " resp 2>&1
		if [[ "$resp" == "n" || "$resp" == "N" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	printf "Initialisation finished, to rerun this assistant, delete ${path}/init\n"
	touch "${path}init"
	return 0
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

contains(){
	key=$1
	shift 1
	for ele in "$@"
	do
		if [[ "$ele" == "$key" ]]
		then
			return 0
		fi
	done
	return 1
}
###########################################FUNCTIONS-END############################################################

###########################################EXECUTE-SCRIPT##########################################################
execFunc(){
	stat=$(cat ${path}/stat.txt)
	if [[ ! ( "$stat" =~ ^[0-9]+$  && "$stat" -ge 0 && "$stat" -lt "${#backupDsNames[@]}" ) ]]
	then
		printf "${RED}Error:${NC}"
		printf "%s\n" \
			" no valid value for ${path}/stat.txt -> exit" \
			"       This shouldn't have happened if you didn't modify the file" #TODO @Gala hint für unerfahrene user hier?
		exit 1
	fi
	echo "$(( (stat + 1) % ${#backupDsNames[@]} ))" > ${path}/stat.txt
	bakSet="${backupDsNames[stat]}"
	
	echo -e "BackupDataSet is \"$bakSet\""
	read -ep "Press Enter to continue (ctrl+C to abort) " muell 2>&1
	
	# echo ${arraySets[*]%%/*} | tr " " "\n" | sort -u

	readarray -t requiredPools <<<$(printf "%s\n" "${arraySets[@]}" | awk -F"/" '{print $1}' | sort -u)
	requiredPools+=("${backupPool}")

	readarray -t zfsImported <<<$(zpool list | sed 's/  \+/\t/g' | awk -F $'\t' 'NR>1 {print $1}')

	#import
	printf "\n${BLUE}Import Devices${NC}\n"
	for pool in "${requiredPools[@]}"
	do
		# don't import pools that are already imported
		if contains "$pool" "${zfsImported[@]}"
		then
			continue
		fi

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
	do
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
	for pool in "${requiredPools[@]}"
	do
		# don't import pools that are already imported
		if contains "$pool" "${zfsImported[@]}"
		then
			continue
		fi

		if ! zpool import $pool
		then
			printf "${RED}Error:${NC} $pool couldn't been exported \n"
			exit 1
		else
			printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T")\n\n"
		fi
	done

	printf "\nAll Tasks are ${GREEN}successfully${NC} done at $(date "+%Y-%m-%d %T")\n"
	
	date +%s > ${path}/backupDone.txt #To remember when the last Backup took place (for the reminder to do Backups)
	###########################################EXECUTE-SCRIPT-END######################################################
	exit
}

# check if started with sudo
if [[ "$EUID" -ne 0 ]]
then
	printf "%s\n" "This script has to be run as root (sudo)"
	exit 1
fi

# note that init is not logged
if ! init
then
	exit 1
fi

path="$(readlink -f "${0%/*}")" # collect the path from how the script was called and canonicalize the path
#############################################LOAD-CONFIG##############################################################
# global variables with respect to configuration are stored in the backup.cfg file
if [[ -f ${path}/backup.cfg ]]
then
	source ${path}/backup.cfg
fi

if [[ ! (-v backupPool && -v poolSnapshot && -v arraySets) ]]
then
	printf "${RED}Error:${NC} "
	printf "%s\n" \
		"Global variables are missing, most probably some settings in the 'backup.cfg' are missing." \
		"       See the 'backup.cfg.def' for an example." \
		"       List of needed variables: backupPool, poolSnapshot, arraySets"
	exit 2
else
	echo "Everything set"
fi


mv "${path}/backup.log.0" "${path}/backup.log.1"
mv "${path}/backup.log" "${path}/backup.log.0"

execFunc | tee ${path}/backup.log
