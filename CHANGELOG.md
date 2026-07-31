# Changelog

This changelog reconstructs the pre-Git development snapshots preserved in
`versions/`. Their original release dates are unknown, so versions are listed
in semantic order rather than by date. See [Version history](docs/version-history.md)
for provenance, naming notes, and known ambiguities.

## Unreleased

### Changed

- Normalized the supported ExFAT script's displayed project version to v3.4.
- Marked `rsync_tmbackup_exfat.sh` executable for direct command-line use.

### Documentation

- Reconstructed the historical v2.1-v3.4 sequence from the versioned scripts
  and `version-to-library-mappings.txt`.
- Documented the ExFAT design decisions and a proposed long-term repository
  structure.

## v3.4

### Added

- Added `--resume-last` to deliberately update the completed snapshot named by
  `latest.txt` with new and changed files.

### Changed

- Continued to resume interrupted snapshots automatically when both
  `backup.inprogress` and `latest.txt` are present.
- Clarified in the script that completed snapshots are modified only when
  `--resume-last` is explicitly requested.
- Updated the script's displayed internal version from 2.1 to 2.3. This
  internal label is historical and does not replace the archive version v3.4.

## v3.3

### Fixed

- Reworked argument parsing so options can appear before or after the source
  and destination.
- Added missing-value checks for options that require a value.
- Added support for both `--exclude-from FILE` and `--exclude-from=FILE`.
- Rejected excess positional arguments and preserved the third positional
  exclude-file form.
- Quoted the generated `--exclude-from` argument consistently.

## v3.2

### Changed

- Returned the rewrite to the upstream-compatible command surface, including
  SSH, logging, destination marker, and rsync flag controls.
- Added resumable ExFAT full-copy snapshots using `backup.inprogress` and
  `latest.txt`, while keeping hard links and `--link-dest` disabled.
- Added partial-transfer retention in `.rsync-partial`.
- Added an optional default exclude file at
  `~/.config/rsync_tmbackup/excludes.txt`, explicit `--exclude-from`, legacy
  positional exclude-file support, validation, and active-rule reporting.
- Validated snapshot names before resuming and repaired the known legacy
  trailing literal `n` in `latest.txt`.
- Kept automatic expiration and deletion disabled for ExFAT backups.

## v3.1

### Changed

- Rewrote the ExFAT implementation from scratch instead of patching v2.4.
  This is the rewrite previously called “-1”; it is v3.1 because it starts a
  new implementation line.
- Introduced a smaller local-only command surface with safe array-based rsync
  invocation and no `eval`.
- Created full, independent, timestamped snapshots without hard links,
  `--link-dest`, or automatic expiration.
- Added a required `backup.marker`, atomic `latest.txt` and
  `backup.inprogress` state updates, interrupted-run resume, dry-run support,
  transfer logs, default exclusions, and destination-space warnings.
- Added validation for source/destination relationships, exclude files, and
  snapshot state.

### Historical note

- The script header and `--version` output say `2.0.0`, and the mapped library
  name is `rsync_tmbackup_exfat_v2.sh`. Those are internal names from the
  rewrite artifact; the preserved project-history version is v3.1.

## v2.4

Two sibling artifacts are preserved under this version.

### ExFAT variant

- Restored ExFAT-safe full-copy behavior after the v2.3 hard-link detour.
- Added `--exclude-from` support and automatic use of
  `~/.config/rsync_tmbackup/excludes.txt` when present.
- Used ExFAT-safe rsync flags: copied symlink targets, omitted Unix ownership,
  permission, device, symlink, and hard-link preservation, and retained the
  two-second timestamp tolerance.
- Continued to create independent timestamped snapshots, write `latest.txt`,
  ignore stale legacy in-progress state, and avoid automatic expiration.

### Standard-filesystem variant

- Added the same default-exclude-file behavior to the hard-link-capable
  upstream-style implementation.
- Retained `--link-dest`, Unix metadata preservation, resume-by-move behavior,
  expiration, and the `latest` symlink.

## v2.3

### Added

- Added explicit exclude-file plumbing to the upstream-style script.

### Changed

- Temporarily used the standard-filesystem implementation with hard links,
  `--link-dest`, Unix metadata preservation, resume-by-move, expiration, and a
  `latest` symlink.

### Compatibility warning

- Despite its archived ExFAT filename, this artifact is not ExFAT-safe. It is
  byte-for-byte identical to the mapped
  `library/rsync_tmbackup_with_exclude.sh` and should be treated as an
  intermediate development snapshot, not an ExFAT release.

## v2.2

### Changed

- Replaced the single `current/` mirror with complete timestamped snapshot
  directories.
- Adapted the upstream command surface for ExFAT while disabling hard links,
  `--link-dest`, resume-by-renaming, and automatic expiration.
- Replaced the unsupported `latest` symlink with `latest.txt`.
- Ignored stale upstream `backup.inprogress` state rather than moving or
  modifying an existing snapshot.
- Preserved ExFAT-safe rsync behavior, including copied symlink targets and
  two-second timestamp tolerance.

## v2.1

### Added

- Introduced the first ExFAT-safe backup variant.
- Updated a single `DESTINATION/current/` mirror-like archive in place without
  deleting source-removed files.
- Disabled hard links, `--link-dest`, Unix ownership/group/permission/device
  preservation, and automatic expiration.
- Followed symlinks and copied their target contents because ExFAT cannot
  represent Unix symlinks.
- Added destination marker checks, dry-run support, rsync flag controls, and
  basic source/destination safety validation.
