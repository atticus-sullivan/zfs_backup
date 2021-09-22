# What is this?
This is a collection of scripts for the use of making backups on a zfs.

# How to use this
- Clone this repo or download it somehow
- Adjust the `path` variable in the `backups.bash` script (one of the last lines) to the path where you cloned the repo (basically `pwd` when you're in the folder)
- Then adjust the `backupPool`, `requiredPools`, `poolSnapshot`, `arraySets` to your needs (I hope I will make this easier soon by the use of an `.env` file)
- Afterwards just execute the `backups.bash` script (as root) and the backup will be made

The current script always lets the last backup on the backup device alive so that always two backups are present, the one you're currently making and the last one.

# The variables
backupPool | the name of the pool on which the backup is stored
-------|-------
requiredPools | a list of all pools which have to be present to be able to execute the backup
poolSnapshot | the name of the snapshot which then is transferred to the backup device
arraySets | a list of all datasets that should be backupped (full path starting from the pool is required)
