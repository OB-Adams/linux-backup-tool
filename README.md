# linux-backup-tool

A bash tool that creates a timestamped, compressed tar archive of a source
directory, verifies the archive isn't corrupt, and prunes archives older
than a retention window. Built for cron/systemd timers, with monitoring
-friendly exit codes.

Third in a set of sysadmin practice scripts (user provisioning, server
bootstrap, memory monitor) built while prepping for Linux admin / junior
cloud / help desk roles.

## Layout

```
.
├── logs/            # runtime log output (gitignore this, don't track it)
├── script/
│   └── backup.sh
└── README.md
```

## Usage

```bash
chmod +x script/backup.sh
./script/backup.sh -s /etc -d /srv/backups                     # basic backup
./script/backup.sh -s /var/www -d /srv/backups -r 14           # 14-day retention
./script/backup.sh -s /etc -d /srv/backups -q -l logs/backup.log  # cron-friendly
```

```
Required:
  -s DIR   Source directory to back up
  -d DIR   Destination directory to store archives in

Options:
  -r DAYS  Retention window in days; archives older than this are deleted (default: 7)
  -l FILE  Append a timestamped log line to FILE
  -q       Quiet: suppress the human-readable report, keep exit code + log
  -h       Show this help
```

### Exit codes

| Code | Meaning  |
|------|----------|
| 0    | OK       |
| 1    | WARNING  (backup succeeded, but a retention delete failed) |
| 2    | FAILURE  (archive creation or verification failed) |
| 3    | Script error (bad args, missing source dir) |

## What it does, step by step

1. Validates `-s`/`-d` were given and the source directory exists.
2. Builds an archive name: `<source-basename>-<YYYYmmdd-HHMMSS>.tar.gz`.
3. Runs `tar -czf` from the *parent* of the source dir, so the archive
   contains a clean relative path instead of your full absolute path.
4. Verifies the archive by listing its contents (`tar -tzf`) — catches
   truncated or corrupted archives before you find out the hard way,
   during a restore.
5. Deletes archives for that same source older than the retention window
   (`find ... -mtime +N`), and reports what got removed.

## Example output

```
[2026-08-10 09:02:11] backup: OK
  Source : /etc
  Archive: etc-20260810-090211.tar.gz (3.2M)
  Retention: 7 days, 4 archive(s) currently kept
  Deleted 1 archive(s) past retention:
    - etc-20260802-090003.tar.gz
```

## Running on a schedule

```cron
0 2 * * * /opt/scripts/script/backup.sh -s /etc -d /srv/backups -q -l /opt/scripts/logs/backup.log || \
    mail -s "backup FAILED: $(hostname)" you@example.com < /opt/scripts/logs/backup.log
```

## Known limitation

Archive names use 1-second timestamp resolution. Two runs against the same
source within the same second will collide and the second run overwrites
the first archive silently (tar just replaces the file). Not an issue for
normal cron cadences (hourly/daily), but worth knowing.

## Concepts this touches (useful for interviews)

- **tar**: creation (`-c`), extraction (`-x`), listing (`-t`), gzip
  compression (`-z`), and why `-C` (change directory before archiving)
  keeps paths inside the archive clean and relative instead of absolute.
- **Archive verification**: `tar -tzf` reads the archive's index without
  extracting — cheap way to confirm it isn't corrupt right after creation.
- **Retention/pruning**: `find DIR -mtime +N` finds files with an mtime
  older than N days; the standard building block for "delete anything
  older than X" logic.
- **Full vs incremental**: this script only does full backups (whole
  directory, every run). `rsync` is the natural next step for
  incremental — only transferring what changed.
- **Restore testing**: verifying with `tar -tzf` is *not* the same as
  proving a restore works. Periodically extract a backup somewhere and
  confirm the files are actually intact and usable.

## Possible next steps

- A `restore.sh` companion: extract a chosen archive to a target
  directory, with a dry-run (`--list`) mode first.
- Switch from full tar snapshots to `rsync --link-dest` for
  space-efficient incremental backups that still look like full
  snapshots on disk (hardlink-based).
- Encrypt archives at rest (`gpg --symmetric`) if backing up anything
  sensitive, especially before shipping off-box.
- Ship archives to a remote host via `rsync`/`scp` over SSH keys instead
  of (or in addition to) local `DEST_DIR`.
