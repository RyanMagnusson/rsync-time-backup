# Rsync time backup

This script offers Time Machine-style backup using rsync. It creates incremental backups of files and directories to the destination of your choice. The backups are structured in a way that makes it easy to recover any file at any point in time.

It works on Linux, macOS and Windows (via WSL or Cygwin). The main advantage over Time Machine is the flexibility as it can backup from/to any filesystem and works on any platform. You can also backup, for example, to a Truecrypt drive without any problem.

On macOS, it has a few disadvantages compared to Time Machine - in particular it does not auto-start when the backup drive is plugged (though it can be achieved using a launch agent), it requires some knowledge of the command line, and no specific GUI is provided to restore files. Instead files can be restored by using any file explorer, including Finder, or the command line.

## Installation

	git clone https://github.com/RyanMagnusson/rsync-time-backup
	cd rsync-time-backup

## Usage

	Usage: rsync_tmbackup.sh [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION> [exclude-pattern-file]

	Options
	 -p, --port             SSH port.
	 -h, --help             Display this help message.
	 -i, --id_rsa           Specify the private ssh key to use.
	 --rsync-get-flags      Display the default rsync flags that are used for backup. If using remote
	                        drive over SSH, --compress will be added.
	 --rsync-set-flags      Set the rsync flags that are going to be used for backup.
	 --rsync-append-flags   Append the rsync flags that are going to be used for backup.
	 --log-dir              Set the log file directory. If this flag is set, generated files will
	                        not be managed by the script - in particular they will not be
	                        automatically deleted.
	                        Default: /home/backuper/.rsync_tmbackup
	 --log-to-destination   Set the log file directory to the destination directory. If this flag
	                        is set, generated files will not be managed by the script - in particular
				they will not be automatically deleted.
	 --strategy             Set the expiration strategy. Default: "1:1 30:7 365:30" means after one
	                        day, keep one backup per day. After 30 days, keep one backup every 7 days.
	                        After 365 days keep one backup every 30 days.
	 --no-auto-expire       Disable automatically deleting backups when out of space. Instead an error
	                        is logged, and the backup is aborted.

## ExFAT backup variant

This fork includes `rsync_tmbackup_exfat.sh` for destinations that do not
support the hard links, symbolic links, or Unix metadata used by the standard
script. The current implementation is the reconstructed v3.4 history
described in [the changelog](CHANGELOG.md) and
[version history](docs/version-history.md).

The ExFAT variant creates a complete, independent timestamped snapshot on each
normal run. It does not use hard links or `--link-dest`, and it never
automatically expires or deletes older snapshots. This is safer for recovery,
but it can consume substantially more space than the standard script.

Before the first backup, create the destination and its safety marker:

```sh
mkdir -p "/Volumes/Backup"
touch "/Volumes/Backup/backup.marker"
```

Then run:

```sh
bash ./rsync_tmbackup_exfat.sh "$HOME/Documents" "/Volumes/Backup"
```

Snapshots are stored in directories named `YYYY-MM-DD-HHMMSS`.
`latest.txt` identifies the most recent or active snapshot, and
`backup.inprogress` records an interrupted run. Running the same backup command
again automatically resumes an interrupted snapshot.

Use `--resume-last` only when you intentionally want to add new and changed
files to the completed snapshot named by `latest.txt`:

```sh
bash ./rsync_tmbackup_exfat.sh --resume-last \
  "$HOME/Documents" "/Volumes/Backup"
```

`--resume-last` does not make a new snapshot and does not remove files that
were deleted from the source.

### Exclusions

Pass an rsync-compatible exclusion file explicitly:

```sh
bash ./rsync_tmbackup_exfat.sh \
  --exclude-from "$HOME/backup-excludes.txt" \
  "$HOME/Documents" "/Volumes/Backup"
```

The option may appear before or after the source and destination. A third
positional exclude-file argument is retained for compatibility. If no explicit
file is supplied, the script automatically uses
`~/.config/rsync_tmbackup/excludes.txt` when that file exists.

### ExFAT limitations and safety notes

- Every normal run is a full copy; monitor free destination space.
- Existing snapshots are not automatically expired when space runs out.
- Symlinks are followed and their target contents are copied because ExFAT
  cannot store Unix symlinks. A symlink may therefore copy content outside the
  apparent source tree.
- Unix ownership, groups, permissions, device files, hard links, and symlinks
  cannot be preserved on ExFAT.
- The destination must contain `backup.marker`; the script refuses to run
  without it.
- Treat `latest.txt` and `backup.inprogress` as backup state. Do not edit them
  while a backup is running.

## Features

* Each backup is on its own folder named after the current timestamp. Files can be copied and restored directly, without any intermediate tool.

* Backup to/from remote destinations over SSH.

* Files that haven't changed from one backup to the next are hard-linked to the previous backup so take very little extra space.

* Safety check - the backup will only happen if the destination has explicitly been marked as a backup destination.

* Resume feature - if a backup has failed or was interrupted, the tool will resume from there on the next backup.

* Exclude file - support for pattern-based exclusion via the `--exclude-from` rsync parameter.

* Automatically purge old backups - within 24 hours, all backups are kept. Within one month, the most recent backup for each day is kept. For all previous backups, the most recent of each month is kept.

* "latest" symlink that points to the latest successful backup.

## Examples
	
* Backup the home folder to backup_drive
	
		rsync_tmbackup.sh /home /mnt/backup_drive  

* Backup with exclusion list:
	
		rsync_tmbackup.sh /home /mnt/backup_drive excluded_patterns.txt

* Backup to remote drive over SSH, on port 2222:

		rsync_tmbackup.sh -p 2222 /home user@example.com:/mnt/backup_drive


* Backup from remote drive over SSH:

		rsync_tmbackup.sh user@example.com:/home /mnt/backup_drive

* To mimic Time Machine's behaviour, a cron script can be setup to backup at regular interval. For example, the following cron job checks if the drive "/mnt/backup" is currently connected and, if it is, starts the backup. It does this check every 1 hour.
		
		0 */1 * * * if grep -qs /mnt/backup /proc/mounts; then rsync_tmbackup.sh /home /mnt/backup; fi

## Backup expiration logic

Backup sets are automatically deleted following a simple expiration strategy defined with the `--strategy` flag. This strategy is a series of time intervals with each item being defined as `x:y`, which means "after x days, keep one backup every y days". The default strategy is `1:1 30:7 365:30`, which means:

- After **1** day, keep one backup every **1** day (**1:1**).
- After **30** days, keep one backup every **7** days (**30:7**).
- After **365** days, keep one backup every **30** days (**365:30**).

Before the first interval (i.e. by default within the first 24h) it is implied that all backup sets are kept. Additionally, if the backup destination directory is full, the oldest backups are deleted until enough space is available.

## Exclusion file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial](https://web.archive.org/web/20230126121643/https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

## Built-in lock

The script is designed so that only one backup operation can be active for a given directory. If a new backup operation is started while another is still active (i.e. it has not finished yet), the new one will be automaticalled interrupted. Thanks to this the use of `flock` to run the script is not necessary.

## Rsync options

To display the rsync options that are used for backup, run `./rsync_tmbackup.sh --rsync-get-flags`. It is also possible to add or remove options using the `--rsync-append-flags` or `--rsync-set-flags` option. For example, to exclude backing up permissions and groups:

	rsync_tmbackup --rsync-append-flags "--no-perms --no-group" /src /dest

## No automatic backup expiration

An option to disable the default behaviour to purge old backups when out of space. This option is set with the `--no-auto-expire` flag.
	
	
## How to restore

The script creates a backup in a regular directory so you can simply copy the files back to the original directory. You could do that with something like `rsync -aP /path/to/last/backup/ /path/to/restore/to/`. Consider using the `--dry-run` option to check what exactly is going to be copied. Use `--delete` if you also want to delete files that exist in the destination but not in the backup (obviously extra care must be taken when using this option).

For an ExFAT backup, read the snapshot name from `latest.txt` or choose any
timestamped snapshot directory, then copy directly from that directory. The
snapshot contains ordinary files and does not require this script to restore.

## Tests

Run the ExFAT regression suite on a system with Bash and rsync:

```sh
tests/test_exfat.sh
```

The suite uses isolated temporary source and destination directories. It
covers snapshot creation, explicit and default exclusions, interrupted-run
resume, `--resume-last`, marker safety, and invalid resume state.

## Extensions

* [rtb-wrapper](https://github.com/thomas-mc-work/rtb-wrapper): Allows creating backup profiles in config files. Handles both backup and restore operations.
* [time-travel](https://github.com/joekerna/time-travel): Smooth integration into OSX Notification Center

## TODO

* Check source and destination file-system (`df -T /dest`). If one of them is FAT, use the --modify-window rsync parameter (see `man rsync`) with a value of 1 or 2
* Add `--whole-file` arguments on Windows? See http://superuser.com/a/905415/73619
* Minor changes (see TODO comments in the source).

## LICENSE

The MIT License (MIT)

Copyright (c) 2013-2024 Laurent Cozic

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
