# 321Doit Local MCP Server

`321DoitMCP` exposes local, structured filmmaking tools over the standard MCP
stdio transport. It does not make network requests and cannot access paths
outside roots explicitly allowed when it starts.

The server currently exposes 25 tools:

- project discovery, creation, metadata updates, move-to-Trash, and canonical
  project snapshots;
- Living Storyboard read, analysis, guarded proposal/preview/apply, complete
  structured scene writing, and session undo;
- Production Planning read, confirmed shooting-day/call-sheet writing, and
  JSON/HTML call-sheet export;
- Rapid Script Log read, confirmed Take recording, and JSON/CSV report export;
- Turbo Offload preflight plus confirmed background copy, checksum verification,
  resume, reports, status polling, and cancellation;
- Media Conversion probe/preflight plus confirmed background conversion,
  post-conversion verification, JSON reports, status polling, and cancellation.

## Start

The release build embeds the executable here:

```text
/Applications/321Doit.app/Contents/Helpers/321DoitMCP
```

Pass one or more project/media roots:

```text
/Applications/321Doit.app/Contents/Helpers/321DoitMCP \
  --allow-root "/Volumes/Production" \
  --allow-root "$HOME/Movies"
```

`DOIT_MCP_ALLOWED_ROOTS` may also contain colon-separated roots. An empty root
list is valid for discovery but all path tools refuse access.

## Codex configuration

Add a trusted-repository MCP server entry to `.codex/config.toml`:

```toml
[mcp_servers.321doit]
command = "/Applications/321Doit.app/Contents/Helpers/321DoitMCP"
args = ["--allow-root", "/path/to/projects-and-media"]
```

Restart or open a new Codex task after changing MCP configuration.

## OpenCode configuration

OpenCode uses the same stdio MCP transport. Add this server to the project's
`opencode.jsonc` (or your global OpenCode config):

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "321doit": {
      "type": "local",
      "command": [
        "/Applications/321Doit.app/Contents/Helpers/321DoitMCP",
        "--allow-root",
        "/path/to/projects-and-media"
      ],
      "enabled": true,
      "timeout": 10000
    }
  },
  "permission": {
    "321doit_project_create": "ask",
    "321doit_project_update_metadata": "ask",
    "321doit_project_move_to_trash": "ask",
    "321doit_production_plan_upsert_call_sheet": "ask",
    "321doit_production_plan_export_call_sheet": "ask",
    "321doit_script_log_record_take": "ask",
    "321doit_script_log_export_report": "ask",
    "321doit_storyboard_apply_patch": "ask",
    "321doit_storyboard_undo_last_agent_change": "ask",
    "321doit_storyboard_write_scene": "ask",
    "321doit_offload_start": "ask",
    "321doit_media_conversion_start": "ask",
    "321doit_task_cancel": "ask"
  }
}
```

The same configuration is available as
[`opencode.example.jsonc`](opencode.example.jsonc). Run `opencode mcp list`
from the configured workspace to verify that `321doit` is connected.

OpenCode allows MCP tools without prompting by default, so keep the write and
execution permissions above set to `ask`. Do not start OpenCode with `--auto`
if you want these prompts to remain manual. Read-only 321Doit tools can
continue to run without approval.

## Agent workflows

### Manage projects

1. Call `workspace_list_projects` to inspect real projects under authorized roots.
2. Use `project_create` with an authorized parent folder; it never overwrites an
   existing package.
3. Use `project_update_metadata` for project and principal crew names without
   replacing production, script-log, or storyboard data.
4. Use `project_move_to_trash` only after showing the exact package path and
   obtaining confirmation. The package is moved to macOS Trash rather than
   permanently deleted.

### Offload a camera card

1. Call `offload_preflight` with the source card and one to three destinations.
2. Show the user the source, destinations, size, output folder, checksum, and
   blocking issues.
3. After confirmation, call `offload_start` with project/card/operator metadata
   and a stable idempotency key.
4. Poll `task_get_status` with the returned `task_id`.
5. On completion, use `result.targets[].output_path`,
   `reports_directory`, and `report_paths` (MHL/PDF/CSV/JSON/TXT/checksum).

Offload reports live inside each completed package's `REPORTS` directory
(`03_REPORTS` for legacy layouts).

### Convert media

1. Call `media_conversion_preflight` for the chosen recipe.
2. After confirmation, call `media_conversion_start`.
3. Poll `task_get_status`.
4. Read every `result.outputs[]` entry for the verified `output_path` and
   `report_path`.

Each conversion report is written beside the output under
`.321doit/conversion/<task-id>.json`.

### Write production data

- Use `production_plan_upsert_call_sheet` to create or update tomorrow's or any
  future shooting day, then `production_plan_export_call_sheet` for JSON/HTML.
- Use `script_log_record_take` to append on-set Take data, then
  `script_log_export_report` for JSON/CSV.
- Use `storyboard_write_scene` to write a complete structured scene, or use the
  proposal/preview/apply tools for a selective change to an existing scene.

Project call-sheet and script-log exports are placed under
`<project>.321doit/_321Doit/reports`.

## Safety contract

- Project writes cover project creation and metadata, storyboard scenes,
  shooting-day/call-sheet data, and script-log Takes.
- Project removal means a confirmed move to macOS Trash; no MCP tool performs
  permanent project deletion.
- Offload and conversion execution run only after preflight and confirmation.
- Suggest mode is read-only at the domain boundary.
- Every execution/write tool requires a caller-stable idempotency key; primary
  content writes and long-running jobs also require explicit confirmation.
- In OpenCode, the example permission rules make these calls prompt with
  `once`, `always`, or `reject`.
- Selective storyboard apply additionally requires explicit operation IDs and
  the current storyboard revision.
- High-risk operations are not selected by default.
- Writes use the existing validated repository, atomic replacement, local
  backups, field locks, audit logs, and persistent idempotency receipts.
- Offload never deletes or formats source media. Conversion publishes output
  only after verification. Cancellation never deletes already completed output.
