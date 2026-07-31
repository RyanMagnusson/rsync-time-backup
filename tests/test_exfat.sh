#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT_DIR/rsync_tmbackup_exfat.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rsync-tmbackup-exfat-tests.XXXXXX")"
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
	LAST_OUTPUT="$(HOME="$HOME_DIR" bash "$SCRIPT" --log-dir "$LOG_DIR" "$@" 2>&1)"
	LAST_STATUS=$?
	set -e
}

snapshot_count() {
	find "$DEST_DIR" -mindepth 1 -maxdepth 1 -type d \
		-name '????-??-??-??????' | wc -l | tr -d ' '
}

latest_snapshot_path() {
	printf '%s/%s' "$DEST_DIR" "$(tr -d '\r\n' < "$DEST_DIR/latest.txt")"
}

test_new_snapshot() {
	new_case new-snapshot
	mark_destination
	printf 'important\n' > "$SOURCE_DIR/keep.txt"
	mkdir "$DEST_DIR/2000-01-01-000000"
	printf 'preserve\n' > "$DEST_DIR/2000-01-01-000000/sentinel.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "new snapshot succeeds" 0
	assert "latest.txt is written" test -f "$DEST_DIR/latest.txt"
	assert "new snapshot contains source data" test -f "$(latest_snapshot_path)/keep.txt"
	assert "completed run removes backup.inprogress" test ! -e "$DEST_DIR/backup.inprogress"
	assert "older snapshots are not deleted" test -f "$DEST_DIR/2000-01-01-000000/sentinel.txt"
}

test_explicit_exclusions_after_paths() {
	new_case explicit-exclusions
	mark_destination
	printf 'keep\n' > "$SOURCE_DIR/keep.txt"
	printf 'ignore\n' > "$SOURCE_DIR/ignored.txt"
	printf '/ignored.txt\n' > "$CASE_DIR/excludes.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR" --exclude-from "$CASE_DIR/excludes.txt"

	assert_status "options after paths are accepted" 0
	assert "non-excluded file is copied" test -f "$(latest_snapshot_path)/keep.txt"
	assert "explicitly excluded file is omitted" test ! -e "$(latest_snapshot_path)/ignored.txt"
}

test_default_exclusions() {
	new_case default-exclusions
	mark_destination
	mkdir -p "$HOME_DIR/.config/rsync_tmbackup"
	printf '/ignored.txt\n' > "$HOME_DIR/.config/rsync_tmbackup/excludes.txt"
	printf 'keep\n' > "$SOURCE_DIR/keep.txt"
	printf 'ignore\n' > "$SOURCE_DIR/ignored.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "default exclude file is accepted" 0
	assert_contains "default exclude file is reported" "$LAST_OUTPUT" "$HOME_DIR/.config/rsync_tmbackup/excludes.txt"
	assert "default exclusion is applied" test ! -e "$(latest_snapshot_path)/ignored.txt"
}

test_interrupted_resume() {
	new_case interrupted-resume
	mark_destination
	local snapshot="2026-01-02-030405"
	mkdir "$DEST_DIR/$snapshot"
	printf '%s\n' "$snapshot" > "$DEST_DIR/latest.txt"
	printf '99999\n' > "$DEST_DIR/backup.inprogress"
	printf 'continued\n' > "$SOURCE_DIR/resumed.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "interrupted snapshot resumes successfully" 0
	assert_contains "automatic resume is reported" "$LAST_OUTPUT" "Resuming interrupted snapshot"
	assert "resume writes into the existing snapshot" test -f "$DEST_DIR/$snapshot/resumed.txt"
	assert "resume does not create another snapshot" test "$(snapshot_count)" -eq 1
	assert "successful resume removes in-progress state" test ! -e "$DEST_DIR/backup.inprogress"
}

test_resume_last() {
	new_case resume-last
	mark_destination
	local snapshot="2026-02-03-040506"
	mkdir "$DEST_DIR/$snapshot"
	printf '%s\n' "$snapshot" > "$DEST_DIR/latest.txt"
	printf 'added later\n' > "$SOURCE_DIR/new.txt"

	run_backup --resume-last "$SOURCE_DIR" "$DEST_DIR"

	assert_status "--resume-last succeeds" 0
	assert_contains "--resume-last is reported" "$LAST_OUTPUT" "Resume-last enabled"
	assert "--resume-last updates the named snapshot" test -f "$DEST_DIR/$snapshot/new.txt"
	assert "--resume-last does not create another snapshot" test "$(snapshot_count)" -eq 1
}

test_marker_safety() {
	new_case marker-safety
	printf 'data\n' > "$SOURCE_DIR/file.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "missing marker is rejected" 1
	assert_contains "marker failure explains the safety check" "$LAST_OUTPUT" "marker file not found"
	assert "missing marker creates no snapshot" test "$(snapshot_count)" -eq 0
}

test_invalid_resume_state() {
	new_case invalid-state
	mark_destination
	printf 'not-a-snapshot\n' > "$DEST_DIR/latest.txt"
	printf '99999\n' > "$DEST_DIR/backup.inprogress"
	printf 'data\n' > "$SOURCE_DIR/file.txt"

	run_backup "$SOURCE_DIR" "$DEST_DIR"

	assert_status "invalid resume state is rejected" 1
	assert_contains "invalid state reports the reason" "$LAST_OUTPUT" "does not contain a valid timestamped snapshot name"
	assert "invalid state creates no snapshot" test "$(snapshot_count)" -eq 0
}

set -e

test_new_snapshot
test_explicit_exclusions_after_paths
test_default_exclusions
test_interrupted_resume
test_resume_last
test_marker_safety
test_invalid_resume_state

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
