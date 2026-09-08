# NOTEPAD.R4X

`NOTEPAD.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.8`
- Image target: `/R4OS/SOFTWARE/DESKTOP/NOTEPAD.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux or macOS:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## Documentation

Rendering and both scrollbars share one current-document TextArea layout.
Wrap, font and window changes recompute that bounded layout. Long clipped
captions use complete measured UTF-8 candidates and logarithmic search
within each logical line.

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.


Notepad document loading (0.78.68)
----------------------------------
Notepad0.1.10 retains the origin of a truncated load across typing, cut and
paste. Direct Save remains blocked. Save As can turn this prefix into a new
document only at a missing target; an existing file, alias or failed target
lookup is rejected. Successful creation publishes the new path and clears
the prefix origin and Dirty together. Atomic save replacement is described below for 0.78.69.

Loading stages at most32KB of source bytes, including a one-byte EOF probe,
before changing the visible editor, path, directory, Dirty or prefix state.
It does not infer completion from optional file metadata. Any read failure
preserves the old document including selection, view and pending recent-file
state. Discarding a save prompt before opening another file does not mark the
old document clean while the new file is still unconfirmed. Only successful
load, New or a successful Save As to a fresh file resets load provenance.
Counting raw input also bounds files made of filtered text-control bytes;
the normal editor retains its32KB buffer with32767 usable text bytes.

Three focused host groups cover editing and Save As guards, a failure after
the first512-byte read, state preservation, normalization and the exact EOF
boundary. A short SMP4 console probe uses the actual document methods with
a private40000-byte file, checks the retained full original and fresh copy,
and verifies a failed subsequent open. No manual visual check or large
editor/graphics profile is required.


Document saving (0.78.69)
--------------------------
Notepad 0.1.11 and Paint 0.1.7 share the SDK document_save.Saver policy.
Save and Save As first create a private 8.3 sibling (DSxxxxxx.TMP), write
bounded chunks and confirm the final stream flush. Only then does the
existing Files.replaceAtomic facade publish the target. An old document is
never passed to fileWrite. Path, Dirty and recent-file history change only
after confirmed replacement. A truncated Notepad load also requires the
target to remain absent at the atomic publication boundary.

A failure before replacement aborts only the exact owned stream. An
unconfirmed replacement retains the stage and backup for recovery, while
the app keeps its edited document. A confirmed save with failed backup
cleanup stays successful and reports the retained backup. The temporary
names remain in the target directory; there is no direct-write fallback.
Existing FAT long names can be replaced, but creation of a new FAT long
name is not supported by the current atomic storage primitive. Such a
request fails without falling back to an unsafe overwrite.

One host case injects a single short stage write and checks unchanged
Notepad text, selection, path, Dirty and pending history, no replacement,
and cleanup of the owned stage. One short SMP4 console probe calls the real
Notepad methods on private FAT files and the real Paint methods on private
NTFS files: Save and Save As over existing targets, exact saved bytes,
metadata and sibling cleanup. It also confirms fresh Save As of a Notepad
prefix through the create-only atomic path. Both product modules build.
