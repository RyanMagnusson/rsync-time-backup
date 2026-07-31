#!/usr/bin/env bash
# rsync_tmbackup_exfat_v2.sh
# Version 2.0.0
# Full, timestamped snapshots for ExFAT destinations.
# No hard links, no --link-dest, no automatic deletion or expiration.

set -u

APP_NAME="$(basename "$0")"
VERSION="2.0.0"
DEFAULT_EXCLUDE_FILE="$HOME/.config/rsync_tmbackup/excludes.txt"
MARKER_NAME="backup.marker"
INPROGRESS_NAME="backup.inprogress"
LATEST_NAME="latest.txt"
LOG_DIR_NAME="logs"
PARTIAL_DIR_NAME=".rsync-partial"
DRY_RUN=0
EXCLUDE_FILE=""
NO_DEFAULT_EXCLUDES=0
SOURCE=""
DEST_ROOT=""
CURRENT_SNAPSHOT=""
LOG_FILE=""

info()  { printf '%s: %s\n' "$APP_NAME" "$*"; }
warn()  { printf '%s: [WARNING] %s\n' "$APP_NAME" "$*" >&2; }
error() { printf '%s: [ERROR] %s\n' "$APP_NAME" "$*" >&2; }
die()   { error "$*"; exit 1; }

usage() {
  cat <<USAGE
$APP_NAME v$VERSION

Usage:
  $APP_NAME [options] SOURCE DESTINATION [LEGACY_EXCLUDE_FILE]

Creates a complete timestamped snapshot under DESTINATION. If an interrupted
backup is detected, it resumes the snapshot named by DESTINATION/$LATEST_NAME.

Options:
  --exclude-from FILE   Override the default exclude file.
  --no-default-excludes Do not automatically load $DEFAULT_EXCLUDE_FILE.
  --dry-run             Show what rsync would do without changing backup data.
  -h, --help            Show this help.
  --version             Show version.

Destination safety marker:
  DESTINATION/$MARKER_NAME must exist before a real run.

Example:
  touch "/Volumes/Sandisk1TB/Backups/$MARKER_NAME"
  $APP_NAME --exclude-from "$HOME/backup-excludes.txt" \
    "$HOME" "/Volumes/Sandisk1TB/Backups"
USAGE
}

trim_state_value() {
  # Remove CR/LF and surrounding whitespace. Repair the known legacy trailing
  # literal 'n' only when it follows an otherwise valid timestamp.
  local value="$1"
  value="$(printf '%s' "$value" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  case "$value" in
    ????-??-??-??????n) value="${value%n}" ;;
  esac
  printf '%s' "$value"
}

valid_snapshot_name() {
  printf '%s' "$1" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}$'
}

atomic_write() {
  local destination="$1"
  local value="$2"
  local temporary="${destination}.tmp.$$"
  printf '%s\n' "$value" > "$temporary" || return 1
  mv -f "$temporary" "$destination"
}

human_kib() {
  awk -v kib="$1" 'BEGIN {
    split("KiB MiB GiB TiB PiB", u, " ");
    n=kib; i=1;
    while (n>=1024 && i<5) { n/=1024; i++ }
    if (i==1) printf "%.0f %s", n, u[i]; else printf "%.1f %s", n, u[i]
  }'
}

count_exclude_patterns() {
  awk 'BEGIN { n=0 }
    { sub(/\r$/, "") }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }
    { n++ }
    END { print n }' "$1"
}

on_interrupt() {
  printf '\n' >&2
  warn "Interrupted. Resume state was retained. Run the same command again."
  [ -n "$CURRENT_SNAPSHOT" ] && warn "Incomplete snapshot: $CURRENT_SNAPSHOT"
  exit 130
}
trap on_interrupt INT TERM HUP

# Parse options without eval.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --exclude-from)
      [ "$#" -ge 2 ] || die "--exclude-from requires a file path."
      EXCLUDE_FILE="$2"
      shift 2
      ;;
    --exclude-from=*)
      EXCLUDE_FILE="${1#*=}"
      shift
      ;;
    --no-default-excludes)
      NO_DEFAULT_EXCLUDES=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --version)
      printf '%s v%s\n' "$APP_NAME" "$VERSION"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      break
      ;;
  esac
done

[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
SOURCE="$1"
DEST_ROOT="$2"
LEGACY_EXCLUDE_FILE="${3:-}"

# A third positional argument remains supported for compatibility.
if [ -n "$LEGACY_EXCLUDE_FILE" ]; then
  [ -z "$EXCLUDE_FILE" ] || die "Specify an exclude file either with --exclude-from or as the third argument, not both."
  EXCLUDE_FILE="$LEGACY_EXCLUDE_FILE"
elif [ -z "$EXCLUDE_FILE" ] && [ "$NO_DEFAULT_EXCLUDES" -eq 0 ] && [ -f "$DEFAULT_EXCLUDE_FILE" ]; then
  EXCLUDE_FILE="$DEFAULT_EXCLUDE_FILE"
fi

command -v rsync >/dev/null 2>&1 || die "rsync is not installed or not in PATH."
[ -e "$SOURCE" ] || die "Source does not exist: $SOURCE"
[ -d "$SOURCE" ] || die "Source must be a directory: $SOURCE"
[ -d "$DEST_ROOT" ] || die "Destination directory does not exist: $DEST_ROOT"
[ -w "$DEST_ROOT" ] || die "Destination is not writable: $DEST_ROOT"

# Resolve local paths so state and safety checks are unambiguous.
SOURCE="$(cd "$SOURCE" 2>/dev/null && pwd -P)" || die "Cannot resolve source path."
DEST_ROOT="$(cd "$DEST_ROOT" 2>/dev/null && pwd -P)" || die "Cannot resolve destination path."

case "$DEST_ROOT/" in
  "$SOURCE/"*|"$SOURCE/") die "Destination cannot be inside the source." ;;
esac
case "$SOURCE/" in
  "$DEST_ROOT/"*|"$DEST_ROOT/") warn "Source is inside the destination; verify this is intentional." ;;
esac

MARKER_FILE="$DEST_ROOT/$MARKER_NAME"
INPROGRESS_FILE="$DEST_ROOT/$INPROGRESS_NAME"
LATEST_FILE="$DEST_ROOT/$LATEST_NAME"
LOG_DIR="$DEST_ROOT/$LOG_DIR_NAME"

if [ "$DRY_RUN" -eq 0 ]; then
  [ -f "$MARKER_FILE" ] || die "Safety marker missing: $MARKER_FILE\nCreate it only after confirming this is the correct destination:\n  touch \"$MARKER_FILE\""
fi

if [ -n "$EXCLUDE_FILE" ]; then
  [ -f "$EXCLUDE_FILE" ] || die "Exclude file not found: $EXCLUDE_FILE"
  [ -r "$EXCLUDE_FILE" ] || die "Exclude file is not readable: $EXCLUDE_FILE"
  EXCLUDE_FILE="$(cd "$(dirname "$EXCLUDE_FILE")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$EXCLUDE_FILE")")"
  EXCLUDE_COUNT="$(count_exclude_patterns "$EXCLUDE_FILE")"
else
  EXCLUDE_COUNT=0
fi

RESUMING=0
SNAPSHOT_NAME=""
if [ -f "$INPROGRESS_FILE" ]; then
  [ -f "$LATEST_FILE" ] || die "$INPROGRESS_NAME exists, but $LATEST_NAME is missing. Refusing to guess the interrupted snapshot."
  RAW_LATEST="$(cat "$LATEST_FILE" 2>/dev/null || true)"
  SNAPSHOT_NAME="$(trim_state_value "$RAW_LATEST")"
  valid_snapshot_name "$SNAPSHOT_NAME" || die "Invalid snapshot name in $LATEST_FILE: '$RAW_LATEST'"
  SNAPSHOT_DIR="$DEST_ROOT/$SNAPSHOT_NAME"
  [ -d "$SNAPSHOT_DIR" ] || die "Resume snapshot directory does not exist: $SNAPSHOT_DIR"
  RESUMING=1
else
  SNAPSHOT_NAME="$(date '+%Y-%m-%d-%H%M%S')"
  SNAPSHOT_DIR="$DEST_ROOT/$SNAPSHOT_NAME"
  [ ! -e "$SNAPSHOT_DIR" ] || die "Snapshot path already exists: $SNAPSHOT_DIR"
fi
CURRENT_SNAPSHOT="$SNAPSHOT_DIR"

AVAILABLE_KIB="$(df -Pk "$DEST_ROOT" | awk 'NR==2 {print $4}')"
SOURCE_KIB="$(du -sk "$SOURCE" 2>/dev/null | awk '{print $1}')"
[ -n "$AVAILABLE_KIB" ] || AVAILABLE_KIB=0
[ -n "$SOURCE_KIB" ] || SOURCE_KIB=0

printf '\n%s v%s\n' "$APP_NAME" "$VERSION"
printf '%s\n' '------------------------------------------------------------'
printf 'Mode:                 ExFAT full timestamped snapshot\n'
printf 'Source:               %s\n' "$SOURCE"
printf 'Destination root:     %s\n' "$DEST_ROOT"
printf 'Snapshot:             %s\n' "$SNAPSHOT_NAME"
printf 'Resume:               %s\n' "$([ "$RESUMING" -eq 1 ] && printf 'Yes' || printf 'No')"
printf 'Dry run:              %s\n' "$([ "$DRY_RUN" -eq 1 ] && printf 'Yes' || printf 'No')"
if [ -n "$EXCLUDE_FILE" ]; then
  printf 'Exclude file:          %s\n' "$EXCLUDE_FILE"
else
  printf 'Exclude file:          none\n'
fi
printf 'Active exclude rules:  %s\n' "$EXCLUDE_COUNT"
printf 'Source apparent size:  %s\n' "$(human_kib "$SOURCE_KIB")"
printf 'Destination free:     %s\n' "$(human_kib "$AVAILABLE_KIB")"
printf '%s\n\n' '------------------------------------------------------------'

if [ -z "$EXCLUDE_FILE" ]; then
  warn "No exclude file is active; no files or folders will be excluded."
elif [ "$EXCLUDE_COUNT" -eq 0 ]; then
  warn "The exclude file contains no active patterns."
fi

if [ "$RESUMING" -eq 0 ] && [ "$SOURCE_KIB" -gt "$AVAILABLE_KIB" ]; then
  warn "The source appears larger than the currently available destination space."
  warn "Because this is a full snapshot without hard links, the backup may run out of space."
fi

mkdir -p "$LOG_DIR" || die "Could not create log directory: $LOG_DIR"
LOG_FILE="$LOG_DIR/$SNAPSHOT_NAME.log"

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
  "--partial-dir=$PARTIAL_DIR_NAME"
)

if [ -n "$EXCLUDE_FILE" ]; then
  RSYNC_ARGS+=("--exclude-from=$EXCLUDE_FILE")
fi
if [ "$DRY_RUN" -eq 1 ]; then
  RSYNC_ARGS+=(--dry-run)
fi

# Use trailing slashes to copy SOURCE contents into the timestamped directory.
if [ "$DRY_RUN" -eq 0 ]; then
  if [ "$RESUMING" -eq 0 ]; then
    mkdir -p "$SNAPSHOT_DIR" || die "Could not create snapshot directory: $SNAPSHOT_DIR"
    atomic_write "$LATEST_FILE" "$SNAPSHOT_NAME" || die "Could not write $LATEST_FILE"
    atomic_write "$INPROGRESS_FILE" "$SNAPSHOT_NAME" || die "Could not write $INPROGRESS_FILE"
  else
    # Normalize legacy/malformed latest.txt contents before resuming.
    atomic_write "$LATEST_FILE" "$SNAPSHOT_NAME" || die "Could not normalize $LATEST_FILE"
    atomic_write "$INPROGRESS_FILE" "$SNAPSHOT_NAME" || die "Could not normalize $INPROGRESS_FILE"
    info "Resuming interrupted snapshot: $SNAPSHOT_DIR"
  fi
else
  info "Dry run: state files and snapshot directories will not be changed."
fi

info "Starting rsync. Log: $LOG_FILE"
set +e
rsync "${RSYNC_ARGS[@]}" "$SOURCE/" "$SNAPSHOT_DIR/" 2>&1 | tee -a "$LOG_FILE"
RSYNC_STATUS=${PIPESTATUS[0]}
set -e

if [ "$RSYNC_STATUS" -ne 0 ]; then
  error "rsync exited with status $RSYNC_STATUS."
  if [ "$DRY_RUN" -eq 0 ]; then
    warn "Resume state retained. Run the same command again to continue snapshot $SNAPSHOT_NAME."
  fi
  exit "$RSYNC_STATUS"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  info "Dry run completed successfully."
  exit 0
fi

rm -f "$INPROGRESS_FILE" || die "Backup copied successfully, but could not remove $INPROGRESS_FILE"
atomic_write "$LATEST_FILE" "$SNAPSHOT_NAME" || die "Backup copied successfully, but could not finalize $LATEST_FILE"

# Remove an empty partial directory, but preserve it if partial files remain.
rmdir "$SNAPSHOT_DIR/$PARTIAL_DIR_NAME" 2>/dev/null || true

info "Snapshot completed successfully: $SNAPSHOT_DIR"
info "Resume marker removed; $LATEST_NAME now identifies the completed snapshot."
