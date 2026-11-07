#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/rsync_tmbackup.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rsync-tmbackup-standard-tests.XXXXXX")"
PASSED=0
FAILED=0
LAST_OUTPUT=""
LAST_STATUS=0

cleanup() {
	rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
	PASSED=$((PASSED + 1))
	printf 'ok %d - %s\n' "$((PASSED + FAILED))" "$1"
}

fail() {
	FAILED=$((FAILED + 1))
	printf 'not ok %d - %s\n' "$((PASSED + FAILED))" "$1"
	printf '%s\n' "$2" | sed 's/^/  /'
}

assert() {
	local description="$1"
	shift
	if "$@"; then
		pass "$description"
	else
		fail "$description" "command failed: $*"
	fi
}

assert_contains() {
	local description="$1"
	local haystack="$2"
	local needle="$3"
	if [[ "$haystack" == *"$needle"* ]]; then
		pass "$description"
	else
		fail "$description" "expected output to contain: $needle"
	fi
}

assert_not_contains() {
	local description="$1"
	local haystack="$2"
	local needle="$3"
	if [[ "$haystack" != *"$needle"* ]]; then
		pass "$description"
	else
		fail "$description" "expected output to omit: $needle"
	fi
}

assert_status() {
	local description="$1"
	local expected="$2"
	if [ "$LAST_STATUS" -eq "$expected" ]; then
		pass "$description"
	else
		fail "$description" "expected status $expected, got $LAST_STATUS
$LAST_OUTPUT"
	fi
}

new_case() {
	local name="$1"
	CASE_DIR="$TEST_ROOT/$name"
	SOURCE_DIR="$CASE_DIR/source"
	DEST_DIR="$CASE_DIR/destination"
	HOME_DIR="$CASE_DIR/home"
	LOG_DIR="$CASE_DIR/logs"
	mkdir -p "$SOURCE_DIR" "$DEST_DIR" "$HOME_DIR" "$LOG_DIR"
}

mark_destination() {
	touch "$DEST_DIR/backup.marker"
}

run_backup() {
	set +e
	LAST_OUTPUT="$(HOME="$HOME_DIR" "$SCRIPT" --log-dir "$LOG_DIR" "$@" 2>&1)"
	LAST_STATUS=$?
	set -e
}

snapshot_count() {
	find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d \
		-name '????-??-??-??????' | wc -l | tr -d ' '
}

latest_snapshot_path() {
	local target
	target="$(readlink "$DEST_DIR/latest")"
	printf '%s/%s' "$DEST_DIR" "$target"
}

inode_number() {
	if stat -f '%i' "$1" >/dev/null 2>&1; then
		stat -f '%i' "$1"
	else
		stat -c '%i' "$1"
	fi
}

test_incremental_snapshots() {
	new_case incremental
	mark_destination
	printf 'unchanged\n' > "$SOURCE_DIR/file.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"
	assert_status "first standard snapshot succeeds" 0
	assert_contains "standard project version is reported" "$LAST_OUTPUT" "Version: 3.5 standard filesystem"
	assert_contains "first standard snapshot reports a new backup" "$LAST_OUTPUT" "No previous backup - creating new one."
	local first_snapshot
	first_snapshot="$(latest_snapshot_path)"

	sleep 1
	run_backup "$SOURCE_DIR" "$DEST_DIR"
	assert_status "second standard snapshot succeeds" 0
	local second_snapshot
	second_snapshot="$(latest_snapshot_path)"

	assert "two timestamped snapshots are retained" test "$(snapshot_count)" -eq 2
	assert "unchanged data is hard-linked between snapshots" \
		test "$(inode_number "$first_snapshot/file.txt")" = "$(inode_number "$second_snapshot/file.txt")"
	assert "latest is a symbolic link" test -L "$DEST_DIR/latest"
	assert "completed run removes backup.inprogress" test ! -e "$DEST_DIR/backup.inprogress"
}

test_explicit_exclusions_after_paths() {
	new_case explicit-exclusions
	mark_destination
	printf 'keep\n' > "$SOURCE_DIR/keep.txt"
	printf 'ignore\n' > "$SOURCE_DIR/ignored.txt"
	printf '/ignored.txt\n' > "$CASE_DIR/excludes.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR" --exclude-from "$CASE_DIR/excludes.txt"

	assert_status "standard options after paths are accepted" 0
	assert "standard backup copies non-excluded files" test -f "$(latest_snapshot_path)/keep.txt"
	assert "standard backup applies explicit exclusions" test ! -e "$(latest_snapshot_path)/ignored.txt"
}

test_default_exclusions() {
	new_case default-exclusions
	mark_destination
	mkdir -p "$HOME_DIR/.config/rsync_tmbackup"
	printf '/ignored.txt\n' > "$HOME_DIR/.config/rsync_tmbackup/excludes.txt"
	printf 'keep\n' > "$SOURCE_DIR/keep.txt"
	printf 'ignore\n' > "$SOURCE_DIR/ignored.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "standard default exclude file is accepted" 0
	assert_contains "standard default exclude file is reported" "$LAST_OUTPUT" "$HOME_DIR/.config/rsync_tmbackup/excludes.txt"
	assert "standard default exclusion is applied" test ! -e "$(latest_snapshot_path)/ignored.txt"
}

test_interrupted_resume() {
	new_case interrupted-resume
	mark_destination
	local snapshot="2026-01-02-030405"
	mkdir "$DEST_DIR/$snapshot"
	ln -s "$snapshot" "$DEST_DIR/latest"
	printf '999999\n' > "$DEST_DIR/backup.inprogress"
	printf 'continued\n' > "$SOURCE_DIR/resumed.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "standard interrupted snapshot resumes successfully" 0
	assert_contains "standard automatic resume is reported" "$LAST_OUTPUT" "Backup will resume from there"
	assert_contains "standard resume with no older snapshot names the interrupted snapshot" "$LAST_OUTPUT" "Continuing interrupted snapshot $DEST_DIR/$snapshot. No older snapshot to hard-link from."
	assert_not_contains "standard resume with no older snapshot does not claim a new backup" "$LAST_OUTPUT" "No previous backup - creating new one."
	assert "standard resume retains prior snapshot contents" test "$(snapshot_count)" -eq 1
	assert "standard resume copies new data" test -f "$(latest_snapshot_path)/resumed.txt"
	assert "standard resume preserves the original timestamp" test "$(readlink "$DEST_DIR/latest")" = "$snapshot"
	assert "standard resume writes to the original directory" test -f "$DEST_DIR/$snapshot/resumed.txt"
	assert "standard successful resume removes in-progress state" test ! -e "$DEST_DIR/backup.inprogress"
}

test_nested_log_directory() {
	new_case nested-logs
	mark_destination
	LOG_DIR="$CASE_DIR/missing/parent/logs"
	printf 'data\n' > "$SOURCE_DIR/file.txt"
	run_backup "$SOURCE_DIR" "$DEST_DIR"
	assert_status "nested log directory backup succeeds" 0
	assert "missing log parents are created" test -d "$LOG_DIR"
	assert "nested log directory contains a transfer log" test -n "$(find "$LOG_DIR" -name '*.log' -print)"
}

test_resume_last() {
	new_case resume-last
	mark_destination
	local snapshot="2026-02-03-040506"
	mkdir "$DEST_DIR/$snapshot"
	ln -s "$snapshot" "$DEST_DIR/latest"
	printf 'added later\n' > "$SOURCE_DIR/new.txt"

	run_backup --resume-last "$SOURCE_DIR" "$DEST_DIR"

	assert_status "standard --resume-last succeeds" 0
	assert_contains "standard --resume-last is reported" "$LAST_OUTPUT" "Resume-last enabled"
	assert "standard --resume-last updates the named snapshot" test -f "$DEST_DIR/$snapshot/new.txt"
	assert "standard --resume-last does not create another snapshot" test "$(snapshot_count)" -eq 1
}

test_rsync_failure_leaves_snapshot_unfinished() {
	new_case rsync-failure
	mark_destination
	local previous="2026-11-01-120000"
	mkdir "$DEST_DIR/$previous"
	ln -s "$previous" "$DEST_DIR/latest"
	printf 'already copied\n' > "$DEST_DIR/$previous/file.txt"
	printf 'new\n' > "$SOURCE_DIR/file.txt"
	mkdir -p "$CASE_DIR/bin"
	cat > "$CASE_DIR/bin/rsync" <<'EOF'
#!/bin/sh
log_file=""
previous=""
for arg in "$@"; do
	if [ "$previous" = "--log-file" ]; then
		log_file=$arg
	fi
	case "$arg" in
		--log-file=*) log_file=${arg#--log-file=} ;;
	esac
	previous=$arg
done
if [ -n "$log_file" ]; then
	: > "$log_file"
fi
echo "rsync(17990): error: unexpected end of file" >&2
exit 1
EOF
	chmod +x "$CASE_DIR/bin/rsync"

	PATH="$CASE_DIR/bin:$PATH" run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "failed rsync is not reported as success" 1
	assert_contains "failed rsync reports its exit status" "$LAST_OUTPUT" "Rsync exited with status 1. The snapshot was left unfinished."
	assert_not_contains "failed rsync does not claim a clean completion" "$LAST_OUTPUT" "Backup completed without errors."
	assert "failed rsync keeps the interrupted snapshot pending" test -f "$DEST_DIR/backup.inprogress"
	assert "failed rsync keeps the previous latest snapshot" test "$(readlink "$DEST_DIR/latest")" = "$previous"
}

test_safety_and_flag_validation() {
	new_case safety
	printf 'data\n' > "$SOURCE_DIR/file.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"
	assert_status "standard missing marker is rejected" 1
	assert_contains "standard marker failure explains safety check" "$LAST_OUTPUT" "marker file not found"

	set +e
	LAST_OUTPUT="$("$SCRIPT" --exclude-from 2>&1)"
	LAST_STATUS=$?
	set -e
	assert_status "standard missing option value is rejected" 1
	assert_contains "standard missing option value is explained" "$LAST_OUTPUT" "requires a file path"

	local flags
	flags="$("$SCRIPT" --rsync-get-flags)"
	assert_contains "standard transfers retain partial files" "$flags" "--partial"
	assert_contains "standard transfers use a partial directory" "$flags" "--partial-dir=.rsync-partial"
	assert_contains "standard transfers retain hard links" "$flags" "--hard-links"

	local standard_options
	local exfat_options
	standard_options="$("$SCRIPT" --help | grep -Eo -- '--[a-z][a-z_-]*' | sort -u)"
	exfat_options="$("$ROOT_DIR/rsync_tmbackup_exfat.sh" --help | grep -Eo -- '--[a-z][a-z_-]*' | sort -u)"
	assert "standard and ExFAT scripts expose the same command-line flags" \
		test "$standard_options" = "$exfat_options"
}

set -e

test_incremental_snapshots
test_explicit_exclusions_after_paths
test_default_exclusions
test_interrupted_resume
test_nested_log_directory
test_resume_last
test_rsync_failure_leaves_snapshot_unfinished
test_safety_and_flag_validation

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
