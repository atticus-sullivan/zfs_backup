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
fi

myExit(){
	printf "Task ${REED}failed${NC}!\nTrying to export the backup-pool anyway.\n"
	zpool export backup && printf "Exporting ${GREEN}successful${NC} " || printf "Exporting ${RED}failed${NC} "
	printf "-> exit"
	exit
}

check if started with sudo
if [[ "$EUID" -ne 0 ]]
then
	printf "%s\n" "This script has to be run as root (sudo)"
	exit 1
fi

printf "${BLUE}Importing the backup-pool${NC}\n"
if ! zpool import backup
then
	printf "${RED}Error${NC} while trying to import the backup-pool!\nMake sure the device with the pool on it is connected and that this script runs as root!"
	exit 1
fi
printf "Pool ${GREEN}successfully${NC} imported!\n\n"

for processing in "${backupDsNames[@]}"
do
	printf "\n${BLUE}Create backup/${processing}${NC}\n"
	zfs create backup/${processing} || myExit
	printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T")\n\n"

	for ds in "${arraySets[@]}"
	do
		# usage of ${ds#*/} so strip the pool name from the ds path
		printf "${BLUE}Create backup/${processing}/${ds#*/} and create snapshot @${poolSnapshot}${NC}\n"
		zfs create ${backupPool}/${processing}/${ds#*/} || myExit
		zfs snapshot ${backupPool}/${processing}/${ds#*/}@${poolSnapshot} || myExit
		printf "${GREEN}Done${NC} at $(date "+%Y-%m-%d %T")\n\n"
	done
done

printf "\nAll tasks ${GREEN}successfully${NC} completed!\n"

exit
