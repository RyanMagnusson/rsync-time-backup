# Roadmap

## RTB-010 – Intelligent Home Directory Profiling

Status: first stable slice implemented.

Provide reusable, file-based profiles that describe what is backed up. Profile
v1 supports `include`, `exclude`, and `extends`; multiple profiles can be
selected and chained without teaching the backup engine about specific tools
or directory layouts.

Merge semantics are intentionally deterministic:

- includes are a set union;
- excludes are a set union;
- excludes are passed to rsync before includes, so exclude wins when a rule
  matches both sets;
- repeated rules are de-duplicated while preserving first-seen order;
- extends are resolved depth-first, and circular chains are rejected.

Future slices may add profile discovery, validation commands, higher-level
capabilities, and friendlier rule generation. Profile v1 remains the stable,
portable base.

## RTB-011 – Configuration & Job Engine

Status: concepts and forward-compatible schema defined; execution deferred.

RTB-011 separates three concepts:

- **Profile**: what to back up (the RTB-010 rules).
- **Destination**: where and how snapshots are stored.
- **Job**: a named composition of one or more profiles and one destination.

A future versioned job file may look like this:

```text
version 1
destination local-usb
profile developer
profile personal
```

This slice does not parse jobs or destinations. Existing source/destination
arguments remain authoritative, avoiding premature decisions about secrets,
remote hosts, scheduling, and destination-specific settings. The new profile
CLI is the minimal configuration seam needed for later job resolution.
