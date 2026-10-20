# NOTEPAD.R4X

`NOTEPAD.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.14`
- Image target: `/R4OS/SOFTWARE/DESKTOP/NOTEPAD.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

Normal background instances declare `runtime.parallel=owned-v1`; editor,
file dialogs and the synchronous atomic document saver belong to that instance.
All GUI work remains on its single main-thread producer.

## Build

On Windows:

    Build.bat

On Linux:

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

Historical0.78.68 verification covered editing and Save As guards, a failure after
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

Unicode dialog contract (0.85.43)
--------------------------------
Save-as fields accept complete Unicode scalar events and keep separate byte
cursor/selection positions. Invalid or overlong preloads and failed insertions
preserve the previous input; a rejected filename cannot be saved until edited
or replaced by a valid selection. Initial path arguments and constructed paths
are checked in full, before copying or filesystem access. Directory labels may
show a whole-scalar prefix plus ...; the stored full path alone identifies a row.
Glyph coverage is independent of text input. No normalization, grapheme, Bidi
or shaping promise follows from these scalar operations.
Build.sh test (Build.bat test on Windows) exercises the actual app dialog owner.
Tests/DialogText is an explicit IMAGE_SCOPE=none console fixture of the same app
source. /DIALOGTEST additionally verifies real private file saves, full Unicode
row identity, failure-state preservation and cleanup; Notepad checks actual
search values too. It does not claim a manual visual GUI acceptance.
Find preloads the whole editor selection or reports failure and retains the
previous query. Search input, replacement and Backspace preserve full scalars.

0.85.44: Rebuilt with SDK0.64.57 and the shared R4STD Unicode17.0.0
extended grapheme editing boundaries. Byte offsets, scalar font advances
and grapheme clusters are distinct; no shaping or BiDi support is implied.
