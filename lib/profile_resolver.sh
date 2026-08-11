#!/usr/bin/env bash

# RTB profile v1 resolver. This file is sourced by the backup entry points and
# can also be sourced by tests. It deliberately uses only Bash and awk/grep.

RTB_PROFILE_STACK=""
RTB_PROFILE_RESOLVED=""
RTB_PROFILE_INCLUDES_FILE=""
RTB_PROFILE_EXCLUDES_FILE=""

rtb_profile_error() {
	printf 'profile resolver: %s\n' "$1" >&2
}

rtb_profile_list_contains() {
	printf '%s\n' "$1" | grep -F -x -- "$2" >/dev/null 2>&1
}

rtb_profile_add_unique() {
	local file="$1"
	local rule="$2"
	grep -F -x -- "$rule" "$file" >/dev/null 2>&1 || printf '%s\n' "$rule" >> "$file"
}

rtb_profile_path() {
	local reference="$1"
	case "$reference" in
		*/*|*.profile)
			printf '%s\n' "$reference"
			;;
		*)
			printf '%s/%s.profile\n' "$RTB_PROFILES_DIR" "$reference"
			;;
	esac
}

rtb_profile_resolve_one() {
	local reference="$1"
	local profile_file
	local canonical
	local line_number=0
	local directive
	local value
	local version=""
	local version_count=0
	local extends=""

	profile_file="$(rtb_profile_path "$reference")"
	if [ ! -f "$profile_file" ] || [ ! -r "$profile_file" ]; then
		rtb_profile_error "profile '$reference' was not found or is not readable ($profile_file)"
		return 1
	fi
	canonical="$(cd "$(dirname "$profile_file")" 2>/dev/null && pwd)/$(basename "$profile_file")"

	if rtb_profile_list_contains "$RTB_PROFILE_RESOLVED" "$canonical"; then
		return 0
	fi
	if rtb_profile_list_contains "$RTB_PROFILE_STACK" "$canonical"; then
		rtb_profile_error "circular extends detected while resolving '$reference'"
		return 1
	fi
	RTB_PROFILE_STACK="${RTB_PROFILE_STACK}${RTB_PROFILE_STACK:+
}${canonical}"

	while IFS= read -r line || [ -n "$line" ]; do
		line_number=$((line_number + 1))
		line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		case "$line" in ''|'#'*) continue ;; esac
		directive="${line%%[[:space:]]*}"
		if [ "$directive" = "$line" ]; then
			rtb_profile_error "$profile_file:$line_number: expected '<directive> <value>'"
			return 1
		fi
		value="${line#"$directive"}"
		value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//')"
		case "$directive" in
			version) version="$value"; version_count=$((version_count + 1)) ;;
			extends) extends="${extends}${extends:+
}${value}" ;;
			include) ;;
			exclude) ;;
			*) rtb_profile_error "$profile_file:$line_number: unknown directive '$directive'"; return 1 ;;
		esac
	done < "$profile_file"

	if [ "$version" != "1" ] || [ "$version_count" -ne 1 ]; then
		rtb_profile_error "$profile_file: expected exactly one supported 'version 1' declaration"
		return 1
	fi

	while IFS= read -r value; do
		[ -n "$value" ] || continue
		rtb_profile_resolve_one "$value" || return 1
	done <<EOF
$extends
EOF

	while IFS= read -r line || [ -n "$line" ]; do
		line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
		case "$line" in ''|'#'*) continue ;; esac
		directive="${line%%[[:space:]]*}"
		value="${line#"$directive"}"
		value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//')"
		case "$directive" in
			include) rtb_profile_add_unique "$RTB_PROFILE_INCLUDES_FILE" "$value" ;;
			exclude) rtb_profile_add_unique "$RTB_PROFILE_EXCLUDES_FILE" "$value" ;;
		esac
	done < "$profile_file"

	RTB_PROFILE_STACK="$(printf '%s\n' "$RTB_PROFILE_STACK" | sed '$d')"
	RTB_PROFILE_RESOLVED="${RTB_PROFILE_RESOLVED}${RTB_PROFILE_RESOLVED:+
}${canonical}"
}

rtb_profiles_resolve() {
	RTB_PROFILES_DIR="$1"
	RTB_PROFILE_INCLUDES_FILE="$2"
	RTB_PROFILE_EXCLUDES_FILE="$3"
	shift 3
	RTB_PROFILE_STACK=""
	RTB_PROFILE_RESOLVED=""
	: > "$RTB_PROFILE_INCLUDES_FILE"
	: > "$RTB_PROFILE_EXCLUDES_FILE"
	local reference
	for reference in "$@"; do
		rtb_profile_resolve_one "$reference" || return 1
	done
}
