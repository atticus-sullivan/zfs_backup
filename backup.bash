#!/bin/bash

###########
## TODOs ##
###########
# - [-] use an extra layer to wrap zfs commands => e.g zfs_destroy or
#         zfs_/zpool_exists for better reuse and less code-duplication
# - [-] interactive stuff (by default this should be interactive, but provide a switch to make "scriptable")
# - [-] interactive config creation
# - [-] help function
# - [-] check space
# - [-] write EXIT_ENC and EXIT_IMPORT to file/read from file so that the user can change what is exported/encrypted at the end if necessary
# - [ ] reminder stuff
# - [ ] init function to create datasets and snapshots the first time (print warnings if already exists) to get a consistant state to run this script on

#################
## CONVENTIONS ##
#################
# functions shall return 0 on success (e.g. -1 on error)
# functions are allowed to exit (0 on success) only if they are named main_
# functions shall never exit otherwise
# functions shall print error messages, but for general cleanup EXIT_STACK is to be used
# global variables are written in CAPS_LOCK
# names with _ instread of camelCase
# localization: variables begin with LANG_
# localization: variables ending with _FMT are format strings for printf and may/will take "arguments"

##################
## GLOBAL STUFF ##
##################
# get the directory of the script in a canonicalized way
DIR="$(readlink -f "${0%/*}")"

# COLORS
GREEN='\033[0;32m' # success
RED='\033[0;31m'   # erorrs
WARN='\033[0;33m'  # warnings
BLUE='\033[0;44m'  # information (what's happening)
BOLD='\033[1m'     # bold font
NC='\033[0;0m'     # formatting reset

##################
## LOCALIZATION ##
##################
# use
# grep -No LANG_.[^}]* backup.bash | sort -u
# to find all variables shich have to be provided
# Hint: You can use "source" and ${DIR} in that file as well to use another
#       language as default
source "${DIR}/resource/lang.en"

################
## EXIT STUFF ##
################
# cleans up according to the EXIT_STACK (make one EXIT_STACK per operation)
# makes use of global variables indicating clean-up
# currently these are
# EXIT_IMPORT and EXIT_ENC
# Cleanup works by first processing EXIT_ENC and then processing EXIT_IMPORT
EXIT_ENC=()
EXIT_IMPORT=()
exit_stack()
{
	local ret=0
	if [[ "${1}" != "normal" ]] ; then
		printf "${WARN}%b${NC} %b\n" "${LANG_WARNING}" ${LANG_EXIT_WARNING}
	fi

	# no matter what error, we at least try to cleanup the rest of the stack

	for s in "${EXIT_ENC[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_ENCRYPTING}" "${s}"
		if zfs unmount "${s}" && zfs unload-key "${s}" ; then
		else
			printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" ${LANG_ENCRYPT_ERROR}
			ret=-1
		fi
	done

	for p in "${EXIT_IMPORT[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_EXPORTING}" "${s}"
		if zpool export "${s}" ; then
		else
			printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" ${LANG_EXPORT_ERROR}
			ret=-1
		fi
	done
	return "${ret}"
}

##########
## HELP ##
##########
# TODO implement help_fun
help_fun()
{
	return 0
}

##################
## CONFIG STUFF ##
##################

# sets up gloabl user config variables
# currently these are
# BACKUP_POOL, BACKUP_DS_NAMES, SNAPSHOT_NAME and ARRAY_SET
config_user_read()
{
	# TODO prompt the user to write config file if is interactive
	# only reads the config from file if file is present
	if [[ -f ${DIR}/backup.cfg ]]
	then
		source ${DIR}/backup.cfg
	fi
}

# checks if all user config is ok
config_user_check()
{
	if [[ -n "${BACKUP_POOL}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}"
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_POOL"
		return 1
	fi
	if [[ -n "${BACKUP_DS_NAMES}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}"
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_DS_NAMES"
		return 2
	fi
	if [[ -n "${SNAPSHOT_NAME}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}"
		printf "${LANG_CONFIG_MISSING_FMT}\n" "SNAPSHOT_NAME"
		return 3
	fi
	if [[ -n "${ARRAY_SET}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}"
		printf "${LANG_CONFIG_MISSING_FMT}\n" "ARRAY_SET"
		return 4
	fi

	# check for source datasets
	for s in "${ARRAY_SET[@]}" ; do
		if ! zfs list -H "${s}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_CONFIG_SET_UNAVAILABLE_FMT}\n" "${s}"
			return 5
		fi
	done

	# check for dst datasets
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		if ! zfs list -H "${BACKUP_POOL}/${b}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}"
			return 6
		fi
		for s in "${ARRAY_SET[@]}" ; do
			s="${#*/}" # remove pool from set path
			if ! zfs list -H "${BACKUP_POOL}/${b}/${s}" > /dev/null ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}"
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}"
				return 6
			fi
		done
	done

	# check for dst dataset snapshots
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		for s in "${ARRAY_SET[@]}" ; do
			s="${#*/}" # remove pool from set path
			if ! zfs list -H "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}" > /dev/null ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}"
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}"
				return 7
			fi
		done
	done

	for s in "${ARRAY_SET[@]}" ; do
		if zfs list -H "${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_CONFIG_SNAPSHOT_EXISTS_FMT}\n" "${s}@${SNAPSHOT_NAME}"
			return 8
		fi
	done

	return 0
}

# sets up global "config" variables that are derived from the user provided config
# currently these are
# BAK_SET, IMPORT_POOLS and ENCRYPTED_SETS
config_user_process()
{
	readarray -t IMPORT_POOLS < <(for s in "${ARRAY_SET[@]}" ; do
		echo "${s%%/*}"
	done | sort -u)

	readarray -t ENCRYPTED_SETS < <(for s in "${ARRAY_SET[@]}" ; do
		local enc="$(zfs list -Ho name,encryption,keystatus "${s}" | cut -f 2)"
		if [[ "${enc}" != "off" ]] ; then
			echo "${s}"
		fi
	done | sort -u)

	local stat=$(cat ${DIR}/stat.txt)
	echo "${stat}"
	if [[ ! ( "${stat}" =~ ^[0-9]+$  && "${stat}" -ge 0 && "${stat}" -lt "${#BACKUP_DS_NAMES[@]}" ) ]]
	then
		printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" "${LANG_STAT_FAIL}"
		return 1
	fi
	echo "$(( (stat + 1) % ${#BACKUP_DS_NAMES[@]} ))" > ${DIR}/stat.txt
	BAK_SET="${BACKUP_DS_NAMES[stat]}"

	printf "${LANG_BACKUP_SET_FMT}" "${BAK_SET}"
	read -ep "${LANG_CONFIRM}" muell 2>&1 # TODO interactive

	return 0
}


######################
## FUNCTIONAL STUFF ##
######################

# import pools from IMPORT_POOLS and
# push them to EXIT_IMPORT if succsessful
import()
{
	for p in "${IMPORT_POOLS[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_IMPORTING}" "${p}"
		if zpool import "${p}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
			# prepend for a stack like cleanup
			EXIT_IMPORT=("${p}" "${EXIT_IMPORT[@]}")
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_IMPORT_ERROR_FMT}\n" "${p}"
			return 1
		fi
	done
	return 0
}

# mount/decrypt all sets from ENCRYPTED_SETS
# and push them to EXIT_ENC if succsessful
decrypt()
{
	for p in "${ENCRYPTED_SETS[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_DECRYPTING}" "${p}"
		if zpool mount -l "${p}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
			# prepend for a stack like cleanup
			EXIT_ENC=("${p}" "${EXIT_ENC[@]}")
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_DECRYPT_ERROR_FMT}\n"
			return 1
		fi
	done
	return 0
}

# TODO implement check_space
check_space()
{
	return 0
}

# destroy dst snapshots on the backup pool
destroy_dst()
{
	for s in "${ARRAY_SET[@]}"
	do
		s="${#*/}" # remove pool from set path
		printf "${BLUE}%b${NC} %s:" "${LANG_DESTROYING}" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}"
		if zfs destroy "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}"
			return 1
		fi
	done
	return 0
}

# create src snapshots
create_src()
{
	for s in "${ARRAY_SET[@]}"
	do
		printf "${BLUE}%b${NC} %s:" "${LANG_CREATING}" "${s}"
		if zfs snapshot "${s}@${SNAPSHOT_NAME}" ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_CREATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}"
			return 1
		fi
	done
	return 0
}

# send snapshots to BACKUP_POOL
replicate()
{
	for s in "${ARRAY_SET[@]}"
	do
		echo "runs until BACKUP_POOL is at 'zfs program s.pool xyz.lua + zfs program BACKUP_POOL xyz_.lua'" # TODO

		printf "${BLUE}%b${NC} %s -> %s:" "${LANG_REPLICATING}" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}"
		if zfs send "${s}@${SNAPSHOT_NAME}" | zfs recv "${BACKUP_POOL}/${BAK_SET}/${s#*/}" -F
		then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_REPLICATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}"
			return 1
		fi
	done
	return 0
}

# destroy the snapshot what was just being sent
destroy_src()
{
	#Destroy source Snapshot
	for s in "${ARRAY_SET[@]}"
	do
		printf "${BLUE}%b${NC} %s:" "${LANG_DESTROYING}" "${s}@${SNAPSHOT_NAME}"
		if zfs destroy "${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}"
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}"
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}"
			return 1
		fi
	done
	return 0
}

main_replicate()
{
	if ! config_user_read ; then
		exit_stack
		exit -2
	fi
	echo

	if ! import ; then
		exit_stack
		exit -3
	fi
	echo

	if ! config_user_check ; then
		exit_stack
		exit -4
	fi
	echo
	if ! config_user_process ; then
		exit_stack
		exit -5
	fi
	echo

	if ! decrypt ; then
		exit_stack
		exit -6
	fi
	echo

	if ! check_space ; then
		exit_stack
		exit -7
	fi
	echo

	if ! destroy_dst ; then
		exit_stack
		exit -8
	fi
	echo

	if ! create ; then
		exit_stack
		exit -9
	fi
	echo

	if ! replicate ; then
		exit_stack
		exit -10
	fi
	echo

	if ! destroy_src ; then
		exit_stack
		exit -10
	fi
	echo

	if exit_stack "normal" ; then
		printf "${GREEN}${LANG_DONE_SUCC_FMT}${NC}" "$(date "+%Y-%m-%d %T")"
		exit 0
	else
		printf "${RED}${LANG_DONE_ERROR_FMT}${NC}" "$(date "+%Y-%m-%d %T")"
		exit -1
	fi
	# UNREACHABLE
}

# check if started with sudo
if [[ "${EUID}" -ne 0 ]]
then
	printf "%b\n" "${LANG_ROOT_ERROR}"
	exit 1
fi

mv "${DIR}/backup.log.0" "${DIR}/backup.log.1"
mv "${DIR}/backup.log" "${DIR}/backup.log.0"

main_replicate | tee ${DIR}/backup.log
