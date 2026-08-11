#!/usr/bin/env bash

set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT_DIR/tests/fixtures/profiles"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rsync-tmbackup-profile-tests.XXXXXX")"
INCLUDES="$TEST_ROOT/includes"
EXCLUDES="$TEST_ROOT/excludes"
PASSED=0
FAILED=0

cleanup() { rm -rf -- "$TEST_ROOT"; }
trap cleanup EXIT

# shellcheck source=../lib/profile_resolver.sh
. "$ROOT_DIR/lib/profile_resolver.sh"

check() {
	local description="$1"
	shift
	if "$@"; then
		PASSED=$((PASSED + 1))
		printf 'ok %d - %s\n' "$((PASSED + FAILED))" "$description"
	else
		FAILED=$((FAILED + 1))
		printf 'not ok %d - %s\n' "$((PASSED + FAILED))" "$description"
	fi
}

rtb_profiles_resolve "$FIXTURES" "$INCLUDES" "$EXCLUDES" developer conflict
check "extends chains include parent and child rules" grep -Fqx '/.ssh/***' "$INCLUDES"
check "include union retains inherited rules" grep -Fqx '/Documents/***' "$INCLUDES"
check "include union de-duplicates rules" test "$(grep -Fxc '/Documents/***' "$INCLUDES")" -eq 1
check "exclude union retains inherited rules" grep -Fqx '/.cache/***' "$EXCLUDES"
check "conflicting rule is present in includes" grep -Fqx '/private.txt' "$INCLUDES"
check "conflicting rule is present in excludes (CLI applies excludes first)" grep -Fqx '/private.txt' "$EXCLUDES"

if rtb_profiles_resolve "$FIXTURES" "$INCLUDES" "$EXCLUDES" missing >/dev/null 2>&1; then
	check "missing profiles fail resolution" false
else
	check "missing profiles fail resolution" true
fi

if rtb_profiles_resolve "$FIXTURES" "$INCLUDES" "$EXCLUDES" cycle-a >/dev/null 2>&1; then
	check "circular extends fail resolution" false
else
	check "circular extends fail resolution" true
fi

check "standard CLI exposes repeatable profile selection" bash -c '"$1" --help | grep -q -- "--profile PROFILE"' _ "$ROOT_DIR/rsync_tmbackup.sh"
check "standard and ExFAT profile options remain aligned" bash -c '
	standard=$("$1" --help | grep -Eo -- "--profile(s-dir)?")
	exfat=$("$2" --help | grep -Eo -- "--profile(s-dir)?")
	test "$standard" = "$exfat"
' _ "$ROOT_DIR/rsync_tmbackup.sh" "$ROOT_DIR/rsync_tmbackup_exfat.sh"

mkdir -p "$TEST_ROOT/source" "$TEST_ROOT/destination" "$TEST_ROOT/home" "$TEST_ROOT/logs" "$TEST_ROOT/integration-profiles"
touch "$TEST_ROOT/destination/backup.marker"
printf 'public\n' > "$TEST_ROOT/source/public.txt"
printf 'private\n' > "$TEST_ROOT/source/private.txt"
cat > "$TEST_ROOT/integration-profiles/all.profile" <<'EOF'
version 1
include /***
EOF
cat > "$TEST_ROOT/integration-profiles/private.profile" <<'EOF'
version 1
extends all
include /private.txt
exclude /private.txt
EOF
if HOME="$TEST_ROOT/home" "$ROOT_DIR/rsync_tmbackup.sh" \
	--log-dir "$TEST_ROOT/logs" --profiles-dir "$TEST_ROOT/integration-profiles" \
	--profile private "$TEST_ROOT/source" "$TEST_ROOT/destination" >/dev/null 2>&1; then
	LATEST="$(readlink "$TEST_ROOT/destination/latest")"
	check "profile includes are applied by rsync" test -f "$TEST_ROOT/destination/$LATEST/public.txt"
	check "profile excludes win include conflicts" test ! -e "$TEST_ROOT/destination/$LATEST/private.txt"
else
	check "profile-backed integration backup succeeds" false
fi

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
