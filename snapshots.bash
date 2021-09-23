#!/bin/bash

prCron(){
	duration="$1"
	prefix="$2"
	type="$3"
	shift 3

	if [[ ! ( -d "/etc/cron.${type}" && ! -f "/etc/cron.${type}/zfsnap" ) ]]
	then
		printf "\"/etc/cron.${type}\" not present or \"/etc/cron.${type}/zfsnap\" is already present -> skipping\n"
		return
	fi

	{
		printf "%s\n" \
			"#!/bin/bash" \
			"" \
			"#create snapshots"
		printf "/usr/bin/zfsnap snapshot -a ${duration} -p ${prefix} %s\n" "$@"
		printf "%s\n" \
			"" \
			"#destroy expired snapshots"
		printf "/usr/bin/zfsnap destroy -p ${prefix} -v %s\n" "$@"
	} > /etc/cron.${type}/zfsnap
	sudo chown root:root "/etc/cron.${type}/zfsnap"
	sudo chmod 755 "/etc/cron.${type}/zfsnap"
}

# check if started with sudo
if [[ "$EUID" -ne 0 ]]
then
	printf "%s\n" "This script has to be run as root (sudo)"
	exit 1
fi

for t in hourly daily weekly
do
	printf "\n\n$t snapshots?\n"
	read -ep "[y]es/[N]o " resp 2>&1
	if [[ "$resp" == "y" || "$resp" == "Y" ]]
	then
		printf "\nHow long should these snapshots last? (see \`man zfsnap\` -> TTL Syntax, but I allow only [num][modifier])\n"
		read -p "Duration: " duration

		printf "\nWhat should be the prefix of the snapshots?\n"
		read -p "Prefix: " prefix

		if [[ "$prefix" == "" || "$duration" == "" ]]
		then
			printf "Error: Prefix/duration cannot be empty\n"
			exit 1
		fi
		if [[ ! ( "$duration" =~ [1-9][0-9]*[ymwdhMs] ) ]]
		then
			printf "Error: Duration is not valid\n"
			exit 1
		fi

		prCron "$duration" "$prefix" "$t" "$@"
	fi
done
printf "\n"
