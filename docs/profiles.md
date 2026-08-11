# Backup profiles (format version 1)

Profiles are plain UTF-8 text files. The format is line-oriented, requires no
YAML parser, and is intended to remain easy to inspect and share.

```text
version 1
extends base
include /Documents/***
include /.ssh/***
exclude /.ssh/known_hosts
exclude /.cache/***
```

Each non-comment line is a directive, one space, and a value. Blank lines and
lines beginning with `#` are ignored. Version 1 accepts:

- `version 1`, required exactly once;
- `extends NAME`, repeatable, resolving `NAME` as `NAME.profile` in the
  profiles directory;
- `include PATTERN`, repeatable;
- `exclude PATTERN`, repeatable.

Rules are rsync filter patterns relative to the source root. `/***` selects a
directory and everything below it. When at least one include exists, everything
not included is excluded. Parent directories required to reach included paths
should therefore be included explicitly when using more complex patterns.

Select profiles with repeatable options:

```sh
./rsync_tmbackup.sh \
  --profiles-dir "$HOME/.config/rsync_tmbackup/profiles" \
  --profile developer --profile personal \
  "$HOME" "/Volumes/Backup"
```

`--profile` also accepts an explicit path containing `/` or ending in
`.profile`. Named profiles default to the repository's `profiles/` directory;
`RTB_PROFILES_DIR` may also set a different default.

Profiles compose as a graph resolved depth-first. Includes union, excludes
union, duplicate rules collapse, and excludes win conflicts. Missing profiles,
unsupported or malformed directives, and circular `extends` chains stop the
backup before destination state changes.

An existing `--exclude-from` file is still supported. Its exclusions are
applied alongside profile exclusions. With no selected profile, profile logic
is not invoked and backup behavior is unchanged.
