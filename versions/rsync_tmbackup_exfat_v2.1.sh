#!/usr/bin/env bash
#
# rsync_tmbackup_exfat.sh
# ExFAT-safe mirror variant of rsync_tmbackup.sh.
#
# IMPORTANT DIFFERENCES FROM rsync-time-backup:
#   * No hard links and no --link-dest snapshots (ExFAT cannot support them).
#   * No Unix owner/group/permission/device preservation (ExFAT cannot represent them).
#   * No automatic expiration or deletion.
#   * Repeated runs update DESTINATION/current/ in place as a mirror-like archive.
#   * Source deletions are NOT deleted from the backup.
#   * Symlinks are followed and their target contents are copied because ExFAT cannot
#     store Unix symlinks. Be aware that a symlink can point outside the source tree.
#
# Usage:
#   rsync_tmbackup_exfat.sh [options] SOURCE DESTINATION [exclude-pattern-file]
#
# Example:
#   ./rsync_tmbackup_exfat.sh "$HOME/Documents" /Volumes/Sandisk1TB/MacBackup

set -u

APPNAME=$(basename "$0" | sed 's/\.sh$//')
RSYNC_FLAGS="--recursive --times --copy-links --one-file-system --itemize-changes --stats --human-readable --modify-window=2 --partial"
LOG_DIR="$HOME/.$APPNAME"
EXTRA_RSYNC_FLAGS=""

log_info()  { printf '%s: %s\n' "$APPNAME" "$1"; }
log_warn()  { printf '%s: [WARNING] %s\n' "$APPNAME" "$1" >&2; }
log_error() { printf '%s: [ERROR] %s\n' "$APPNAME" "$1" >&2; }

usage() {
    cat <<USAGE
Usage: $(basename "$0") [OPTION]... SOURCE DESTINATION [exclude-pattern-file]

Creates/updates DESTINATION/current/ using ExFAT-safe rsync options.
It never uses hard links, --link-dest, or --delete.

Options:
  -h, --help                 Show this help.
  --rsync-get-flags          Show the default rsync flags.
  --rsync-append-flags ARG   Append additional rsync flags.
  --log-dir DIR              Store logs in DIR.
  --dry-run                  Show what would be copied without changing files.

For safety, DESTINATION must contain a file named backup.marker.
Create it once with:
  mkdir -p -- "DESTINATION" && touch "DESTINATION/backup.marker"
USAGE
}

DRY_RUN=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        --rsync-get-flags)
            printf '%s\n' "$RSYNC_FLAGS"
            exit 0
            ;;
        --rsync-append-flags)
            shift
            if [ "$#" -eq 0 ]; then
                log_error "--rsync-append-flags requires an argument."
                exit 2
            fi
            EXTRA_RSYNC_FLAGS="$EXTRA_RSYNC_FLAGS $1"
            shift
            ;;
        --log-dir)
            shift
            if [ "$#" -eq 0 ]; then
                log_error "--log-dir requires a directory."
                exit 2
            fi
            LOG_DIR="$1"
            shift
            ;;
        --dry-run)
            DRY_RUN="--dry-run"
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            log_error "Unknown option: $1"
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage >&2
    exit 2
fi

SRC_FOLDER=${1%/}
DEST_FOLDER=${2%/}
EXCLUSION_FILE=${3:-}
DEST="$DEST_FOLDER/current"
MARKER="$DEST_FOLDER/backup.marker"

if [ ! -e "$SRC_FOLDER" ]; then
    log_error "Source does not exist: $SRC_FOLDER"
    exit 1
fi

mkdir -p -- "$DEST_FOLDER" || exit 1

if [ ! -f "$MARKER" ]; then
    log_error "Safety check failed: $MARKER was not found."
    log_info "If this is the intended backup destination, run:"
    printf '  touch %q\n' "$MARKER"
    exit 1
fi

mkdir -p -- "$DEST" "$LOG_DIR" || exit 1

# Warn if destination does not appear to be ExFAT, but do not refuse to run.
if command -v diskutil >/dev/null 2>&1 && [[ "$DEST_FOLDER" == /Volumes/* ]]; then
    VOLUME="/Volumes/${DEST_FOLDER#/Volumes/}"
    VOLUME="/Volumes/${VOLUME#/Volumes/}"
    VOLUME="/Volumes/${VOLUME#/Volumes/}"
    # Reduce to /Volumes/<volume-name> even when DEST_FOLDER has subdirectories.
    VOLUME="/Volumes/$(printf '%s' "${DEST_FOLDER#/Volumes/}" | cut -d/ -f1)"
    FS_PERSONALITY=$(diskutil info "$VOLUME" 2>/dev/null | awk -F: '/File System Personality/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    if [ -n "$FS_PERSONALITY" ]; then
        log_info "Destination filesystem: $FS_PERSONALITY"
    fi
fi

NOW=$(date +"%Y-%m-%d-%H%M%S")
LOG_FILE="$LOG_DIR/$NOW.log"

log_info "ExFAT-safe mirror backup"
log_info "From: $SRC_FOLDER/"
log_info "To:   $DEST/"
log_info "No destination files will be deleted."
log_warn "Symlinks are followed and copied as their target contents because ExFAT cannot store Unix symlinks."

RSYNC_ARGS=(
    --recursive
    --times
    --copy-links
    --one-file-system
    --itemize-changes
    --stats
    --human-readable
    --modify-window=2
    --partial
    --log-file "$LOG_FILE"
)

if [ -n "$DRY_RUN" ]; then
    RSYNC_ARGS+=(--dry-run)
fi

if [ -n "$EXCLUSION_FILE" ]; then
    if [ ! -f "$EXCLUSION_FILE" ]; then
        log_error "Exclude file not found: $EXCLUSION_FILE"
        exit 1
    fi
    RSYNC_ARGS+=(--exclude-from "$EXCLUSION_FILE")
fi

# Preserve compatibility with the old script's append-flags option. Word splitting
# is intentional here because this option contains rsync command-line flags.
if [ -n "$EXTRA_RSYNC_FLAGS" ]; then
    # shellcheck disable=SC2206
    EXTRA_ARGS=( $EXTRA_RSYNC_FLAGS )
    RSYNC_ARGS+=("${EXTRA_ARGS[@]}")
fi

rsync "${RSYNC_ARGS[@]}" -- "$SRC_FOLDER/" "$DEST/"
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
    log_info "Backup completed successfully."
    log_info "Log: $LOG_FILE"
else
    log_error "rsync exited with status $STATUS."
    log_error "Log: $LOG_FILE"
fi

exit "$STATUS"
