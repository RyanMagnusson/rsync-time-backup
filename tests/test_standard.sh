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
	assert "standard resume retains prior snapshot contents" test "$(snapshot_count)" -eq 1
	assert "standard resume copies new data" test -f "$(latest_snapshot_path)/resumed.txt"
	assert "standard successful resume removes in-progress state" test ! -e "$DEST_DIR/backup.inprogress"
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
test_resume_last
test_safety_and_flag_validation

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
