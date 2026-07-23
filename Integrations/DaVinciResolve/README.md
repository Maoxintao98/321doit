# 321Doit Bridge for DaVinci Resolve

An Electron **Workflow Integration** for DaVinci Resolve Studio that imports
verified 321Doit offload tasks into the current Resolve project and optionally
injects on-set script-log (`.321log`) metadata. The production entry is under
Workspace → Workflow Integrations; the earlier Utility Script is removed on
upgrade.

## Requirements

- DaVinci Resolve Studio (scripting enabled)
- Python >= 3.6 (python.org or Homebrew)
- Preferences → System → General → **External scripting using = Local**
  (or Network)

## Install

Double-click **`install.command`**. macOS asks for administrator approval
because Resolve only scans the system-wide Workflow Integration Plugins
directory. Then restart Resolve and open
**Workspace → Workflow Integrations → 321Doit**. The installer removes the
earlier Utility Script entry so there is only one production command.

To remove, double-click **`uninstall.command`**; import-result audit data is
preserved.

### Manual install

Copy the assembled `com.321doit.resolve.workflow` folder into
`/Library/Application Support/Blackmagic Design/DaVinci Resolve/Workflow Integration Plugins/`.
The folder must include the Resolve 21 `WorkflowIntegration.node` shipped with
the local Developer examples and `backend/bridge/`.

## Inputs

1. **Required — offload task.** Select either `<task>/.321doit/task.json` or
   the task root directory. The manifest must declare
   `schema = "com.321doit.offload-task"` and `schemaVersion = 2`; anything
   else stops the import.
2. **Optional — script log.** Select a `.321log`, or leave blank to
   auto-search under the task root (`.321doit/`, `.321doit/script-log/`,
   `_ScriptLog/`).

## Workflow

1. Select the task (and optionally the script log). **Nothing changes yet.**
2. Press **Preflight only**. The summary shows counts (verified, missing,
   matched, conflicts, duplicates). The **Execute Import** button is enabled
   only after a non-blocking preflight.
3. Press **Execute Import**.

If the task has `failedResults > 0` or errors, import is blocked by default.
Tick **Allow import of verified part only** to import just the verified files.

## What it does (and does not) do

**Does:**
- Import only files with `copied == true && verified == true`, AND only real
  media extensions (`.mov/.mp4/.mxf/.r3d/.braw/...`). XML, checksum, and
  camera sidecars are skipped.
- Create bins: `321Doit / <project or Independent> / <date> / <camera> / <card>`;
  multi-camera tasks route each clip into its matched A/B/C camera bin.
- Resolve media by `task_root/relativePath`, then `MEDIA/<card>/`, then a
  verified `outputPath` — so changed mount points still work.
- Reject directory traversal (`..`, absolute injection, symlink egress).
- Write Scene/Shot/Take/Camera/Comments/Keywords via **`SetMetadata`**
  (never `SetClipProperty`), with field-support detection. The Camera label
  is chosen per clip (matching camera record), so B-camera clips aren't
  labelled as A.
- Write identity fields via `SetThirdPartyMetadata`
  (`321Doit Media Key = taskID + relativePath + sourceHash`, Task ID, Take ID,
  Relative Path, Source Hash, Project ID).
- Map status → clip color & flag: good=Green/OK, hold=Yellow/KP,
  ng=Red/NG, circle take=Green flag + "Circle Take".
- Idempotent re-runs: scans the **entire** media pool (not just the 321Doit
  bin) for duplicates by media key and resolved path; no duplicate clips;
  backfills metadata by filling **only empty fields** (user edits preserved);
  never clears user-added colors/flags/keywords.
- Reports honest status: verified-but-missing media → `partial` (or
  `failed` when nothing importable is on disk).

**Does NOT:**
- Create or overwrite Resolve projects, timelines, or bins destructively.
- Modify project frame rate, resolution, color management, or start TC.
- Copy/move/rename source media.
- Modify `task.json`, generate `05_HANDOFF`, or build any "post package".
- Guess proxy files or apply LUTs (MVP — no explicit proxy mapping in task v2).
- Network/telemetry, `eval`, or shell-concatenated user paths.

## Result protocol

Results are written atomically to
`<task>/.321doit/integrations/resolve/<taskID>.json` (read-only task disk →
falls back to `~/Library/Application Support/321Doit/ResolveBridge/results/`),
schema `com.321doit.resolve-import-result` v1. stdout also emits:

```
321DOIT_RESULT_BEGIN
{...json...}
321DOIT_RESULT_END
```

## Known limitations

- The file/folder picker uses the macOS-native AppleScript `choose`
  dialogs (via `osascript`, standard library) since UIManager has no
  documented cross-version file dialog; you can also paste a path into the
  text field.
- Metadata field names (Scene/Shot/Take/Camera/Comments/Keywords/Good) are
  probed per clip via `GetMetadata()`; unsupported fields become warnings.
- Proxy linking (`LinkProxyMedia`) is disabled until the manifest carries an
  explicit `proxyRelativePath`/`proxyHash`.
- The Workflow Integration panel supports Chinese and English, follows the
  system language on first launch, and remembers the in-panel language switch.

## Tests

```
python3 -m unittest discover -s tests
```

47 tests cover manifest validation (schema/v1/v2/version), the 5 matching
rules incl. card-joint disambiguation and conflicts, path resolution,
mount-point changes, missing media (partial/failed status), non-media
sidecar filtering, partial import, Unicode paths, traversal blocking,
Resolve API failures, partial results, dry-run, multi-camera camera-label
selection, duplicate suppression across all bins, metadata backfill that
preserves user edits, and Take-ID writing.
