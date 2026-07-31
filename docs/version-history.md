# Version history and engineering notes

## Scope and evidence

The historical scripts arrived in one Git commit, so Git cannot provide their
individual creation dates or an edit-by-edit chronology. This reconstruction
uses:

1. the version identifiers in `versions/`;
2. the name relationships in `version-to-library-mappings.txt`;
3. byte comparisons between mapped files; and
4. behavioral diffs between consecutive versioned scripts.

The `versions/` copies are authoritative for project-history identifiers.
Names and version strings inside scripts are retained as evidence, but they do
not override the archive identifiers.

## Reconstructed sequence

| Project version | Mapped library name | Interpretation |
| --- | --- | --- |
| v2.1 | `rsync_tmbackup_exfat.sh` | First ExFAT-safe, in-place `current/` mirror |
| v2.2 | `rsync_tmbackup_exfat_timestamped.sh` | Independent timestamped ExFAT snapshots |
| v2.3 | `rsync_tmbackup_with_exclude.sh` | Intermediate upstream/hard-link exclusion experiment; not ExFAT-safe despite the archived filename |
| v2.4 (ExFAT) | `rsync_tmbackup_exfat_timestamped_with_excludes.sh` | ExFAT snapshot behavior plus exclusions/default exclusions |
| v2.4 (standard) | `rsync_tmbackup_with_default_excludes.sh` | Hard-link-capable sibling with default exclusions |
| v3.1 | `rsync_tmbackup_exfat_v2.sh` | Clean rewrite, formerly called “-1” |
| v3.2 | `rsync_tmbackup_exfat_v2_1.sh` | Upstream-compatible/resumable implementation |
| v3.3 | `rsync_tmbackup_exfat_v2_2.sh` | Option-order and quoting fixes |
| v3.4 | `rsync_tmbackup_exfat_v2_3.sh` | Explicit `--resume-last` |

All mapped pairs that exist in both folders are byte-for-byte identical.

## Why the ExFAT design differs

The upstream backup model relies on filesystem capabilities that ExFAT does
not provide: hard links for unchanged files, symbolic links for `latest`, and
Unix ownership/permission/device metadata. The ExFAT line therefore makes
these deliberate substitutions:

- full independent copies instead of `--link-dest` hard-link snapshots;
- `latest.txt` instead of a `latest` symlink;
- `--copy-links` so symlink targets become ordinary copied content;
- no preservation of unsupported Unix metadata;
- `--modify-window=2` to tolerate ExFAT timestamp granularity; and
- no automatic expiration/deletion, favoring data preservation when space is
  exhausted.

Following symlinks can copy content outside the apparent source tree. That is
an intentional compatibility tradeoff and should remain prominent in future
user documentation.

## Version-line interpretation

### v2.1 to v2.4: exploratory adaptation

v2.1 proved the ExFAT-safe rsync flag set in a single mutable `current/`
directory. v2.2 restored timestamped snapshots while keeping each one a full,
independent copy. v2.3 is a detour: it is the standard upstream hard-link
implementation with exclusion support, not a safe continuation of v2.2.
v2.4 then forks that work into an ExFAT-safe version and a
standard-filesystem version, both with default exclusions.

### v3.1: a new implementation, not “v2.4-1”

v3.1 is the artifact previously called “-1.” It restarted the script rather
than applying another patch to v2.4, so it begins the v3 line. Its internal
header says `Version 2.0.0`, and its mapped library filename ends in `_v2.sh`;
both are historical implementation labels. Calling the project-history
artifact v3.1 preserves the important architectural boundary.

The rewrite reduced the command surface to local backups but introduced safer
argument handling, array-based rsync invocation, atomic state files, strict
snapshot-name validation, logging, dry run, destination-space warnings, and a
required destination marker.

### v3.2 to v3.4: compatibility and recovery

v3.2 reintroduced the upstream-style feature surface while preserving the
full-copy ExFAT model. It added automatic interrupted-run resume, partial-file
retention, exclusion reporting, and state validation. v3.3 made options
position-independent and tightened missing-value/quoting behavior. v3.4 added
`--resume-last`, allowing an operator to opt into updating the last completed
snapshot as distinct from automatic recovery of an interrupted snapshot.

## Known ambiguities

- No per-version dates or release tags were supplied. These should remain
  “historical snapshots,” not dated releases, unless external records are
  found.
- The v2.3 versioned filename says ExFAT, but its contents enable hard links,
  `--link-dest`, Unix metadata, expiration, and a `latest` symlink. The mapping
  and byte comparison confirm that it is the standard-filesystem exclusion
  experiment.
- v3.1's internal `2.0.0` and v3.2/v3.3's displayed `2.1` do not align with
  the archive version numbers. v3.4 displays `2.3`. These are documented as
  historical internal labels rather than silently corrected.
- The mapping references `library/rsync_tmbackup_exfat_v2_3.sh` for v3.4, but
  that file is absent. The authoritative
  `versions/rsync_tmbackup_exfat_v3.4.sh` is present and differs from v3.3 only
  by the documented `--resume-last` work and displayed-version update.
- `library/backup.inprogress`, `library/latest.txt`, and
  `library/excludes.txt` appear to be example/runtime artifacts. Their exact
  provenance is not encoded in the mapping.

## Repository structure after migration

The temporary `versions/`, `library/`, and mapping artifacts were removed
after the reconstructed v2.1-v3.4 sequence was committed to the history of
`rsync_tmbackup_exfat.sh`. They remain recoverable from Git. The maintained
repository now targets:

```text
.
├── rsync_tmbackup.sh
├── rsync_tmbackup_exfat.sh
├── CHANGELOG.md
├── README.md
├── docs/
│   └── version-history.md
├── examples/
│   └── excludes.txt
├── tests/
│   └── test_exfat.sh
└── list-rename-bad-unicode-filenames.py
```

Migration decisions:

1. `rsync_tmbackup_exfat.sh` is the supported ExFAT script.
2. The generic sample exclusions moved to `examples/excludes.txt`.
3. Runtime state such as `backup.inprogress` and `latest.txt` is not tracked.
4. Historical scripts are preserved in Git rather than duplicated in the
   working tree.
5. Experiments such as v2.3 remain documented without being presented as
   supported releases.
