#!/bin/bash

#Farben
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;44m'
NC='\033[0;0m'

myExit(){
	printf "Task ${REED}failed${NC}!\nTrying to export the backup-pool anyway.\n"
	zpool export backup && printf "Exporting ${GREEN}successful${NC} " || printf "Exporting ${RED}failed${NC} "
	printf "-> exit"
	exit
}

printf "${BLUE}Importing the backup-pool${NC}\n"
zpool import backup || (printf "${RED}Error${NC} while trying to import the backup-pool!\nMake sure the device with the pool on it is connected and that this script runs as root!" ; exit)
printf "Pool ${GREEN}successfully${NC} imported!"

for num in {1..3}
do
	printf "\n${BLUE}Create backup/bak${num}${NC}\n"
	zfs create backup/bak${num} || myExit
	printf "Task ${GREEN}successfull${NC}!\n\n"

	for ds in daten daten/downloads daten/filme home home/lukas
	do
		printf "${BLUE}Create backup/bak${num}/${ds} and create snapshot @replication${NC}\n"
		zfs create backup/bak${num}/${ds} || myExit
		if [[ "$ds" != "home" ]] #kein home@replication sollte da sein
		then
			zfs snapshot backup/bak${num}/${ds}@replication || myExit
		fi
		printf "Task ${GREEN}successfull${NC}!\n\n"
	done
done

printf "\n\nAll tasks ${GREEN}successfully${NC} completed!\n"

exit
