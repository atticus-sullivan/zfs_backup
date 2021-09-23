#!/bin/bash

	# check if started with sudo
	if [[ "$EUID" -ne 0 ]]
	then
		printf "%s\n" "This script has to be run as root (sudo)"
		exit 1
	fi

if [[ -d "/etc/cron.hourly" && ! -f "/etc/cron.hourly/zfsnap" ]]
then
	cat > /etc/cron.hourly/zfsnap << EOF
#!/bin/bash

#create snapshots
/usr/bin/zfsnap snapshot -a 1d -p _HOURLY_ data/daten

#destroy expired snapshots
/usr/bin/zfsnap destroy -p _HOURLY_ -v data/daten
EOF
	sudo chown root:root "/etc/cron.hourly/zfsnap"
	sudo chmod 755 "/etc/cron.hourly/zfsnap"
else
	printf "\"/etc/cron.hourly\" not present or \"/etc/cron.hourly/zfsnap\" is already present -> skipping\n"
fi

if [[ -d "/etc/cron.weekly" && ! -f "/etc/cron.weekly/zfsnap" ]]
then
	cat > /etc/cron.weekly/zfsnap << EOF
#!/bin/bash

#create snapshots
/usr/bin/zfsnap snapshot -a 1m -p _WEEKLY_ data/daten

#destroy expired snapshots
/usr/bin/zfsnap destroy -p _WEEKLY_ -v data/daten
EOF
	sudo chown root:root "/etc/cron.weekly/zfsnap"
	sudo chmod 755 "/etc/cron.weekly/zfsnap"
else
	printf "\"/etc/cron.weekly\" not present or \"/etc/cron.weekly/zfsnap\" is already present -> skipping\n"
fi

if [[ -d "/etc/cron.daily" && ! -f "/etc/cron.daily/zfsnap" ]]
then
	cat > /etc/cron.daily/zfsnap << EOF
#!/bin/bash

#create snapshots
/usr/bin/zfsnap snapshot -a 1w -p _DAILY_ data/daten

#destroy expired snapshots
/usr/bin/zfsnap destroy -p _DAILY_ -v data/daten
EOF
	sudo chown root:root "/etc/cron.daily/zfsnap"
	sudo chmod 755 "/etc/cron.daily/zfsnap"
else
	printf "\"/etc/cron.daily\" not present or \"/etc/cron.daily/zfsnap\" is already present -> skipping\n"
fi
