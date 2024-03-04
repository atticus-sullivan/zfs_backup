# What is this?
This is a collection of scripts for the use of making backups on a zfs.

# How to use this
- Clone this repo or download it somehow
- Create your `backup.cfg` (there is an example `backup.cfg.def` contained in
  this repo)
- Afterwards just execute the `backup.bash` script (as root) and the backup will be made

# The variables
variable name | description
-------|-------
`BACKUP_POOL` | the name of the pool on which the backup is stored
`BACKUP_DS_NAMES` | a list of datasets on which the different backups are stored (for more see below)
`SNAPSHOT_NAME` | the name of the snapshot which then is transferred to the backup device
`ARRAY_SET` | a list of all datasets that should be backupped (full path starting from the pool is required)

## BACKUP_DS_NAMES
The amount of items in this list descide how many backups are left on the
backup-pool (e.g. `"bak1" "bak2"` means that there will always be two backups,
the previous one and the current one)

# Prerequisites
To successfully run the `backup.bash`, the datasets specified as
`backupDsNames` all have to exist. In addition, on each of these sets there have
to be datasets with the same name/path as the ones you want to back up.

Example: `BACKUP_POOL=backup ; BACKUP_DS_NAMES=("bak1" "bak2") ; ARRAY_SET=("data/daten data/home")`
then the Datasets `backup/bak1`, `backup/bak2`, `backup/bak1/daten`,
`backup/bak1/home`, `backup/bak2/daten` and `backup/bak2/home` have to exist.

Hint: By running `backup.bash` with the `-n` flag, the script automatically
detects missing datasets (and snapshots) which are needed before creating the
backup and creates them.

# Encryption
In case you're using encypted datasets, these need to be mounted before running
`zfs send | zfs recv`. In case an encrypted dataset is not mounted, the
`backup.bash` script will try to mount it (and you will need to provide the
passphrase for the decryption).

# Progress
Just a small snippet of `lua` (using the `date` library) for calculating when
the replication is finished (or when it should be finished)
```lua
function foo(sent)
    now = date()
    -- insert the start time/date here (if you do this later, you can check the
    -- change date of `stat.txt` and/or the timestamp should also be included in
    -- the console output)
    start = date(2024, 3, 4, 17, 46, 8)
    total_s = (now - start):spanseconds() * (379 / sent)

    return start:copy():addseconds(total_s)
end
```

# Credits
A huge thank you to Galatheas for pointing me to zfs and the basic framework of
the `backup.bash` script originates from him too
