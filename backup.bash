#!/bin/bash

###########
## TODOs ##
###########
# nice to have:
# - [ ] interactive config creation
# - [ ] init function to create datasets and snapshots the first time (print
# warnings if already exists) to get a consistent state to run this script on
# - [ ] check space -> lua
# - [ ] reminder stuff

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
DIR="$(dirname "$(readlink -f "${0}")")"
INTERACTIVE=false

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
		printf "${WARN}%b${NC} %b\n" "${LANG_WARNING}" "${LANG_EXIT_WARNING}" >&2
	fi

	# no matter what error, we at least try to cleanup the rest of the stack

	for s in "${EXIT_ENC[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_ENCRYPTING}" "${s}" >&2
		if zfs unmount "${s}" && zfs unload-key "${s}" ; then
			:
		else
			printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" "${LANG_ENCRYPT_ERROR}" >&2
			ret=-1
		fi
	done

	for p in "${EXIT_IMPORT[@]}" ; do
		printf "${BLUE}%b${NC} %s:" "${LANG_EXPORTING}" "${s}" >&2
		if zpool export "${s}" ; then
			:
		else
			printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" "${LANG_EXPORT_ERROR}" >&2
			ret=-1
		fi
	done
	return "${ret}"
}

##########
## HELP ##
##########
help_fun()
{
	cat >&2 <<EOF
Usage: $(basename "$0") [-i]

Create backup snapshot and send it to a backup pool.

  -i <INTERACTIVE>    be interactive (yes/true) or not (no/false) (default: yes)
  -h                  show this help

Config:
The config will be read from the backup.cfg placed alongside this script (currently
"${DIR}"). It has to be readable via 'source' by the bash and contain the
following variables:

- ARRAY_SET:          names of the datasets to be backed up. This script will
                      auto-detect which of those datasets is encrypted
                      (array of strings)

- BACKUP_POOL:        name of the pool to send the backup snapshot to
                      (simple string)

- SNAPSHOT_NAME:      name of the snapshot used for the backup (which is being
                      sent to BACKUP_POOL)

- BACKUP_DS_NAMES:    usually you want to have not only one backup but keep e.g.
                      the last backup as well. Set here the names of the
                      datasets holding the actual backups (e.g. bak1, bak2).
                      This script will rotate on which dataset to place the
                      backup on.

EOF
	return 0
}

###################
## PARSE_OPTIONS ##
###################
# Parameters:
# $@: options to parse
# Sets the following global variables:
# - INTERACTIVE (if passed)
# Returns 0 if successful, 1 on help and other on error
parse_options(){
	local OPTION
	local OPTARG
	while getopts ':i:h' OPTION ; do
		case "${OPTION}" in
			i)
				if [[ "${OPTARG,,}" == "yes" || "${OPTARG,,}" == "true" ]] ; then
					INTERACTIVE=true
				elif [[ "${OPTARG,,}" == "no" || "${OPTARG,,}" == "false" ]] ; then
					INTERACTIVE=false
				else
					echo "'-i' has to be either yes/true or no/false" >&2
					return -1
				fi
				;;
			h)
				help_fun
				return 1
				;;
			:)
				echo "Error: -${OPTARG} expects an argument" >&2
				return -1
				;;
			?)
				echo "Error: Unknown argument passed: ${OPTARG}" >&2
				;;
		esac
	done
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
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_POOL" >&2
		return 1
	fi
	if [[ -n "${BACKUP_DS_NAMES}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_DS_NAMES" >&2
		return 2
	fi
	if [[ -n "${SNAPSHOT_NAME}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "SNAPSHOT_NAME" >&2
		return 3
	fi
	if [[ -n "${ARRAY_SET}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "ARRAY_SET" >&2
		return 4
	fi

	# check for source datasets
	for s in "${ARRAY_SET[@]}" ; do
		if ! zfs list -H "${s}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CONFIG_SET_UNAVAILABLE_FMT}\n" "${s}" >&2
			return 5
		fi
	done

	# check for dst datasets
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		if ! zfs list -H "${BACKUP_POOL}/${b}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}" >&2
			return 6
		fi
		for s in "${ARRAY_SET[@]}" ; do
			s="${#*/}" # remove pool from set path
			if ! zfs list -H "${BACKUP_POOL}/${b}/${s}" > /dev/null ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}" >&2
				return 6
			fi
		done
	done

	# check for dst dataset snapshots
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		for s in "${ARRAY_SET[@]}" ; do
			s="${#*/}" # remove pool from set path
			if ! zfs list -H "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}" > /dev/null ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}" >&2
				return 7
			fi
		done
	done

	for s in "${ARRAY_SET[@]}" ; do
		if zfs list -H "${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CONFIG_SNAPSHOT_EXISTS_FMT}\n" "${s}@${SNAPSHOT_NAME}" >&2
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
		printf "${RED}%b${NC} %b\n" "${LANG_ERROR}" "${LANG_STAT_FAIL}" >&2
		return 1
	fi
	echo "$(( (stat + 1) % ${#BACKUP_DS_NAMES[@]} ))" > ${DIR}/stat.txt
	BAK_SET="${BACKUP_DS_NAMES[stat]}"

	printf "${LANG_BACKUP_SET_FMT}" "${BAK_SET}" >&2
	if [[ "${INTERACTIVE}" == true ]] ; then
		read -ep "${LANG_CONFIRM}" resp 2>&1
	fi

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
		printf "${BLUE}%b${NC} %s:" "${LANG_IMPORTING}" "${p}" >&2
		if zpool import "${p}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
			# prepend for a stack like cleanup
			EXIT_IMPORT=("${p}" "${EXIT_IMPORT[@]}")
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_IMPORT_ERROR_FMT}\n" "${p}" >&2
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
		printf "${BLUE}%b${NC} %s:" "${LANG_DECRYPTING}" "${p}" >&2
		if zpool mount -l "${p}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
			# prepend for a stack like cleanup
			EXIT_ENC=("${p}" "${EXIT_ENC[@]}")
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DECRYPT_ERROR_FMT}\n" >&2
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
		printf "${BLUE}%b${NC} %s:" "${LANG_DESTROYING}" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" >&2
		if zfs destroy "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" >&2
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
		printf "${BLUE}%b${NC} %s:" "${LANG_CREATING}" "${s}" >&2
		if zfs snapshot "${s}@${SNAPSHOT_NAME}" ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CREATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" >&2
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
		# echo "runs until BACKUP_POOL is at 'zfs program s.pool xyz.lua + zfs program BACKUP_POOL xyz_.lua'" # TODO

		printf "${BLUE}%b${NC} %s -> %s:" "${LANG_REPLICATING}" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}" >&2
		if zfs send "${s}@${SNAPSHOT_NAME}" | zfs recv "${BACKUP_POOL}/${BAK_SET}/${s#*/}" -F
		then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_REPLICATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}" >&2
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
		printf "${BLUE}%b${NC} %s:" "${LANG_DESTROYING}" "${s}@${SNAPSHOT_NAME}" >&2
		if zfs destroy "${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" >&2
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
		printf "${GREEN}${LANG_DONE_SUCC_FMT}${NC}" "$(date "+%Y-%m-%d %T")" >&2
		exit 0
	else
		printf "${RED}${LANG_DONE_ERROR_FMT}${NC}" "$(date "+%Y-%m-%d %T")" >&2
		exit -1
	fi
	# UNREACHABLE
}

# check if started with sudo
if [[ "${EUID}" -ne 0 ]]
then
	printf "%b\n" "${LANG_ROOT_ERROR}" >&2
	exit 1
fi

# parse passed options
parse_options "$@"

mv "${DIR}/backup.log.0" "${DIR}/backup.log.1"
mv "${DIR}/backup.log" "${DIR}/backup.log.0"

main_replicate 2>&1 | tee ${DIR}/backup.log
