#!/bin/bash
#Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;44m'
NC='\033[0;0m'

##########################################LANGUAGE####################################################################
source /home/lukas/coding/zfs-bash/resource/lang.en
##########################################LANGUAGE####################################################################

###########################################FUNCTIONS-START############################################################

myExit(){
  read -ep "${continue}" -r muell 2>&1

  echo -e "\n ${exporting_anyway}"
  if ! zpool export "$backupPool"
  then
    printf " ${RED}${error}${NC} ${exporting_failure} \n" "backup" # TODO exoort all exportable not only the backuopool
  else
    printf " ${GREEN}${success}${NC} \n"
  fi
  exit
}

checkConfig(){
	printf "%s\n" \
		"${check_config[@]}"
	read -ep "${Yes_no} " resp 2>&1
	if [[ "$resp" == "${yes[upper]}" || "$resp" == "${yes[lower]}"  || "$resp" == "" ]]
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
				printf "${RED}${error}${NC} ${importing} $pool\n"
				return 1
			fi
		done

		for ds in arraySets
		do
			if ! zfs list "$ds" &>/dev/null
			then
				printf "${RED}${error}${NC} ${dataset_not_found}\n" "$ds"
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
				printf "${RED}${error}${NC} ${exporting_failure}\n" "$pool"
				return 1
			fi
		done
	fi
}

collectWriteConfig(){
	printf "${init_intro}\n"
	read -ep "${Yes_no} " resp 2>&1
	if [[ "$resp" == "${yes[lower]}" || "$resp" == "${yes[upper]}" || "$resp" == "" ]]
	then
		backupPool=""
		printf "\n"
		# TODO @Gala check ob pool existiert? Evtl nicht möglich, da nicht eingesteckt...
		read -ep "${init_backupPool}" backupPool 2>&1
		printf "\n"

		printf "%s\n" \
			"${init_backupDS[@]}"
		backupDsNames=()
		ds="x"
		while [[ "$ds" != "" ]]
		do
			read -ep "${init_backupDS_inter}" ds 2>&1
			[[ "$ds" == "" ]] && continue
			backupDsNames+=("$ds")
		done
		printf "${init_backupDS_confirm}"
		declare -p backupDsNames
		read -ep "${confirm}" muell 2>&1
		printf "\n"

		poolSnapshot=""
		read -ep "${init_replName}" poolSnapshot 2>&1 # TODO @Gala "replication" als default?
		printf "\n"

		printf "%s\n" \
			"${init_srcDS[@]}"
		arraySets=()
		ds="x"
		while [[ "$ds" != "" ]]
		do
			read -ep "${init_srcDS_inter}" ds 2>&1
			[[ "$ds" == "" ]] && continue
			arraySets+=("$ds")
		done
		printf "${init_srcDS_confirm}"
		declare -p arraySets
		read -ep "${confirm}" muell 2>&1
		printf "\n"

		if ! checkConfig
		then
			return 1
		fi

		# Attention do not translate these strings!!!
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
		"${init_createBacks[@]}"
	read -ep "${Yes_no}" resp 2>&1
	if [[ "$resp" == "${yes[lower]}" || "$resp" == "${yes[upper]}"  || "$resp" == "" ]]
	then
		if ! ${path}/createBackupDS.bash
		then
			printf "${RED}${error}${NC} ${init_createBacks_fail}\n"
			return 1
		fi
	fi
}

reminder(){
	printf "%s\n" "${init_back_rem}"
	read -ep "${yes_No}" resp 2>&1
	if [[ "$resp" == "${yes[lower]}" || "$resp" == "${yes[upper]}" ]]
	then
		printf "${init_back_rem_days_intro}\n"
		read -ep "${init_back_rem_days}" days 2>&1
		if [[ ! ( "$days" =~ [1-9][0-9]* ) ]]
		then
			printf "${RED}${error}${NC} ${init_bacl_rem_days_fail}\n"
			return 1
		fi
		if [[ -f /etc/cron.daily/zfsBackupReminder ]]
		then
			printf "${RED}${error}${NC} '/etc/cron.daily/zfsBackupReminder' ${fail_exists}\n"
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
	printf "%s\n" "${init_period_intro}"
	read -ep "${yes_No}" resp 2>&1
	if [[ "$resp" == "${yes[lower]}" || "$resp" == "${yes[upper]}" ]]
	then
		if ! ${path}/snapshots.bash "${arraySets[@]}"
		then
			printf "${RED}${error}${NC} ${init_period_fail}"
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
		printf "%s\n" "${init_keep}"
		read -ep "${yes_No}" resp 2>&1
		if [[ "$resp" == "${no[lower]}" || "$resp" == "${no[upper]}"  || "$resp" == "" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	if ! reminder
	then
		printf "%s\n" "${init_keep}"
		read -ep "${Yes_no}" resp 2>&1
		if [[ "$resp" == "${no[lower]}" || "$resp" == "${no[upper]}" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	if ! periodicSnaps
	then
		printf "%s\n" "${init_keep}"
		read -ep "${Yes_no}" resp 2>&1
		if [[ "$resp" == "${no[lower]}" || "$resp" == "${no[upper]}" ]]
		then
			rm ${path}/backup.cfg
		fi
		return 1
	fi

	printf "${init_fin}\n" "${path}/init"
	touch "${path}init"
	return 0
}

destroySnap(){
  if ! zfs destroy "$1"
  then
    printf "${RED}${error}${NC} ${destroy_fail}\n" "$1"
    myExit
  else
    printf "${GREEN}${done}${NC} ${destroy_succ}\n" "$(date "+%Y-%m-%d %T")" "$1"
  fi
}

createSnap(){
  if ! zfs snapshot "$1"
  then
    printf "${RED}${error}${NC} ${create_fail}\n" "$1"
    myExit
  else
    printf "${GREEN}${done}${NC} ${create_succ}\n" "$(date "+%Y-%m-%d %T")" "$1"
  fi
}

replicateSnap(){
	printf "${repl_intro}\n" "$1" "$2"

	if ! zfs send "$1" | zfs recv "$2" -F
	then
		printf "${RED}${error}${NC} ${repl_fail}" "$1"
		myExit
	else
		printf "${GREEN}${done}${NC} ${repl_succ}\n\n" "$(date "+%Y-%m-%d %T")" "$1" "$2"
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
		printf "${RED}${error}${NC}"
		printf "%s\n" "${main_stat_fail[@]}"
		exit 1
	fi
	echo "$(( (stat + 1) % ${#backupDsNames[@]} ))" > ${path}/stat.txt
	bakSet="${backupDsNames[stat]}"

	printf "$main_backupset" "$bakSet"
	read -ep "$confirm" muell 2>&1
	
	# echo ${arraySets[*]%%/*} | tr " " "\n" | sort -u

	readarray -t requiredPools <<<$(printf "%s\n" "${arraySets[@]}" | awk -F"/" '{print $1}' | sort -u)
	requiredPools+=("${backupPool}")

	readarray -t zfsImported <<<$(zpool list | sed 's/  \+/\t/g' | awk -F $'\t' 'NR>1 {print $1}')

	#import
	printf "\n${BLUE}${main_import}${NC}\n"
	for pool in "${requiredPools[@]}"
	do
		# don't import pools that are already imported
		if contains "$pool" "${zfsImported[@]}"
		then
			continue
		fi

		if ! zpool import $pool
		then
			printf "${RED}${error}${NC} ${main_import_fail}\n" "$pool"
			exit
		else
			printf "${GREEN}${done}${NC} ${main_import_succ}\n\n" "$(date "+%Y-%m-%d %T")"
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
		# TODO localize this one
	  printf "${RED}Error:${NC} Too much data to backup, the targetPool($backupPool) is too full ($backupPool has $(( 10#${freeSpaceOnBackup} / 10#${divisionForGb} )),$(((10#${freeSpaceOnBackup}%10#${divisionForGb})*10/10#${divisionForGb} )) GB (exactly ${freeSpaceOnBackup} bytes) left but there is $(( 10#${needed} / 10#${divisionForGb} )),$(((10#${needed}%10#${divisionForGb})*10/10#${divisionForGb} )) GB (exactly ${needed} bytes) to be backedUp) -> exit\n"
	  myExit
	else
		# TODO localize this one
	  printf "${GREEN}Successful:${NC} Enough place on BackupPool ($backupPool has $(( 10#${freeSpaceOnBackup} / 10#${divisionForGb} )),$(((10#${freeSpaceOnBackup}%10#${divisionForGb})*10/10#${divisionForGb} )) GB ($freeSpaceOnBackup Bytes) left, there is $(( 10#${needed} / 10#${divisionForGb} )),$(((10#${needed}%10#${divisionForGb})*10/10#${divisionForGb} )) GB ($needed Bytes) to be backedUp)   \n"
	fi
	
	#Destroy Old Backup Snapshot 
	printf "\n${BLUE}${main_destroy}${NC}\n"
	
	for processing in "${arraySets[@]}"
	do
	  destroySnap "${backupPool}/${bakSet}/${processing#*/}@${poolSnapshot}"
	done
	
	#create snapshot
	printf "\n${BLUE}${main_create}${NC}\n"
	for processing in "${arraySets[@]}"
	do
	  createSnap "${processing}@${poolSnapshot}"
	done
	
	#Replication
	printf "\n${BLUE}${main_repl}${NC}\n"
	for processing in "${arraySets[@]}"
	do
	  echo -e "\n\n"
	  zpool iostat
	  replicateSnap "${processing}@${poolSnapshot}" "${backupPool}/${bakSet}/${processing#*/}"
	done
	
	#Destroy source Snapshot
	printf "${BLUE}${main_destroySrc}${NC}\n" "${backupPool}/${bakSet}@${poolSnapshot}"
	for processing in "${arraySets[@]}"
	do
	  destroySnap "${processing}@${poolSnapshot}"
	done
	
	#export
	printf "\n${BLUE}${main_export}${NC}\n"
	for pool in "${requiredPools[@]}"
	do
		# don't import pools that are already imported
		if contains "$pool" "${zfsImported[@]}"
		then
			continue
		fi

		if ! zpool import $pool
		then
			printf "${RED}${error}${NC} ${main_export_fail}\n" "$pool"
			exit 1
		else
			printf "${GREEN}${done}${NC} ${main_export_fail}\n\n" "$pool" "$(date "+%Y-%m-%d %T")"
		fi
	done

	printf "\n${main_succ}\n" "$(date "+%Y-%m-%d %T")"
	
	date +%s > ${path}/backupDone.txt #To remember when the last Backup took place (for the reminder to do Backups)
	###########################################EXECUTE-SCRIPT-END######################################################
	exit
}

# check if started with sudo
if [[ "$EUID" -ne 0 ]]
then
	printf "%s\n" "${root_fail}"
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
	printf "${RED}${error}${NC} "
	printf "%s\n" \
		${glob_fail[@]}
	exit 2
else
	printf "${glob_set}\n"
fi


mv "${path}/backup.log.0" "${path}/backup.log.1"
mv "${path}/backup.log" "${path}/backup.log.0"

execFunc | tee ${path}/backup.log
