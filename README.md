# What is this?
This is a collection of scripts for the use of making backups on a zfs.

# How to use this
- Clone this repo or download it somehow
- Ajust the `backup.cfg` to suit your setup. Make sure to fullfill the
  prerequisites stated below before running `backups.bash`
- Afterwards just execute the `backups.bash` script (as root) and the backup will be made

# The variables
variable name | description
-------|-------
`backupPool` | the name of the pool on which the backup is stored
`backupDsNames` | a list of datasets on which the different backups are stored
(for more see below)
`requiredPools` | a list of all pools which have to be present to be able to execute the backup (will soon be deprecated)
`poolSnapshot` | the name of the snapshot which then is transferred to the backup device
`arraySets` | a list of all datasets that should be backupped (full path starting from the pool is required)

## backupDsNames
The amount of items in this list descide how many backups are left on the
backup-pool (e.g. `"bak1" "bak2"` means that there will always be two backups,
the previous one and the current one)

# Prerequisites
To successfully run the `backups.bash`, the datasets specified as `backupDsNames` all have to exist. In addition, on each of these sets there have to be datasets with the same name/path as the ones you want to back up.

Example: `backupPool=backup ; backupDsNames=("bak1" "bak2") ; arraySets=("data/daten data/home")`
then the Datasets `backup/bak1`, `backup/bak2`, `backup/bak1/daten`,
`backup/bak1/home`, `backup/bak2/daten` and `backup/bak2/home` have to exist.

Hint: You can create this structure quickly via the `createBackupDS.bash`
utility which uses the same `backup.cfg` as `backups.bash`

# Credits
A huge thank you to Galatheas for pointing me to zfs and the basic framework of the `backups.bash` script originates from him too
