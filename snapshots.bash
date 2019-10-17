#!/bin/bash

#pool=data

#zfsnap snapshot -n -a 1 day -p _HOURLY_ -r data
#zfsnap snapshot -n -a 1 week -p _DAILY_ -r data
#zfsnap snapshot -n -a 1 month -p _WEEKLY_ -r data


###########Stündliche Snapshots################
#5   *   *   *   *   root zfsnap snapshot -a 1 day -p _HOURLY_ -r data
#7   *   *   *   *   root zfsnap destroy -p _HOURLY_ -r data

############Tägliche Snapshots##################
#0   0   *   *   *   root zfsnap snapshot -a 1 day -p _HOURLY_ -r data
#0   0   *   *   *   root zfsnap destroy -p _HOURLY_ -r data

##########Wöchentliche Snapshots################
#0   0   *   *   *   root zfsnap snapshot -a 1 day -p _HOURLY_ -r data
#0   0   *   *   0   root zfsnap destroy -p _HOURLY_ -r data
