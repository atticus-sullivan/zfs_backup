#!/bin/bash

shopt -s extglob

###########
## TODOs ##
###########
# - [ ] maybe: revise error handling -> like for NC with traps etc
# nice to have:
# - [ ] interactive config creation
# - [ ] check space -> lua
# - [ ] reminder stuff

#################
## CONVENTIONS ##
#################
# functions shall return 0 on success (e.g. -1 on error)
# functions are allowed to exit (0 on success) only if they are named main_
# functions shall never exit otherwise
# functions shall print error messages, but for general cleanup EXIT_STACK is to be used
# functions shall define in a comment above wether they print a "trailing emptyline" [NO YES IF_OUTPUT (errors not counted)]
# global variables are written in CAPS_LOCK
# names with _ instread of camelCase
# localization: variables begin with LANG_
# localization: variables ending with _FMT are format strings for printf and may/will take "arguments"

##################
## GLOBAL STUFF ##
##################
# get the directory of the script in a canonicalized way
DIR="$(dirname "$(readlink -f "${0}")")"
INTERACTIVE=true

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
# trailing emptyline: NO
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
# trailing emptyline: NO
help_fun()
{
  # -g                  guide -- interactive guide for generating the config
	cat >&2 <<EOF
Usage: $(basename "$0") [-i]

Create backup snapshot and send it to a backup pool.

  -i <INTERACTIVE>    be interactive (yes/true) or not (no/false) (default: yes)
  -n                  new -- create datasets+snapshots initially needed
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
# trailing emptyline: NO (no output)
# Parameters:
# $@: options to parse
# Sets the following global variables:
# - INTERACTIVE (if passed)
# Returns 0 if successful, 1 on help and other on error
parse_options(){
	local OPTION
	local OPTARG
	while getopts ':i:nh' OPTION ; do
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
			n)
				bak_ds_init
				return
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
# trailing emptyline: NO (no output)
config_user_read()
{
	# TODO prompt the user to write config file if is interactive
	# only reads the config from file if file is present
	if [[ -f "${DIR}/backup.cfg" ]]
	then
		source "${DIR}/backup.cfg"
	fi
}

# checks if all user config is ok
# trailing emptyline: NO (no output)
config_user_check()
{
	if [[ -z "${BACKUP_POOL}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_POOL" >&2
		return 1
	fi
	if [[ -z "${BACKUP_DS_NAMES}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "BACKUP_DS_NAMES" >&2
		return 2
	fi
	if [[ -z "${SNAPSHOT_NAME}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "SNAPSHOT_NAME" >&2
		return 3
	fi
	if [[ -z "${ARRAY_SET}" ]] ; then
		printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
		printf "${LANG_CONFIG_MISSING_FMT}\n" "ARRAY_SET" >&2
		return 4
	fi

	# check for source datasets
	for s in "${ARRAY_SET[@]}" ; do
		if ! check_zfs_avail "${s}" ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CONFIG_SET_UNAVAILABLE_FMT}\n" "${s}" >&2
			return 5
		fi
	done

	# check for dst datasets
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		if ! check_zfs_avail "${BACKUP_POOL}/${b}" ; then
			printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}" >&2
			return 6
		fi
		for s in "${ARRAY_SET[@]}" ; do
			s="${s#*/}" # remove pool from set path
			if ! check_zfs_avail "${BACKUP_POOL}/${b}/${s}" ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}" >&2
				return 6
			fi
		done
	done

	# check for dst dataset snapshots
	for b in "${BACKUP_DS_NAMES[@]}" ; do
		for s in "${ARRAY_SET[@]}" ; do
			s="${s#*/}" # remove pool from set path
			if ! check_zfs_avail "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}" ; then
				printf "${RED}%b${NC} " "${LANG_ERROR}" >&2
				printf "${LANG_CONFIG_BAKSET_UNAVAILABLE_FMT}\n" "${BACKUP_POOL}/${b}/${s}@${SNAPSHOT_NAME}" >&2
				return 7
			fi
		done
	done

	for s in "${ARRAY_SET[@]}" ; do
		if check_zfs_avail "${s}@${SNAPSHOT_NAME}" ; then
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
# trailing emptyline: YES
config_user_process()
{
	readarray -t IMPORT_POOLS < <(for s in "${ARRAY_SET[@]}" ; do
		if ! check_zfs_avail "${s%%/*}" ; then
			echo "${s%%/*}"
		fi
	done | sort -u)

	readarray -t ENCRYPTED_SETS < <(for s in "${ARRAY_SET[@]}" ; do
		local enc="$(zfs list -Ho name,encryption,keystatus "${s}" | cut -f 2)"
		local mnt="$(zfs list -Ho name,mounted "${s}" | cut -f 2)"
		if [[ "${enc}" != "off" && "${mnt}" != "yes" ]] ; then
			echo "${s}"
		fi
	done | sort -u)

	local stat=$(cat ${DIR}/stat.txt)
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
	echo

	return 0
}


######################
## FUNCTIONAL STUFF ##
######################

# import pools from IMPORT_POOLS and
# push them to EXIT_IMPORT if succsessful
# trailing emptyline: IF_OUTPUT
import()
{
	local out_line=false
	for p in "${IMPORT_POOLS[@]}" ; do
		out_line=true
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
	[[ "${out_line}" == true ]] && echo
	return 0
}

# mount/decrypt all sets from ENCRYPTED_SETS
# and push them to EXIT_ENC if succsessful
# trailing emptyline: IF_OUTPUT
decrypt()
{
	local out_line=false
	for p in "${ENCRYPTED_SETS[@]}" ; do
		out_line=true
		printf "${BLUE}%b${NC} %s: " "${LANG_DECRYPTING}" "${p}" >&2
		if zfs mount -l "${p}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
			# prepend for a stack like cleanup
			EXIT_ENC=("${p}" "${EXIT_ENC[@]}")
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DECRYPT_ERROR_FMT}\n" >&2
			return 1
		fi
	done
	[[ "${out_line}" == true ]] && echo
	return 0
}

# check a zfs item (ds or snapshot) for existance
# return 0 if it exists, 1 if it doesn't
# trailing emptyline: NO (no output)
check_zfs_avail()
{
	if zfs list -H "${1}" &> /dev/null ; then
		# exists
		return 0
	else
		# missing
		return 1
	fi
}

# create necessary data-sets and snapshots for running this script
# trailing emptyline: IF_OUTPUT
bak_ds_init()
{
	local out_line=false
	for bak in "${BACKUP_DS_NAMES[@]}" ; do
		for ds in "${ARRAY_SET[@]}" ; do
			if !check_zfs_avail "${BACKUP_POOL}/${bak}/${ds}" ; then
				# DS does not exist
				printf "${BLUE}%b${NC} %s: " "${LANG_CREATING}" "${BACKUP_POOL}/${bak}/${ds}" >&2
				out_line=true
				if ! zfs create "${BACKUP_POOL}/${bak}/${ds}" ; then
					return -1
				fi
			fi
			if !check_zfs_avail "${BACKUP_POOL}/${bak}/${ds}@${SNAPSHOT_NAME}" ; then
				# snapshot does not exist
				printf "${BLUE}%b${NC} %s: " "${LANG_CREATING}" "${BACKUP_POOL}/${bak}/${ds}@${SNAPSHOT_NAME}" >&2
				out_line=true
				if ! zfs create "${BACKUP_POOL}/${bak}/${ds}@${SNAPSHOT_NAME}" ; then
					return -1
				fi
			fi
		done
	done
	[[ "${out_line}" == true ]] && echo
}

# TODO implement check_space
check_space()
{
	return 0
}

# destroy dst snapshots on the backup pool
# trailing emptyline: IF_OUTPUT
destroy_dst()
{
	local out_line=false
	for s in "${ARRAY_SET[@]}"
	do
		s="${s#*/}" # remove pool from set path
		out_line=true
		printf "${BLUE}%b${NC} %s: " "${LANG_DESTROYING}" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" >&2
		if zfs destroy "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${BACKUP_POOL}/${BAK_SET}/${s}@${SNAPSHOT_NAME}" >&2
			return 1
		fi
	done
	[[ "${out_line}" == true ]] && echo
	return 0
}

# create src snapshots
# trailing emptyline: IF_OUTPUT
create_src()
{
	local out_line=false
	for s in "${ARRAY_SET[@]}"
	do
		out_line=true
		printf "${BLUE}%b${NC} %s: " "${LANG_CREATING}" "${s}@${SNAPSHOT_NAME}" >&2
		if zfs snapshot "${s}@${SNAPSHOT_NAME}" ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_CREATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" >&2
			return 1
		fi
	done
	[[ "${out_line}" == true ]] && echo
	return 0
}

# trailing emptyline: NO
print_send_verbose()
{
	local out_line=false
	while read line ; do
		# clear line and go to column 0
		echo -ne "\033[2K\r"
		if [[ "$line" == [0-9][0-9]:[0-9][0-9]:[0-9][0-9]+([[:space:]])+([0-9])?(.)*([0-9])[KMGT]+([[:space:]])* ]] ; then
			# status line given
			# print line but don't terminate with \n to make overwriting possible
			echo -n "$line"
			out_line=true
		else
			# some other line given (header, warning or error)
			# print line with \n to avoid overwriting
			echo "$line"
			out_line=false
		fi
	done
	# only print \n for not completely terminated line of "echo -n"
	[[ "${out_line}" == true ]] && echo
}


# returns the first non-zero exit code contained in PIPESTATUS
# trailing emptyline: NO (no output)
check_pipestatus(){
	if [[ -n "${PIPESTATUS+x}" ]] ; then
		for e_code in "${PIPESTATUS[@]}" ; do
			if [[ "$e_code" != 0 ]] ; then
				break
			fi
		done
		return $e_code
	fi
	# PIPESTATUS is always present except if no command was executed until now
	return 0
}

# $1 source
# $2 destination
send_rcv(){
	zfs send -v "${1}" | zfs recv "${2}" -F
	check_pipestatus
}

# send snapshots to BACKUP_POOL
# trailing emptyline: IF_OUTPUT
replicate()
{
	# 16:31:36    199M   data/daten/downloads@replication
	local out_line=false
	for s in "${ARRAY_SET[@]}"
	do
		# echo "runs until BACKUP_POOL is at 'zfs program s.pool xyz.lua + zfs program BACKUP_POOL xyz_.lua'" # TODO
		out_line=true
		printf "${BLUE}%b${NC} %s -> %s (%s)\n" "${LANG_REPLICATING}" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}" "$(date "+%Y-%m-%d %T")" >&2
		( send_rcv "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}" ) 3>&1 1>&2- 2>&3- | print_send_verbose
		check_pipestatus
		if [[ $? -eq 0 ]]
		then
			printf "\n${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_REPLICATE_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" "${BACKUP_POOL}/${BAK_SET}/${s#*/}" >&2
			return 1
		fi
	done
	[[ "${out_line}" == true ]] && echo
	return 0
}

# destroy the snapshot what was just being sent
# trailing emptyline: IF_OUTPUT
destroy_src()
{
	local out_line=false
	#Destroy source Snapshot
	for s in "${ARRAY_SET[@]}"
	do
		out_line=true
		printf "${BLUE}%b${NC} %s: " "${LANG_DESTROYING}" "${s}@${SNAPSHOT_NAME}" >&2
		if zfs destroy "${s}@${SNAPSHOT_NAME}" > /dev/null ; then
			printf "${GREEN}%b${NC}\n" "${LANG_SUCCESS}" >&2
		else
			printf "\n${RED}%b${NC} " "${LANG_ERROR}" >&2
			printf "${LANG_DESTROY_ERROR_FMT}\n" "${s}@${SNAPSHOT_NAME}" >&2
			return 1
		fi
	done
	[[ "${out_line}" == true ]] && echo
	return 0
}

main_replicate()
{
	if ! config_user_read ; then
		exit_stack
		exit -2
	fi

	if ! config_user_process ; then
		exit_stack
		exit -5
	fi

	if ! import ; then
		exit_stack
		exit -3
	fi

	if ! config_user_check ; then
		exit_stack
		exit -4
	fi

	if ! decrypt ; then
		exit_stack
		exit -6
	fi

	if ! check_space ; then
		exit_stack
		exit -7
	fi

	if ! destroy_dst ; then
		exit_stack
		exit -8
	fi

	if ! create_src ; then
		exit_stack
		exit -9
	fi

	if ! replicate ; then
		exit_stack
		exit -10
	fi

	if ! destroy_src ; then
		exit_stack
		exit -10
	fi

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
parse_options "$@" || exit $?

mv "${DIR}/backup.log.0" "${DIR}/backup.log.1"
mv "${DIR}/backup.log" "${DIR}/backup.log.0"

main_replicate 2>&1 | tee ${DIR}/backup.log
