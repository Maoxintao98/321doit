import Foundation

private struct PendingStoryboardPatch {
    var projectURL: URL
    var patch: StoryboardPatch
    var defaultAcceptedOperationIDs: Set<UUID>
}

private struct StoryboardUndoEntry {
    var projectURL: URL
    var patchID: UUID
    var before: StoryboardDocument
    var appliedRevision: Int
}

final class DoitMCPServer {
    static let version = "0.2.0"
    static let protocolVersion = "2025-11-25"

    private let allowedRoots: [URL]
    private let executionCoordinator: MCPExecutionCoordinator
    private var pendingPatches: [String: PendingStoryboardPatch] = [:]
    private var undoEntries: [String: [StoryboardUndoEntry]] = [:]

    init(
        allowedRoots: [URL],
        executionCoordinator: MCPExecutionCoordinator = MCPExecutionCoordinator()
    ) {
        var seen = Set<String>()
        self.allowedRoots = allowedRoots.compactMap { root in
            let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(resolved.path).inserted else { return nil }
            return resolved
        }
        self.executionCoordinator = executionCoordinator
    }

    func initializeResult(requestedVersion: String?) -> JSONObject {
        let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
        let negotiated = requestedVersion.flatMap { supported.contains($0) ? $0 : nil }
            ?? Self.protocolVersion
        return [
            "protocolVersion": negotiated,
            "capabilities": [
                "tools": ["listChanged": false],
                "resources": ["subscribe": false, "listChanged": false]
            ],
            "serverInfo": [
                "name": "com.321doit.mcp",
                "title": "321Doit Local Filmmaking Tools",
                "version": Self.version
            ],
            "instructions": """
            321Doit is local-first. Every path must be inside a root explicitly allowed when the server starts. \
            Read and preflight before writes. Executing tools require an idempotency key and an MCP client \
            confirmation from the user. Long-running offload and conversion jobs return task IDs; poll task_get_status \
            for progress, outputs, and report paths. High-risk storyboard patch operations are not selected by default.
            """
        ]
    }

    func toolDefinitions() -> [JSONObject] {
        [
            tool(
                "workspace_list_projects",
                title: "List 321Doit Projects",
                description: "Find .321doit project packages below the explicitly allowed local roots.",
                properties: [
                    "max_depth": integerSchema("Maximum directory depth to scan, from 1 through 8.", defaultValue: 4)
                ],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "project_create",
                title: "Create a 321Doit Project",
                description: "Create a new project package inside an explicitly allowed project-library folder. This never overwrites an existing project.",
                properties: [
                    "root_path": stringSchema("Existing authorized parent folder where the project package will be created."),
                    "name": stringSchema("Project name."),
                    "production_name": stringSchema("Optional production title."),
                    "director": stringSchema("Optional director name."),
                    "dp": stringSchema("Optional director of photography."),
                    "dit_name": stringSchema("Optional DIT name."),
                    "script_supervisor": stringSchema("Optional script supervisor name."),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed the project name and destination."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this project creation.")
                ],
                required: ["root_path", "name", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "project_update_metadata",
                title: "Update 321Doit Project Information",
                description: "Update selected project-level names and crew fields while preserving all production, script-log, and storyboard data.",
                properties: [
                    "project_path": projectPathSchema(),
                    "name": stringSchema("Optional new project name stored in project metadata; the package itself is not renamed."),
                    "production_name": stringSchema("Optional production title."),
                    "director": stringSchema("Optional director name."),
                    "dp": stringSchema("Optional director of photography."),
                    "dit_name": stringSchema("Optional DIT name."),
                    "script_supervisor": stringSchema("Optional script supervisor name."),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed the fields that will change."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this metadata update.")
                ],
                required: ["project_path", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "project_move_to_trash",
                title: "Move a 321Doit Project to Trash",
                description: "Move a complete project package to the macOS Trash. This never permanently deletes files and always requires explicit confirmation.",
                properties: [
                    "project_path": projectPathSchema(),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed the exact project path and warned that the project will close."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this trash operation.")
                ],
                required: ["project_path", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: true,
                idempotent: true
            ),
            pathTool(
                "project_read_snapshot",
                title: "Read Project Snapshot",
                description: "Read the canonical local project snapshot, including production planning and script-log data."
            ),
            pathTool(
                "production_plan_read_snapshot",
                title: "Read Production Plan",
                description: "Read shooting days, call sheets, cast, departments, locations, and camera planning from a project."
            ),
            tool(
                "production_plan_upsert_call_sheet",
                title: "Create or Update a Shooting Day and Call Sheet",
                description: "Write a confirmed shooting day and call-sheet draft into the project. Existing values are preserved when optional fields are omitted.",
                properties: [
                    "project_path": projectPathSchema(),
                    "date": stringSchema("Shooting date in YYYY-MM-DD format."),
                    "day_type": enumSchema(
                        ShootingDayType.allCases.map(\.rawValue),
                        description: "Shooting-day type.",
                        defaultValue: ShootingDayType.shooting.rawValue
                    ),
                    "title": stringSchema("Call-sheet title."),
                    "call_time": stringSchema("Crew call time, for example 06:30."),
                    "estimated_start_time": stringSchema("Estimated camera start time."),
                    "estimated_wrap_time": stringSchema("Estimated wrap time."),
                    "main_location": stringSchema("Primary shooting location."),
                    "general_note": stringSchema("Instructions or plan for the day."),
                    "timeline": [
                        "type": "array",
                        "description": "Optional complete timeline. Each item may include time, title, category, department, key_milestone, and note.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "time": stringSchema("Timeline time."),
                                "title": stringSchema("Timeline event title."),
                                "category": enumSchema(
                                    TimelineCategory.allCases.map(\.rawValue),
                                    description: "Timeline category.",
                                    defaultValue: TimelineCategory.custom.rawValue
                                ),
                                "department": stringSchema("Related department."),
                                "key_milestone": booleanSchema("Whether this is a key milestone."),
                                "note": stringSchema("Timeline note.")
                            ],
                            "required": ["time", "title"],
                            "additionalProperties": false
                        ]
                    ] as JSONObject,
                    "confirmed_by_user": booleanSchema("Must be true after the client obtained explicit user confirmation."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact logical write.")
                ],
                required: ["project_path", "date", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "production_plan_export_call_sheet",
                title: "Export a Call Sheet",
                description: "Export an existing shooting day's call sheet into the project's reports directory and return the exact path.",
                properties: [
                    "project_path": projectPathSchema(),
                    "date": stringSchema("Shooting date in YYYY-MM-DD format."),
                    "format": enumSchema(["json", "html"], description: "Export format.", defaultValue: "html"),
                    "idempotency_key": stringSchema("Caller-stable key for this report write.")
                ],
                required: ["project_path", "date", "format", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            pathTool(
                "script_log_read_snapshot",
                title: "Read Script Log",
                description: "Read shooting days, scenes, shots, takes, multi-camera records, tags, and notes from a project."
            ),
            tool(
                "script_log_record_take",
                title: "Record a Script Take",
                description: "Append a confirmed take to a shooting day, creating the day, scene, or shot when needed.",
                properties: [
                    "project_path": projectPathSchema(),
                    "date": stringSchema("Shooting date in YYYY-MM-DD format."),
                    "scene_number": stringSchema("Scene number."),
                    "shot_number": stringSchema("Shot number."),
                    "take_number": integerSchema("Take number. Use 0 to choose the next number automatically.", defaultValue: 0),
                    "camera_label": stringSchema("Camera label.", defaultValue: "A"),
                    "status": enumSchema(
                        TakeStatus.selectable.map(\.rawValue),
                        description: "Take status.",
                        defaultValue: TakeStatus.hold.rawValue
                    ),
                    "circle_take": booleanSchema("Whether this is a circle take."),
                    "notes": stringSchema("General take notes."),
                    "quick_tags": arraySchema(items: stringSchema("Quick tag."), description: "Optional quick tags."),
                    "clip_name": stringSchema("Optional recorded clip name."),
                    "card_name": stringSchema("Optional camera-card name."),
                    "tc_in": stringSchema("Optional timecode in."),
                    "tc_out": stringSchema("Optional timecode out."),
                    "confirmed_by_user": booleanSchema("Must be true after the client obtained explicit user confirmation."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact logical write.")
                ],
                required: ["project_path", "date", "scene_number", "shot_number", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "script_log_export_report",
                title: "Export Script Log Report",
                description: "Export the current script log to the project's reports directory and return the exact path.",
                properties: [
                    "project_path": projectPathSchema(),
                    "format": enumSchema(["json", "csv"], description: "Report format.", defaultValue: "json"),
                    "idempotency_key": stringSchema("Caller-stable key for this report write.")
                ],
                required: ["project_path", "format", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            pathTool(
                "storyboard_read_snapshot",
                title: "Read Storyboard",
                description: "Read the current storyboard document with its revision, locks, scenes, shots, and production links."
            ),
            tool(
                "storyboard_analyze",
                title: "Analyze Storyboard",
                description: "Run 321Doit's deterministic timing, continuity, production, and data checks without changing the project.",
                properties: [
                    "project_path": projectPathSchema(),
                    "scene_id": stringSchema("Optional storyboard scene UUID. Omit to analyze the full storyboard.")
                ],
                required: ["project_path"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "storyboard_propose_patch",
                title: "Propose Storyboard Patch",
                description: "Create and simulate a guarded storyboard patch from a clear instruction. This never writes the project. High-risk operations are excluded from the default accepted set.",
                properties: [
                    "project_path": projectPathSchema(),
                    "scene_id": stringSchema("Storyboard scene UUID."),
                    "instruction": stringSchema("Concrete instruction including desired shot count, duration, emotion, or production constraints."),
                    "agent_name": stringSchema("Name recorded in the proposal.", defaultValue: "External MCP Agent"),
                    "model": stringSchema("Model or planner identifier recorded in the proposal.", defaultValue: "external")
                ],
                required: ["project_path", "scene_id", "instruction"],
                readOnly: true,
                idempotent: false
            ),
            tool(
                "storyboard_preview_patch",
                title: "Preview Storyboard Patch",
                description: "Re-simulate a proposed patch against the current project revision using an explicit subset of operation IDs.",
                properties: [
                    "patch_handle": stringSchema("Opaque handle returned by storyboard_propose_patch."),
                    "accepted_operation_ids": arraySchema(
                        items: stringSchema("Patch operation UUID."),
                        description: "Operation UUIDs to simulate. Omit to use the safe default set."
                    )
                ],
                required: ["patch_handle"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "storyboard_apply_patch",
                title: "Apply Confirmed Storyboard Patch",
                description: "Apply a previewed patch atomically. The client must show the proposed operations to the user and obtain explicit confirmation immediately before this call.",
                properties: [
                    "patch_handle": stringSchema("Opaque handle returned by storyboard_propose_patch."),
                    "accepted_operation_ids": arraySchema(
                        items: stringSchema("Patch operation UUID."),
                        description: "Explicit operation UUIDs approved by the user."
                    ),
                    "confirmed_by_user": booleanSchema("Must be true only after the MCP client obtained explicit user confirmation."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact logical write.")
                ],
                required: ["patch_handle", "accepted_operation_ids", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: true,
                idempotent: true
            ),
            tool(
                "storyboard_undo_last_agent_change",
                title: "Undo Last MCP Storyboard Change",
                description: "Undo the most recent storyboard change applied by this MCP session if the project revision has not changed since.",
                properties: [
                    "project_path": projectPathSchema(),
                    "confirmed_by_user": booleanSchema("Must be true after explicit user confirmation."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact logical undo.")
                ],
                required: ["project_path", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: true,
                idempotent: true
            ),
            tool(
                "storyboard_write_scene",
                title: "Create a Basic Storyboard Scene",
                description: "Create a new basic storyboard scene from structured Agent output. It never replaces an existing scene; use the guarded patch workflow to modify existing scenes so canvas and production data are preserved.",
                properties: [
                    "project_path": projectPathSchema(),
                    "scene_number": stringSchema("Scene number."),
                    "title": stringSchema("Scene title."),
                    "synopsis": stringSchema("Scene synopsis."),
                    "location": stringSchema("Scene location."),
                    "time_of_day": stringSchema("Scene time of day."),
                    "director_intent": stringSchema("Director intent."),
                    "shots": [
                        "type": "array",
                        "description": "Complete ordered shot list.",
                        "items": [
                            "type": "object",
                            "properties": [
                                "shot_number": stringSchema("Shot number."),
                                "description": stringSchema("Shot content and action."),
                                "duration_seconds": ["type": "number", "minimum": 0.1],
                                "shot_size": enumSchema(StoryboardShotSize.allCases.map(\.rawValue), description: "Shot size.", defaultValue: StoryboardShotSize.medium.rawValue),
                                "camera_angle": enumSchema(StoryboardCameraAngle.allCases.map(\.rawValue), description: "Camera angle.", defaultValue: StoryboardCameraAngle.eyeLevel.rawValue),
                                "camera_motion": enumSchema(StoryboardCameraMotionKind.allCases.map(\.rawValue), description: "Primary camera movement.", defaultValue: StoryboardCameraMotionKind.locked.rawValue),
                                "lens": stringSchema("Lens or focal-length note."),
                                "sound": stringSchema("Sound or dialogue description."),
                                "notes": stringSchema("Production notes.")
                            ],
                            "required": ["shot_number", "description"],
                            "additionalProperties": false
                        ]
                    ] as JSONObject,
                    "agent_name": stringSchema("Agent name recorded in the audit log.", defaultValue: "External MCP Agent"),
                    "model": stringSchema("Model identifier recorded in the audit log.", defaultValue: "external"),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed the complete scene and obtained confirmation."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact logical write.")
                ],
                required: ["project_path", "scene_number", "shots", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: true,
                idempotent: true
            ),
            tool(
                "offload_preflight",
                title: "Inspect Camera Media for Offload",
                description: "Read-only camera-card inspection: detect card structure, count files, total bytes, video files, and inspect target volume capacity. This never starts a copy.",
                properties: [
                    "source_path": stringSchema("Existing source card or folder inside an allowed root."),
                    "target_paths": arraySchema(
                        items: stringSchema("Existing target directory inside an allowed root."),
                        description: "Optional target directories to inspect."
                    ),
                    "max_files": integerSchema("Maximum entries to scan before returning a truncated result.", defaultValue: 100000)
                ],
                required: ["source_path"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "offload_start",
                title: "Start Verified Camera-Card Offload",
                description: "Start a confirmed background offload with checksum verification and reports. Call offload_preflight first, then poll task_get_status for output and report paths.",
                properties: [
                    "source_path": stringSchema("Camera-card or source directory inside an allowed root."),
                    "target_paths": arraySchema(items: stringSchema("Writable target directory inside an allowed root."), description: "One to three destinations."),
                    "project_name": stringSchema("Project name."),
                    "card_number": stringSchema("Card or reel number."),
                    "operator_name": stringSchema("DIT/operator name."),
                    "camera": stringSchema("Camera label."),
                    "location": stringSchema("Shooting location."),
                    "notes": stringSchema("Offload notes."),
                    "checksum": enumSchema(ChecksumAlgorithm.allCases.map(\.rawValue), description: "Verification checksum.", defaultValue: ChecksumAlgorithm.xxhash64.rawValue),
                    "strict_resume": booleanSchema("Re-hash existing destination files before resuming."),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed source, destinations, output folder, and verification plan."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this exact offload.")
                ],
                required: ["source_path", "target_paths", "project_name", "card_number", "operator_name", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "media_probe",
                title: "Probe Media",
                description: "Read media streams, duration, dimensions, frame rate, codecs, audio, timecode, and color metadata with the local ffprobe.",
                properties: [
                    "media_path": stringSchema("Existing media file inside an allowed root.")
                ],
                required: ["media_path"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "media_conversion_preflight",
                title: "Check Media Conversion Compatibility",
                description: "Probe one local media file and evaluate a rewrap, video-transcode, or lossless-audio recipe without creating output.",
                properties: [
                    "media_path": stringSchema("Existing media file inside an allowed root."),
                    "mode": enumSchema(
                        ["rewrap", "transcode", "losslessAudio"],
                        description: "Conversion mode."
                    ),
                    "target_container": enumSchema(
                        MediaContainer.allCases.map(\.rawValue),
                        description: "Target container."
                    ),
                    "video_codec": enumSchema(
                        MediaVideoCodec.allCases.map(\.rawValue),
                        description: "Video codec used only for transcode mode.",
                        defaultValue: MediaTranscodeSettings.default.videoCodec.rawValue
                    ),
                    "audio_codec": enumSchema(
                        MediaAudioCodec.allCases.map(\.rawValue),
                        description: "Audio codec used only for transcode mode.",
                        defaultValue: MediaTranscodeSettings.default.audioCodec.rawValue
                    ),
                    "quality": enumSchema(
                        MediaTranscodeQuality.allCases.map(\.rawValue),
                        description: "Transcode quality.",
                        defaultValue: MediaTranscodeSettings.default.quality.rawValue
                    ),
                    "scale": enumSchema(
                        MediaOutputScale.allCases.map(\.rawValue),
                        description: "Output scale.",
                        defaultValue: MediaTranscodeSettings.default.scale.rawValue
                    ),
                    "frame_rate": enumSchema(
                        MediaOutputFrameRate.allCases.map(\.rawValue),
                        description: "Output frame rate.",
                        defaultValue: MediaTranscodeSettings.default.frameRate.rawValue
                    )
                ],
                required: ["media_path", "mode", "target_container"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "media_conversion_start",
                title: "Start Verified Media Conversion",
                description: "Start a confirmed background conversion for one or more media files. Outputs are verified before publication and each receives a JSON report.",
                properties: [
                    "media_paths": arraySchema(items: stringSchema("Existing media file inside an allowed root."), description: "One or more source media files."),
                    "destination_path": stringSchema("Writable output directory inside an allowed root."),
                    "mode": enumSchema(MediaConversionMode.allCases.map(\.rawValue), description: "Conversion mode."),
                    "target_container": enumSchema(MediaContainer.allCases.map(\.rawValue), description: "Target container."),
                    "video_codec": enumSchema(MediaVideoCodec.allCases.map(\.rawValue), description: "Video codec for transcode mode.", defaultValue: MediaTranscodeSettings.default.videoCodec.rawValue),
                    "audio_codec": enumSchema(MediaAudioCodec.allCases.map(\.rawValue), description: "Audio codec for transcode mode.", defaultValue: MediaTranscodeSettings.default.audioCodec.rawValue),
                    "quality": enumSchema(MediaTranscodeQuality.allCases.map(\.rawValue), description: "Transcode quality.", defaultValue: MediaTranscodeSettings.default.quality.rawValue),
                    "scale": enumSchema(MediaOutputScale.allCases.map(\.rawValue), description: "Output scale.", defaultValue: MediaTranscodeSettings.default.scale.rawValue),
                    "frame_rate": enumSchema(MediaOutputFrameRate.allCases.map(\.rawValue), description: "Output frame rate.", defaultValue: MediaTranscodeSettings.default.frameRate.rawValue),
                    "confirmed_by_user": booleanSchema("Must be true after the client showed the conversion recipe and destination."),
                    "idempotency_key": stringSchema("Caller-stable unique key for this conversion queue.")
                ],
                required: ["media_paths", "destination_path", "mode", "target_container", "confirmed_by_user", "idempotency_key"],
                readOnly: false,
                destructive: false,
                idempotent: true
            ),
            tool(
                "task_get_status",
                title: "Get 321Doit Task Status",
                description: "Read progress, completion state, output paths, report paths, or errors for an offload or media-conversion task.",
                properties: ["task_id": stringSchema("Task ID returned by a start tool.")],
                required: ["task_id"],
                readOnly: true,
                idempotent: true
            ),
            tool(
                "task_cancel",
                title: "Cancel a 321Doit Task",
                description: "Request cancellation of a running offload or media-conversion task. Completed outputs are never deleted by this call.",
                properties: [
                    "task_id": stringSchema("Task ID returned by a start tool."),
                    "confirmed_by_user": booleanSchema("Must be true after explicit user confirmation.")
                ],
                required: ["task_id", "confirmed_by_user"],
                readOnly: false,
                destructive: false,
                idempotent: true
            )
        ]
    }

    func callTool(name: String, arguments: JSONObject) -> JSONObject {
        do {
            let structured: JSONObject
            switch name {
            case "workspace_list_projects":
                structured = try listProjects(arguments)
            case "project_create":
                structured = try createProject(arguments)
            case "project_update_metadata":
                structured = try updateProjectMetadata(arguments)
            case "project_move_to_trash":
                structured = try moveProjectToTrash(arguments)
            case "project_read_snapshot":
                structured = try readProject(arguments, scope: "project")
            case "production_plan_read_snapshot":
                structured = try readProject(arguments, scope: "production_plan")
            case "production_plan_upsert_call_sheet":
                structured = try upsertCallSheet(arguments)
            case "production_plan_export_call_sheet":
                structured = try exportCallSheet(arguments)
            case "script_log_read_snapshot":
                structured = try readProject(arguments, scope: "script_log")
            case "script_log_record_take":
                structured = try recordScriptTake(arguments)
            case "script_log_export_report":
                structured = try exportScriptLog(arguments)
            case "storyboard_read_snapshot":
                structured = try readStoryboard(arguments)
            case "storyboard_analyze":
                structured = try analyzeStoryboard(arguments)
            case "storyboard_propose_patch":
                structured = try proposeStoryboardPatch(arguments)
            case "storyboard_preview_patch":
                structured = try previewStoryboardPatch(arguments)
            case "storyboard_apply_patch":
                structured = try applyStoryboardPatch(arguments)
            case "storyboard_undo_last_agent_change":
                structured = try undoStoryboardChange(arguments)
            case "storyboard_write_scene":
                structured = try writeStoryboardScene(arguments)
            case "offload_preflight":
                structured = try offloadPreflight(arguments)
            case "offload_start":
                structured = try startOffload(arguments)
            case "media_probe":
                structured = try probeMedia(arguments)
            case "media_conversion_preflight":
                structured = try conversionPreflight(arguments)
            case "media_conversion_start":
                structured = try startMediaConversion(arguments)
            case "task_get_status":
                structured = try taskStatus(arguments)
            case "task_cancel":
                structured = try cancelTask(arguments)
            default:
                throw MCPServerError.notFound("Unknown 321Doit tool: \(name)")
            }
            return toolResult(structured, isError: false)
        } catch {
            return toolResult(
                [
                    "error": true,
                    "message": error.localizedDescription,
                    "tool": name
                ],
                isError: true
            )
        }
    }

    func resourceDefinitions() -> [JSONObject] {
        var resources: [JSONObject] = [
            [
                "uri": "321doit://manifest",
                "name": "321Doit MCP Manifest",
                "title": "321Doit AI Tool Manifest",
                "description": "Local server version, allowed roots, and safety contract.",
                "mimeType": "application/json"
            ]
        ]
        if let projects = try? discoverProjects(maxDepth: 4) {
            for project in projects {
                let token = Self.pathToken(project.path)
                resources.append([
                    "uri": "321doit://project/\(token)/snapshot",
                    "name": project.lastPathComponent,
                    "title": "Project Snapshot · \(project.deletingPathExtension().lastPathComponent)",
                    "description": "Canonical local 321Doit project snapshot.",
                    "mimeType": "application/json"
                ])
                let storyboardURL = StoryboardRepository.storyboardJSONURL(for: project)
                if FileManager.default.fileExists(atPath: storyboardURL.path) {
                    resources.append([
                        "uri": "321doit://project/\(token)/storyboard",
                        "name": "\(project.lastPathComponent) Storyboard",
                        "title": "Storyboard · \(project.deletingPathExtension().lastPathComponent)",
                        "description": "Current local storyboard document.",
                        "mimeType": "application/json"
                    ])
                }
            }
        }
        return resources
    }

    func readResource(uri: String) throws -> JSONObject {
        if uri == "321doit://manifest" {
            let value: JSONObject = [
                "uri": uri,
                "mimeType": "application/json",
                "text": try MCPJSON.compactString(manifest())
            ]
            return value
        }

        let prefix = "321doit://project/"
        guard uri.hasPrefix(prefix) else {
            throw MCPServerError.notFound("Unknown 321Doit resource URI.")
        }
        let remainder = String(uri.dropFirst(prefix.count))
        let components = remainder.split(separator: "/", maxSplits: 1).map(String.init)
        guard components.count == 2,
              let path = Self.path(fromToken: components[0]) else {
            throw MCPServerError.invalidArguments("Invalid 321Doit project resource URI.")
        }
        let projectURL = try validatedProject(path)
        let object: Any
        switch components[1] {
        case "snapshot":
            object = try MCPJSON.object(from: ProjectRepository.load(from: projectURL))
        case "storyboard":
            object = try MCPJSON.object(from: StoryboardRepository.loadProjectStoryboard(from: projectURL))
        default:
            throw MCPServerError.notFound("Unknown 321Doit project resource.")
        }
        return [
            "uri": uri,
            "mimeType": "application/json",
            "text": try MCPJSON.compactString(object)
        ]
    }

    private func listProjects(_ arguments: JSONObject) throws -> JSONObject {
        let maxDepth = min(max(arguments["max_depth"] as? Int ?? 4, 1), 8)
        let projects = try discoverProjects(maxDepth: maxDepth)
        let summaries = try projects.map { project -> JSONObject in
            let loaded = try ProjectRepository.load(from: project)
            let storyboardURL = StoryboardRepository.storyboardJSONURL(for: project)
            let revision = (try? StoryboardRepository.loadProjectStoryboard(from: project).revision)
            return [
                "path": project.path,
                "name": loaded.name,
                "project_id": loaded.id.uuidString.lowercased(),
                "shooting_day_count": loaded.shootingDays.count,
                "has_storyboard": FileManager.default.fileExists(atPath: storyboardURL.path),
                "storyboard_revision": revision ?? NSNull()
            ]
        }
        return [
            "projects": summaries,
            "count": summaries.count,
            "allowed_roots": allowedRoots.map(\.path)
        ]
    }

    private func createProject(_ arguments: JSONObject) throws -> JSONObject {
        let idempotencyKey = try confirmedWriteKey(arguments)
        guard let rootPath = nonemptyString(arguments["root_path"]),
              let name = nonemptyString(arguments["name"]) else {
            throw MCPServerError.invalidArguments("root_path and a non-empty project name are required.")
        }
        let rootURL = try validatedExistingURL(rootPath, requireDirectory: true)
        guard !ProjectRepository.isProjectFolder(rootURL) else {
            throw MCPServerError.invalidArguments("root_path must be a project-library folder, not an existing project package.")
        }
        let projectURL = ProjectRepository.projectPackageURL(in: rootURL, projectName: name)
            .standardizedFileURL
        guard allowedRoots.contains(where: { Self.contains(projectURL, in: $0) }) else {
            throw MCPServerError.forbidden("The new project path is outside the explicitly allowed local roots.")
        }
        if let receipt = try existingWorkspaceReceipt(
            containerURL: rootURL,
            tool: "project_create",
            key: idempotencyKey,
            subject: projectURL.path
        ) {
            return receipt
        }
        guard !FileManager.default.fileExists(atPath: projectURL.path) else {
            throw MCPServerError.conflict("A file or project already exists at: \(projectURL.path)")
        }

        var project = Project(name: name)
        if let value = arguments["production_name"] as? String { project.productionName = value }
        if let value = arguments["director"] as? String { project.director = value }
        if let value = arguments["dp"] as? String { project.dp = value }
        if let value = arguments["dit_name"] as? String { project.ditName = value }
        if let value = arguments["script_supervisor"] as? String { project.scriptSupervisor = value }

        do {
            try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: false)
            try ProjectRepository.save(project, to: projectURL)
        } catch {
            try? FileManager.default.removeItem(at: projectURL)
            throw error
        }

        let result: JSONObject = [
            "created": true,
            "project_path": projectURL.path,
            "project_id": project.id.uuidString.lowercased(),
            "name": project.name,
            "canonical_project_path": ProjectRepository.projectStateJSONURL(for: projectURL).path,
            "idempotency_key": idempotencyKey
        ]
        try storeWorkspaceReceipt(
            containerURL: rootURL,
            tool: "project_create",
            key: idempotencyKey,
            subject: projectURL.path,
            result: result
        )
        return result
    }

    private func updateProjectMetadata(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let idempotencyKey = try confirmedWriteKey(arguments)
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "project_update_metadata",
            key: idempotencyKey
        ) {
            return receipt
        }

        let editableKeys = ["name", "production_name", "director", "dp", "dit_name", "script_supervisor"]
        let changedKeys = editableKeys.filter { arguments[$0] is String }
        guard !changedKeys.isEmpty else {
            throw MCPServerError.invalidArguments("Provide at least one project metadata field to update.")
        }
        var project = try ProjectRepository.load(from: projectURL)
        if let value = arguments["name"] as? String {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MCPServerError.invalidArguments("Project name must not be empty.")
            }
            project.name = value
        }
        if let value = arguments["production_name"] as? String { project.productionName = value }
        if let value = arguments["director"] as? String { project.director = value }
        if let value = arguments["dp"] as? String { project.dp = value }
        if let value = arguments["dit_name"] as? String { project.ditName = value }
        if let value = arguments["script_supervisor"] as? String { project.scriptSupervisor = value }
        try ProjectRepository.save(project, to: projectURL)

        let result: JSONObject = [
            "updated": true,
            "project_path": projectURL.path,
            "project_id": project.id.uuidString.lowercased(),
            "name": project.name,
            "changed_fields": changedKeys,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "project_update_metadata",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func moveProjectToTrash(_ arguments: JSONObject) throws -> JSONObject {
        let idempotencyKey = try confirmedWriteKey(arguments)
        guard let path = nonemptyString(arguments["project_path"]) else {
            throw MCPServerError.invalidArguments("project_path is required.")
        }
        let candidate = try validatedAllowedPath(path)
        let parent = candidate.deletingLastPathComponent()
        if let receipt = try existingWorkspaceReceipt(
            containerURL: parent,
            tool: "project_move_to_trash",
            key: idempotencyKey,
            subject: candidate.path
        ) {
            return receipt
        }
        let projectURL = try validatedProject(candidate.path)
        let project = try ProjectRepository.load(from: projectURL)
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: projectURL, resultingItemURL: &resultingURL)
        let trashedPath = (resultingURL as URL?)?.path ?? ""
        let result: JSONObject = [
            "trashed": true,
            "project_path": projectURL.path,
            "original_project_path": projectURL.path,
            "trashed_path": trashedPath,
            "project_id": project.id.uuidString.lowercased(),
            "name": project.name,
            "recoverable_from_trash": true,
            "idempotency_key": idempotencyKey
        ]
        try storeWorkspaceReceipt(
            containerURL: parent,
            tool: "project_move_to_trash",
            key: idempotencyKey,
            subject: projectURL.path,
            result: result
        )
        return result
    }

    private func readProject(_ arguments: JSONObject, scope: String) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let project = try ProjectRepository.load(from: projectURL)
        let encoded = try MCPJSON.dictionary(from: project)
        switch scope {
        case "production_plan":
            return [
                "scope": scope,
                "project_path": projectURL.path,
                "project_id": project.id.uuidString.lowercased(),
                "name": project.name,
                "production_name": project.productionName,
                "director": project.director,
                "dp": project.dp,
                "dit_name": project.ditName,
                "principal_cast": encoded["principalCast"] ?? [],
                "department_contacts": encoded["departmentContacts"] ?? [],
                "location_memory": encoded["locationMemory"] ?? [],
                "camera_registry": encoded["cameraRegistry"] ?? [],
                "shooting_days": encoded["shootingDays"] ?? []
            ]
        case "script_log":
            return [
                "scope": scope,
                "project_path": projectURL.path,
                "project_id": project.id.uuidString.lowercased(),
                "name": project.name,
                "script_supervisor": project.scriptSupervisor,
                "shooting_days": encoded["shootingDays"] ?? []
            ]
        default:
            return [
                "scope": scope,
                "project_path": projectURL.path,
                "snapshot": encoded
            ]
        }
    }

    private func upsertCallSheet(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let idempotencyKey = try confirmedWriteKey(arguments)
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "production_plan_upsert_call_sheet",
            key: idempotencyKey
        ) {
            return receipt
        }
        guard let dateText = nonemptyString(arguments["date"]),
              let date = shootingDate(dateText) else {
            throw MCPServerError.invalidArguments("date must use YYYY-MM-DD.")
        }

        var project = try ProjectRepository.load(from: projectURL)
        let calendar = Calendar.current
        let dayIndex: Int
        if let existing = project.shootingDays.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        }) {
            dayIndex = existing
        } else {
            let number = project.shootingDays.count + 1
            let type = ShootingDayType(rawValue: nonemptyString(arguments["day_type"]) ?? "") ?? .shooting
            project.shootingDays.append(ShootingDay(
                date: date,
                label: "Day \(number)",
                scenes: [],
                callSheet: ShootingDayCallSheet(type: type)
            ))
            dayIndex = project.shootingDays.count - 1
        }

        var callSheet = project.shootingDays[dayIndex].callSheet
        if let value = nonemptyString(arguments["day_type"]),
           let parsed = ShootingDayType(rawValue: value) {
            callSheet.type = parsed
        }
        if let value = arguments["title"] as? String { callSheet.title = value }
        if let value = arguments["call_time"] as? String { callSheet.callTime = value }
        if let value = arguments["estimated_start_time"] as? String { callSheet.estimatedStartTime = value }
        if let value = arguments["estimated_wrap_time"] as? String { callSheet.estimatedWrapTime = value }
        if let value = arguments["main_location"] as? String {
            callSheet.mainLocation = value
            callSheet.locationInfo.shootingLocation = value
        }
        if let value = arguments["general_note"] as? String { callSheet.generalNote = value }
        if let rawTimeline = arguments["timeline"] as? [Any] {
            callSheet.timeline = try rawTimeline.map { raw in
                guard let item = raw as? JSONObject,
                      let time = item["time"] as? String,
                      let title = item["title"] as? String else {
                    throw MCPServerError.invalidArguments("Every timeline item requires time and title.")
                }
                let category = TimelineCategory(
                    rawValue: nonemptyString(item["category"]) ?? ""
                ) ?? .custom
                return DayTimelineItem(
                    time: time,
                    title: title,
                    category: category,
                    relatedDepartment: item["department"] as? String ?? "",
                    isKeyMilestone: item["key_milestone"] as? Bool ?? false,
                    note: item["note"] as? String ?? ""
                )
            }
        }
        callSheet.status = callSheet.status == .empty ? .draft : callSheet.status
        callSheet.updatedAt = Date()
        callSheet.revisions.append(CallSheetRevision(
            revisionCode: "Agent-\(callSheet.revisions.count + 1)",
            summary: "Updated through 321Doit MCP",
            changedFields: arguments.keys.sorted()
        ))
        project.shootingDays[dayIndex].callSheet = callSheet
        let savedDayID = project.shootingDays[dayIndex].id
        project.shootingDays.sort { $0.date < $1.date }
        try ProjectRepository.save(project, to: projectURL)

        guard let savedDay = project.shootingDays.first(where: { $0.id == savedDayID }) else {
            throw MCPServerError.unavailable("The saved shooting day could not be reloaded.")
        }
        let result: JSONObject = [
            "written": true,
            "project_path": projectURL.path,
            "shooting_day_id": savedDay.id.uuidString.lowercased(),
            "date": dateText,
            "call_sheet": try MCPJSON.dictionary(from: savedDay.callSheet),
            "canonical_project_path": ProjectRepository.projectStateJSONURL(for: projectURL).path,
            "reports_directory": ProjectRepository.reportsDirectory(for: projectURL).path,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "production_plan_upsert_call_sheet",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func exportCallSheet(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        guard let dateText = nonemptyString(arguments["date"]),
              let date = shootingDate(dateText),
              let format = nonemptyString(arguments["format"]),
              ["json", "html"].contains(format),
              let idempotencyKey = nonemptyString(arguments["idempotency_key"]) else {
            throw MCPServerError.invalidArguments("project_path, YYYY-MM-DD date, json/html format, and idempotency_key are required.")
        }
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "production_plan_export_call_sheet",
            key: idempotencyKey
        ) {
            return receipt
        }
        let project = try ProjectRepository.load(from: projectURL)
        guard let day = project.shootingDays.first(where: {
            Calendar.current.isDate($0.date, inSameDayAs: date)
        }) else {
            throw MCPServerError.notFound("No shooting day exists on \(dateText).")
        }
        let directory = ProjectRepository.reportsDirectory(for: projectURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("CallSheet_\(dateText).\(format)")
        if format == "json" {
            let payload: JSONObject = [
                "schema": "com.321doit.call-sheet",
                "schema_version": 1,
                "exported_at": ISO8601DateFormatter().string(from: Date()),
                "project": try MCPJSON.dictionary(from: project.metadataOnly),
                "shooting_day": try MCPJSON.dictionary(from: day)
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputURL, options: .atomic)
        } else {
            try callSheetHTML(project: project, day: day, dateText: dateText)
                .write(to: outputURL, atomically: true, encoding: .utf8)
        }
        let result: JSONObject = [
            "exported": true,
            "format": format,
            "date": dateText,
            "report_path": outputURL.path,
            "reports_directory": directory.path,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "production_plan_export_call_sheet",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func recordScriptTake(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let idempotencyKey = try confirmedWriteKey(arguments)
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "script_log_record_take",
            key: idempotencyKey
        ) {
            return receipt
        }
        guard let dateText = nonemptyString(arguments["date"]),
              let date = shootingDate(dateText),
              let sceneNumber = nonemptyString(arguments["scene_number"]),
              let shotNumber = nonemptyString(arguments["shot_number"]) else {
            throw MCPServerError.invalidArguments("date, scene_number, and shot_number are required.")
        }

        var project = try ProjectRepository.load(from: projectURL)
        let calendar = Calendar.current
        let dayIndex: Int
        if let existing = project.shootingDays.firstIndex(where: {
            calendar.isDate($0.date, inSameDayAs: date)
        }) {
            dayIndex = existing
        } else {
            project.shootingDays.append(ShootingDay(
                date: date,
                label: "Day \(project.shootingDays.count + 1)",
                scenes: [],
                callSheet: ShootingDayCallSheet()
            ))
            dayIndex = project.shootingDays.count - 1
        }

        let sceneIndex: Int
        if let existing = project.shootingDays[dayIndex].scenes.firstIndex(where: {
            $0.sceneNumber == sceneNumber
        }) {
            sceneIndex = existing
        } else {
            project.shootingDays[dayIndex].scenes.append(ScriptScene(
                sceneNumber: sceneNumber,
                description: "",
                shots: []
            ))
            sceneIndex = project.shootingDays[dayIndex].scenes.count - 1
        }

        let shotIndex: Int
        if let existing = project.shootingDays[dayIndex].scenes[sceneIndex].shots.firstIndex(where: {
            $0.shotNumber == shotNumber
        }) {
            shotIndex = existing
        } else {
            project.shootingDays[dayIndex].scenes[sceneIndex].shots.append(Shot(
                shotNumber: shotNumber,
                cameraSetup: nonemptyString(arguments["camera_label"]) ?? "A",
                takes: []
            ))
            shotIndex = project.shootingDays[dayIndex].scenes[sceneIndex].shots.count - 1
        }

        let existingTakes = project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes
        let requestedNumber = arguments["take_number"] as? Int ?? 0
        let takeNumber = requestedNumber > 0
            ? requestedNumber
            : (existingTakes.map(\.takeNumber).max() ?? 0) + 1
        let camera = nonemptyString(arguments["camera_label"]) ?? "A"
        let status = TakeStatus(rawValue: nonemptyString(arguments["status"]) ?? "") ?? .hold
        let cameraRecord = CameraRecord(
            cameraLabel: camera,
            status: status,
            clipName: arguments["clip_name"] as? String ?? "",
            cardName: arguments["card_name"] as? String ?? "",
            tcIn: arguments["tc_in"] as? String ?? "",
            tcOut: arguments["tc_out"] as? String ?? "",
            notes: arguments["notes"] as? String ?? ""
        )
        let take = Take(
            sceneNumber: sceneNumber,
            shotNumber: shotNumber,
            takeNumber: takeNumber,
            cameraLabel: camera,
            status: status,
            isCircleTake: arguments["circle_take"] as? Bool ?? false,
            generalNote: arguments["notes"] as? String ?? "",
            quickTags: (arguments["quick_tags"] as? [Any])?.compactMap { $0 as? String } ?? [],
            cameraRecords: [cameraRecord]
        )
        project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].takes.append(take)
        try ProjectRepository.save(project, to: projectURL)

        let result: JSONObject = [
            "recorded": true,
            "project_path": projectURL.path,
            "shooting_day_id": project.shootingDays[dayIndex].id.uuidString.lowercased(),
            "scene_id": project.shootingDays[dayIndex].scenes[sceneIndex].id.uuidString.lowercased(),
            "shot_id": project.shootingDays[dayIndex].scenes[sceneIndex].shots[shotIndex].id.uuidString.lowercased(),
            "take_id": take.id.uuidString.lowercased(),
            "take_number": take.takeNumber,
            "canonical_script_log_path": ProjectRepository.scriptLogJSONURL(for: projectURL).path,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "script_log_record_take",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func exportScriptLog(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        guard let format = nonemptyString(arguments["format"]),
              ["json", "csv"].contains(format),
              let idempotencyKey = nonemptyString(arguments["idempotency_key"]) else {
            throw MCPServerError.invalidArguments("json/csv format and idempotency_key are required.")
        }
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "script_log_export_report",
            key: idempotencyKey
        ) {
            return receipt
        }
        let project = try ProjectRepository.load(from: projectURL)
        let directory = ProjectRepository.reportsDirectory(for: projectURL)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("ScriptLog.\(format)")
        if format == "json" {
            try ScriptLogExporter.writeJSON(project: project, to: outputURL)
        } else {
            try ScriptLogExporter.writeCSV(project: project, language: .en, to: outputURL)
        }
        let result: JSONObject = [
            "exported": true,
            "format": format,
            "report_path": outputURL.path,
            "reports_directory": directory.path,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "script_log_export_report",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func readStoryboard(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let document = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        return [
            "project_path": projectURL.path,
            "revision": document.revision,
            "permission_mode": (document.production?.agentPermissionMode ?? .collaborate).rawValue,
            "snapshot": try MCPJSON.dictionary(from: document)
        ]
    }

    private func analyzeStoryboard(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let document = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        let issues: [StoryboardAnalysisIssue]
        if let sceneText = nonemptyString(arguments["scene_id"]) {
            guard let sceneID = UUID(uuidString: sceneText),
                  let scene = document.scene(id: sceneID) else {
                throw MCPServerError.notFound("The requested storyboard scene was not found.")
            }
            issues = StoryboardAnalysisEngine.analyze(scene: scene)
        } else {
            issues = StoryboardAnalysisEngine.analyze(document: document)
        }
        return [
            "project_path": projectURL.path,
            "revision": document.revision,
            "issue_count": issues.count,
            "issues": try MCPJSON.object(from: issues)
        ]
    }

    private func proposeStoryboardPatch(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let document = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        guard let sceneText = nonemptyString(arguments["scene_id"]),
              let sceneID = UUID(uuidString: sceneText),
              let scene = document.scene(id: sceneID) else {
            throw MCPServerError.notFound("The requested storyboard scene was not found.")
        }
        guard let instruction = nonemptyString(arguments["instruction"]) else {
            throw MCPServerError.invalidArguments("instruction must not be empty.")
        }
        var patch = try StoryboardLocalAgent.propose(
            instruction: instruction,
            document: document,
            scene: scene
        )
        patch.agentName = nonemptyString(arguments["agent_name"]) ?? "External MCP Agent"
        patch.model = nonemptyString(arguments["model"]) ?? "external"
        let accepted = Set(patch.operations.filter { $0.risk != .high }.map(\.id))
        let preview = try StoryboardPatchEngine.preview(patch, in: document, accepting: accepted)
        let handle = UUID().uuidString.lowercased()
        pendingPatches[handle] = PendingStoryboardPatch(
            projectURL: projectURL,
            patch: patch,
            defaultAcceptedOperationIDs: accepted
        )
        return try patchResponse(
            handle: handle,
            patch: patch,
            preview: preview,
            accepted: accepted
        )
    }

    private func previewStoryboardPatch(_ arguments: JSONObject) throws -> JSONObject {
        let pending = try pendingPatch(from: arguments)
        let document = try StoryboardRepository.loadProjectStoryboard(from: pending.projectURL)
        let accepted = try operationIDs(
            from: arguments["accepted_operation_ids"],
            fallback: pending.defaultAcceptedOperationIDs,
            patch: pending.patch
        )
        let preview = try StoryboardPatchEngine.preview(
            pending.patch,
            in: document,
            accepting: accepted
        )
        return try patchResponse(
            handle: nonemptyString(arguments["patch_handle"])!,
            patch: pending.patch,
            preview: preview,
            accepted: accepted
        )
    }

    private func applyStoryboardPatch(_ arguments: JSONObject) throws -> JSONObject {
        let pending = try pendingPatch(from: arguments)
        guard arguments["confirmed_by_user"] as? Bool == true else {
            throw MCPServerError.forbidden("The MCP client must obtain explicit user confirmation before applying a storyboard patch.")
        }
        guard let idempotencyKey = nonemptyString(arguments["idempotency_key"]) else {
            throw MCPServerError.invalidArguments("idempotency_key must not be empty.")
        }
        if let receipt = try existingReceipt(
            projectURL: pending.projectURL,
            tool: "storyboard_apply_patch",
            key: idempotencyKey
        ) {
            return receipt
        }

        let accepted = try operationIDs(
            from: arguments["accepted_operation_ids"],
            fallback: [],
            patch: pending.patch
        )
        guard !accepted.isEmpty else {
            throw MCPServerError.invalidArguments("At least one explicitly approved operation ID is required.")
        }
        let before = try StoryboardRepository.loadProjectStoryboard(from: pending.projectURL)
        let permissionMode = before.production?.agentPermissionMode ?? .collaborate
        let authorization = StoryboardAgentAuthorization.externalUserConfirmed(
            source: "MCP client",
            idempotencyKey: idempotencyKey
        )
        try StoryboardAgentAuthorizationPolicy.validate(
            permissionMode: permissionMode,
            authorization: authorization,
            operationIDs: accepted
        )
        _ = try StoryboardPatchEngine.preview(pending.patch, in: before, accepting: accepted)
        var mutations = try StoryboardPatchEngine.mutations(
            for: pending.patch,
            in: before,
            accepting: accepted
        )
        guard !mutations.isEmpty else {
            throw MCPServerError.invalidArguments("The confirmed patch contains no selected mutations.")
        }

        let affected = affectedEntityIDs(in: pending.patch, accepted: accepted)
        var production = before.production ?? StoryboardProductionData()
        production.agentLogs.append(StoryboardAgentLogEntry(
            agentName: pending.patch.agentName,
            model: pending.patch.model,
            userInstruction: pending.patch.userInstruction,
            tools: ["storyboard_propose_patch", "storyboard_preview_patch", "storyboard_apply_patch"],
            affectedEntityIDs: Array(affected),
            patchID: pending.patch.id,
            confirmed: authorization.confirmedByUser,
            result: "MCP applied \(accepted.count) confirmed operations"
        ))
        mutations.append(.updateProduction(production))

        var bus = try StoryboardCommandBus(document: before)
        try bus.apply(StoryboardTransaction(
            id: pending.patch.id,
            baseRevision: pending.patch.baseRevision,
            source: .agent,
            title: pending.patch.description,
            mutations: mutations
        ))
        try StoryboardRepository.saveProjectStoryboard(bus.document, to: pending.projectURL)

        let projectKey = pending.projectURL.path
        undoEntries[projectKey, default: []].append(StoryboardUndoEntry(
            projectURL: pending.projectURL,
            patchID: pending.patch.id,
            before: before,
            appliedRevision: bus.document.revision
        ))
        if undoEntries[projectKey, default: []].count > 20 {
            undoEntries[projectKey]?.removeFirst()
        }

        let result: JSONObject = [
            "applied": true,
            "idempotency_key": idempotencyKey,
            "patch_id": pending.patch.id.uuidString.lowercased(),
            "accepted_operation_ids": accepted.map { $0.uuidString.lowercased() }.sorted(),
            "new_revision": bus.document.revision,
            "project_path": pending.projectURL.path,
            "audit_logged": true
        ]
        try storeReceipt(
            projectURL: pending.projectURL,
            tool: "storyboard_apply_patch",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func undoStoryboardChange(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        guard arguments["confirmed_by_user"] as? Bool == true else {
            throw MCPServerError.forbidden("The MCP client must obtain explicit user confirmation before undoing a storyboard change.")
        }
        guard let idempotencyKey = nonemptyString(arguments["idempotency_key"]) else {
            throw MCPServerError.invalidArguments("idempotency_key must not be empty.")
        }
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "storyboard_undo_last_agent_change",
            key: idempotencyKey
        ) {
            return receipt
        }
        guard let entry = undoEntries[projectURL.path]?.last else {
            throw MCPServerError.conflict("No MCP storyboard change is available to undo in this server session.")
        }
        let current = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        guard current.revision == entry.appliedRevision else {
            throw MCPServerError.conflict(
                "The storyboard changed after the MCP patch was applied. Refresh instead of overwriting revision \(current.revision)."
            )
        }

        var restored = entry.before
        restored.revision = current.revision + 1
        restored.updatedAt = Date()
        var production = restored.production ?? StoryboardProductionData()
        production.agentLogs.append(StoryboardAgentLogEntry(
            agentName: "321Doit MCP",
            model: "local",
            userInstruction: "Undo patch \(entry.patchID.uuidString.lowercased())",
            tools: ["storyboard_undo_last_agent_change"],
            patchID: entry.patchID,
            confirmed: true,
            result: "Restored the document before the last MCP patch"
        ))
        restored.production = production
        try StoryboardRepository.saveProjectStoryboard(restored, to: projectURL)
        undoEntries[projectURL.path]?.removeLast()

        let result: JSONObject = [
            "undone": true,
            "patch_id": entry.patchID.uuidString.lowercased(),
            "idempotency_key": idempotencyKey,
            "new_revision": restored.revision,
            "project_path": projectURL.path,
            "audit_logged": true
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "storyboard_undo_last_agent_change",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func writeStoryboardScene(_ arguments: JSONObject) throws -> JSONObject {
        let projectURL = try projectURL(from: arguments)
        let idempotencyKey = try confirmedWriteKey(arguments)
        if let receipt = try existingReceipt(
            projectURL: projectURL,
            tool: "storyboard_write_scene",
            key: idempotencyKey
        ) {
            return receipt
        }
        guard let sceneNumber = nonemptyString(arguments["scene_number"]),
              let rawShots = arguments["shots"] as? [Any] else {
            throw MCPServerError.invalidArguments("scene_number and shots are required.")
        }

        guard nonemptyString(arguments["scene_id"]) == nil else {
            throw MCPServerError.forbidden(
                "storyboard_write_scene only creates new scenes. Use storyboard_propose_patch and storyboard_apply_patch for an existing scene."
            )
        }
        let before = try StoryboardRepository.loadProjectStoryboard(from: projectURL)

        let shots = try rawShots.enumerated().map { offset, raw -> StoryboardShot in
            guard let item = raw as? JSONObject,
                  let description = nonemptyString(item["description"]) else {
                throw MCPServerError.invalidArguments("Every storyboard shot requires a non-empty description.")
            }
            let shotNumber = nonemptyString(item["shot_number"]) ?? String(offset + 1)
            let shotSize = StoryboardShotSize(
                rawValue: nonemptyString(item["shot_size"]) ?? ""
            ) ?? .medium
            let cameraAngle = StoryboardCameraAngle(
                rawValue: nonemptyString(item["camera_angle"]) ?? ""
            ) ?? .eyeLevel
            let motion = StoryboardCameraMotionKind(
                rawValue: nonemptyString(item["camera_motion"]) ?? ""
            ) ?? .locked
            let duration = number(item["duration_seconds"]) ?? 3
            guard duration >= 0.1 else {
                throw MCPServerError.invalidArguments("duration_seconds must be at least 0.1.")
            }
            return StoryboardShot(
                shotNumber: shotNumber,
                description: description,
                durationSeconds: duration,
                shotSize: shotSize,
                cameraAngle: cameraAngle,
                lens: item["lens"] as? String ?? "",
                cameraMotions: [StoryboardCameraMotion(kind: motion)],
                notes: item["notes"] as? String ?? "",
                directorIntent: arguments["director_intent"] as? String,
                soundDescription: item["sound"] as? String,
                createdBy: .agent
            )
        }
        guard !shots.isEmpty else {
            throw MCPServerError.invalidArguments("A storyboard scene must contain at least one shot.")
        }

        let sceneID = UUID()
        let replacement = StoryboardScene(
            id: sceneID,
            sceneNumber: sceneNumber,
            title: arguments["title"] as? String ?? "",
            synopsis: arguments["synopsis"] as? String ?? "",
            location: arguments["location"] as? String ?? "",
            timeOfDay: arguments["time_of_day"] as? String ?? "",
            shots: shots,
            directorIntent: arguments["director_intent"] as? String,
            targetDurationSeconds: shots.reduce(0) { $0 + $1.durationSeconds }
        )
        let operationID = UUID()
        let authorization = StoryboardAgentAuthorization.externalUserConfirmed(
            source: "321Doit MCP",
            idempotencyKey: idempotencyKey
        )
        try StoryboardAgentAuthorizationPolicy.validate(
            permissionMode: before.production?.agentPermissionMode ?? .collaborate,
            authorization: authorization,
            operationIDs: [operationID]
        )

        var production = before.production ?? StoryboardProductionData()
        production.agentLogs.append(StoryboardAgentLogEntry(
            agentName: nonemptyString(arguments["agent_name"]) ?? "External MCP Agent",
            model: nonemptyString(arguments["model"]) ?? "external",
            userInstruction: "Write storyboard scene \(sceneNumber)",
            tools: ["storyboard_write_scene"],
            affectedEntityIDs: [sceneID] + shots.map(\.id),
            patchID: operationID,
            confirmed: true,
            result: "Created basic scene with \(shots.count) shots"
        ))
        var bus = try StoryboardCommandBus(document: before)
        try bus.apply(StoryboardTransaction(
            baseRevision: before.revision,
            source: .agent,
            title: "Agent wrote storyboard scene \(sceneNumber)",
            mutations: [.addScene(scene: replacement, index: nil), .updateProduction(production)]
        ))
        try StoryboardRepository.saveProjectStoryboard(bus.document, to: projectURL)
        undoEntries[projectURL.path, default: []].append(StoryboardUndoEntry(
            projectURL: projectURL,
            patchID: operationID,
            before: before,
            appliedRevision: bus.document.revision
        ))

        let result: JSONObject = [
            "written": true,
            "created": true,
            "project_path": projectURL.path,
            "scene_id": sceneID.uuidString.lowercased(),
            "scene_number": sceneNumber,
            "shot_count": shots.count,
            "shot_ids": shots.map { $0.id.uuidString.lowercased() },
            "new_revision": bus.document.revision,
            "storyboard_path": StoryboardRepository.storyboardJSONURL(for: projectURL).path,
            "audit_logged": true,
            "idempotency_key": idempotencyKey
        ]
        try storeReceipt(
            projectURL: projectURL,
            tool: "storyboard_write_scene",
            key: idempotencyKey,
            result: result
        )
        return result
    }

    private func offloadPreflight(_ arguments: JSONObject) throws -> JSONObject {
        guard let sourcePath = nonemptyString(arguments["source_path"]) else {
            throw MCPServerError.invalidArguments("source_path is required.")
        }
        let sourceURL = try validatedExistingURL(sourcePath, requireDirectory: true)
        let maxFiles = min(max(arguments["max_files"] as? Int ?? 100_000, 1), 1_000_000)
        let stats = try directoryStats(sourceURL, maxFiles: maxFiles)
        let profile = CameraCardDetector.detect(sourceURL: sourceURL)

        let targetPaths = arguments["target_paths"] as? [Any] ?? []
        let targets = try targetPaths.map { value -> JSONObject in
            guard let path = value as? String else {
                throw MCPServerError.invalidArguments("Every target path must be a string.")
            }
            let url = try validatedExistingURL(path, requireDirectory: true)
            let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey,
                .volumeNameKey
            ])
            return [
                "path": url.path,
                "volume_name": values?.volumeName ?? "",
                "available_bytes": values?.volumeAvailableCapacityForImportantUsage ?? 0,
                "total_bytes": values?.volumeTotalCapacity ?? 0,
                "writable": FileManager.default.isWritableFile(atPath: url.path),
                "enough_for_source": (values?.volumeAvailableCapacityForImportantUsage ?? 0) > stats.totalBytes
            ]
        }

        return [
            "read_only": true,
            "source": [
                "path": sourceURL.path,
                "file_count": stats.fileCount,
                "directory_count": stats.directoryCount,
                "video_file_count": stats.videoFileCount,
                "total_bytes": stats.totalBytes,
                "scan_truncated": stats.truncated,
                "camera_profile": try MCPJSON.dictionary(from: profile)
            ],
            "targets": targets,
            "blocking_issues": targets.compactMap { target -> String? in
                if target["writable"] as? Bool != true {
                    return "Target is not writable: \(target["path"] as? String ?? "")"
                }
                if target["enough_for_source"] as? Bool != true {
                    return "Target may not have enough free space: \(target["path"] as? String ?? "")"
                }
                return nil
            }
        ]
    }

    private func startOffload(_ arguments: JSONObject) throws -> JSONObject {
        let idempotencyKey = try confirmedWriteKey(arguments)
        guard let sourcePath = nonemptyString(arguments["source_path"]),
              let projectName = nonemptyString(arguments["project_name"]),
              let cardNumber = nonemptyString(arguments["card_number"]),
              let operatorName = nonemptyString(arguments["operator_name"]),
              let rawTargets = arguments["target_paths"] as? [Any] else {
            throw MCPServerError.invalidArguments(
                "source_path, target_paths, project_name, card_number, and operator_name are required."
            )
        }
        let sourceURL = try validatedExistingURL(sourcePath, requireDirectory: true)
        let targetURLs = try rawTargets.map { raw -> URL in
            guard let path = raw as? String else {
                throw MCPServerError.invalidArguments("Every target path must be a string.")
            }
            return try validatedExistingURL(path, requireDirectory: true)
        }
        guard (1...3).contains(targetURLs.count) else {
            throw MCPServerError.invalidArguments("Offload requires one to three target directories.")
        }
        let checksum = ChecksumAlgorithm(
            rawValue: nonemptyString(arguments["checksum"]) ?? ""
        ) ?? .xxhash64
        let settings = OffloadSettings(
            projectName: projectName,
            cardNumber: cardNumber,
            operatorName: operatorName,
            camera: arguments["camera"] as? String ?? "",
            location: arguments["location"] as? String ?? "",
            notes: arguments["notes"] as? String ?? "",
            sourceURL: sourceURL,
            targetRoots: targetURLs,
            createdAt: Date(),
            generateProxies: false,
            language: .en,
            checksumAlgorithm: checksum,
            strictResume: arguments["strict_resume"] as? Bool ?? true
        )
        var result = executionCoordinator.startOffload(
            settings: settings,
            idempotencyKey: idempotencyKey
        )
        result["source_path"] = sourceURL.path
        result["target_paths"] = targetURLs.map(\.path)
        result["expected_output_paths"] = targetURLs.map {
            $0.appendingPathComponent(settings.outputFolderName, isDirectory: true).path
        }
        result["poll_with"] = "task_get_status"
        result["idempotency_key"] = idempotencyKey
        return result
    }

    private func probeMedia(_ arguments: JSONObject) throws -> JSONObject {
        guard let path = nonemptyString(arguments["media_path"]) else {
            throw MCPServerError.invalidArguments("media_path is required.")
        }
        let url = try validatedExistingURL(path, requireDirectory: false)
        let service = MediaProbeService(language: .en)
        switch service.probeSync(url: url, configuredFFmpegPath: bundledFFmpegPath()) {
        case .success(let probed):
            return [
                "media_path": url.path,
                "probe": try MCPJSON.dictionary(from: probed)
            ]
        case .failure(let error):
            throw MCPServerError.unavailable("\(error.rawValue): \(error.message(language: .en))")
        }
    }

    private func conversionPreflight(_ arguments: JSONObject) throws -> JSONObject {
        guard let path = nonemptyString(arguments["media_path"]),
              let modeText = nonemptyString(arguments["mode"]),
              let mode = MediaConversionMode(rawValue: modeText),
              let targetText = nonemptyString(arguments["target_container"]),
              let target = MediaContainer(rawValue: targetText) else {
            throw MCPServerError.invalidArguments("media_path, a valid mode, and a valid target_container are required.")
        }
        let url = try validatedExistingURL(path, requireDirectory: false)
        let probeService = MediaProbeService(language: .en)
        let probed: ProbedMedia
        switch probeService.probeSync(url: url, configuredFFmpegPath: bundledFFmpegPath()) {
        case .success(let value):
            probed = value
        case .failure(let error):
            throw MCPServerError.unavailable("\(error.rawValue): \(error.message(language: .en))")
        }
        var settings = MediaTranscodeSettings.default
        if let value = nonemptyString(arguments["video_codec"]),
           let parsed = MediaVideoCodec(rawValue: value) { settings.videoCodec = parsed }
        if let value = nonemptyString(arguments["audio_codec"]),
           let parsed = MediaAudioCodec(rawValue: value) { settings.audioCodec = parsed }
        if let value = nonemptyString(arguments["quality"]),
           let parsed = MediaTranscodeQuality(rawValue: value) { settings.quality = parsed }
        if let value = nonemptyString(arguments["scale"]),
           let parsed = MediaOutputScale(rawValue: value) { settings.scale = parsed }
        if let value = nonemptyString(arguments["frame_rate"]),
           let parsed = MediaOutputFrameRate(rawValue: value) { settings.frameRate = parsed }

        let compatibility = MediaCompatibilityService(language: .en).decide(
            probed: probed,
            mode: mode,
            target: target,
            transcode: settings
        )
        return [
            "read_only": true,
            "media_path": url.path,
            "mode": mode.rawValue,
            "target_container": target.rawValue,
            "transcode_settings": try MCPJSON.dictionary(from: settings),
            "probe": try MCPJSON.dictionary(from: probed),
            "compatibility": try MCPJSON.dictionary(from: compatibility)
        ]
    }

    private func startMediaConversion(_ arguments: JSONObject) throws -> JSONObject {
        let idempotencyKey = try confirmedWriteKey(arguments)
        guard let rawPaths = arguments["media_paths"] as? [Any],
              let destinationPath = nonemptyString(arguments["destination_path"]),
              let modeText = nonemptyString(arguments["mode"]),
              let mode = MediaConversionMode(rawValue: modeText),
              let targetText = nonemptyString(arguments["target_container"]),
              let target = MediaContainer(rawValue: targetText) else {
            throw MCPServerError.invalidArguments(
                "media_paths, destination_path, a valid mode, and a valid target_container are required."
            )
        }
        let sourceURLs = try rawPaths.map { raw -> URL in
            guard let path = raw as? String else {
                throw MCPServerError.invalidArguments("Every media path must be a string.")
            }
            return try validatedExistingURL(path, requireDirectory: false)
        }
        guard !sourceURLs.isEmpty else {
            throw MCPServerError.invalidArguments("media_paths must not be empty.")
        }
        let destinationURL = try validatedExistingURL(destinationPath, requireDirectory: true)
        guard FileManager.default.isWritableFile(atPath: destinationURL.path) else {
            throw MCPServerError.forbidden("The media conversion destination is not writable.")
        }
        var settings = MediaTranscodeSettings.default
        if let value = nonemptyString(arguments["video_codec"]),
           let parsed = MediaVideoCodec(rawValue: value) { settings.videoCodec = parsed }
        if let value = nonemptyString(arguments["audio_codec"]),
           let parsed = MediaAudioCodec(rawValue: value) { settings.audioCodec = parsed }
        if let value = nonemptyString(arguments["quality"]),
           let parsed = MediaTranscodeQuality(rawValue: value) { settings.quality = parsed }
        if let value = nonemptyString(arguments["scale"]),
           let parsed = MediaOutputScale(rawValue: value) { settings.scale = parsed }
        if let value = nonemptyString(arguments["frame_rate"]),
           let parsed = MediaOutputFrameRate(rawValue: value) { settings.frameRate = parsed }

        var result = executionCoordinator.startConversion(
            sourceURLs: sourceURLs,
            destinationURL: destinationURL,
            mode: mode,
            target: target,
            transcodeSettings: settings,
            ffmpegPath: bundledFFmpegPath() ?? "",
            idempotencyKey: idempotencyKey
        )
        result["media_paths"] = sourceURLs.map(\.path)
        result["destination_path"] = destinationURL.path
        result["poll_with"] = "task_get_status"
        result["idempotency_key"] = idempotencyKey
        return result
    }

    private func taskStatus(_ arguments: JSONObject) throws -> JSONObject {
        guard let taskID = nonemptyString(arguments["task_id"]),
              let status = executionCoordinator.status(taskID: taskID) else {
            throw MCPServerError.notFound("The requested 321Doit task was not found in this MCP session.")
        }
        return status
    }

    private func cancelTask(_ arguments: JSONObject) throws -> JSONObject {
        guard arguments["confirmed_by_user"] as? Bool == true else {
            throw MCPServerError.forbidden("Explicit user confirmation is required before cancelling a task.")
        }
        guard let taskID = nonemptyString(arguments["task_id"]),
              let status = executionCoordinator.cancel(taskID: taskID) else {
            throw MCPServerError.notFound("The requested 321Doit task was not found in this MCP session.")
        }
        return status
    }

    private func patchResponse(
        handle: String,
        patch: StoryboardPatch,
        preview: StoryboardPatchPreview,
        accepted: Set<UUID>
    ) throws -> JSONObject {
        [
            "patch_handle": handle,
            "patch": try MCPJSON.dictionary(from: patch),
            "preview": try MCPJSON.dictionary(from: preview),
            "accepted_operation_ids": accepted.map { $0.uuidString.lowercased() }.sorted(),
            "high_risk_operation_ids": patch.operations
                .filter { $0.risk == .high }
                .map { $0.id.uuidString.lowercased() }
                .sorted(),
            "requires_user_confirmation_to_apply": true
        ]
    }

    private func pendingPatch(from arguments: JSONObject) throws -> PendingStoryboardPatch {
        guard let handle = nonemptyString(arguments["patch_handle"]),
              let pending = pendingPatches[handle] else {
            throw MCPServerError.notFound("The patch handle is missing or expired. Propose a new patch.")
        }
        return pending
    }

    private func operationIDs(
        from raw: Any?,
        fallback: Set<UUID>,
        patch: StoryboardPatch
    ) throws -> Set<UUID> {
        guard let raw else { return fallback }
        guard let values = raw as? [Any] else {
            throw MCPServerError.invalidArguments("accepted_operation_ids must be an array.")
        }
        let ids = try Set(values.map { value -> UUID in
            guard let text = value as? String, let id = UUID(uuidString: text) else {
                throw MCPServerError.invalidArguments("Every accepted operation ID must be a UUID string.")
            }
            return id
        })
        let available = Set(patch.operations.map(\.id))
        guard ids.isSubset(of: available) else {
            throw MCPServerError.invalidArguments("accepted_operation_ids contains an operation outside this patch.")
        }
        return ids
    }

    private func affectedEntityIDs(
        in patch: StoryboardPatch,
        accepted: Set<UUID>
    ) -> Set<UUID> {
        Set(patch.operations.filter { accepted.contains($0.id) }.flatMap { operation -> [UUID] in
            switch operation.kind {
            case .createShot(_, _, let shot): return [shot.id]
            case .updateShot(_, let shotID, _),
                 .deleteShot(_, let shotID),
                 .moveShot(_, let shotID, _): return [shotID]
            case .updateScene(let sceneID, _): return [sceneID]
            }
        })
    }

    private func projectURL(from arguments: JSONObject) throws -> URL {
        guard let path = nonemptyString(arguments["project_path"]) else {
            throw MCPServerError.invalidArguments("project_path is required.")
        }
        return try validatedProject(path)
    }

    private func validatedProject(_ path: String) throws -> URL {
        let url = try validatedExistingURL(path, requireDirectory: true)
        guard ProjectRepository.isProjectFolder(url) else {
            throw MCPServerError.invalidArguments("Not a readable 321Doit project package: \(url.path)")
        }
        return url
    }

    private func validatedExistingURL(
        _ path: String,
        requireDirectory: Bool
    ) throws -> URL {
        guard !allowedRoots.isEmpty else {
            throw MCPServerError.forbidden(
                "No local roots are allowed. Start 321DoitMCP with --allow-root <path> or DOIT_MCP_ALLOWED_ROOTS."
            )
        }
        let candidate = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            throw MCPServerError.notFound("Path does not exist: \(candidate.path)")
        }
        guard !requireDirectory || isDirectory.boolValue else {
            throw MCPServerError.invalidArguments("Expected a directory: \(candidate.path)")
        }
        guard requireDirectory || !isDirectory.boolValue else {
            throw MCPServerError.invalidArguments("Expected a file: \(candidate.path)")
        }
        guard allowedRoots.contains(where: { Self.contains(candidate, in: $0) }) else {
            throw MCPServerError.forbidden("Path is outside the explicitly allowed local roots: \(candidate.path)")
        }
        return candidate
    }

    /// Validates a path by resolving its existing parent. This is used only to
    /// look up an idempotency receipt for an item that may already have been
    /// moved to Trash; normal execution still calls validatedProject before
    /// touching the package.
    private func validatedAllowedPath(_ path: String) throws -> URL {
        guard !allowedRoots.isEmpty else {
            throw MCPServerError.forbidden(
                "No local roots are allowed. Start 321DoitMCP with --allow-root <path> or DOIT_MCP_ALLOWED_ROOTS."
            )
        }
        let raw = URL(fileURLWithPath: path).standardizedFileURL
        let parent = raw.deletingLastPathComponent().resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw MCPServerError.notFound("Parent folder does not exist: \(parent.path)")
        }
        let candidate = parent.appendingPathComponent(raw.lastPathComponent).standardizedFileURL
        guard allowedRoots.contains(where: { Self.contains(candidate, in: $0) }) else {
            throw MCPServerError.forbidden("Path is outside the explicitly allowed local roots: \(candidate.path)")
        }
        return candidate
    }

    private func discoverProjects(maxDepth: Int) throws -> [URL] {
        guard !allowedRoots.isEmpty else {
            throw MCPServerError.forbidden(
                "No local roots are allowed. Start 321DoitMCP with --allow-root <path> or DOIT_MCP_ALLOWED_ROOTS."
            )
        }
        var found: [URL] = []
        var seen = Set<String>()
        for root in allowedRoots {
            if ProjectRepository.isProjectFolder(root), seen.insert(root.path).inserted {
                found.append(root)
                continue
            }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                let relativeDepth = url.pathComponents.count - root.pathComponents.count
                if relativeDepth > maxDepth {
                    enumerator.skipDescendants()
                    continue
                }
                guard url.pathExtension.lowercased() == ProjectRepository.projectFileExtension,
                      ProjectRepository.isProjectFolder(url) else { continue }
                let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
                guard Self.contains(resolved, in: root), seen.insert(resolved.path).inserted else {
                    enumerator.skipDescendants()
                    continue
                }
                found.append(resolved)
                enumerator.skipDescendants()
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func directoryStats(
        _ root: URL,
        maxFiles: Int
    ) throws -> (fileCount: Int, directoryCount: Int, videoFileCount: Int, totalBytes: Int64, truncated: Bool) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            throw MCPServerError.unavailable("Could not enumerate the source folder.")
        }
        var fileCount = 0
        var directoryCount = 0
        var videoFileCount = 0
        var totalBytes: Int64 = 0
        var truncated = false
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .fileSizeKey])
            if values?.isDirectory == true {
                directoryCount += 1
                continue
            }
            guard values?.isRegularFile == true else { continue }
            fileCount += 1
            totalBytes += Int64(values?.fileSize ?? 0)
            if CameraCardDetector.videoExtensions.contains(url.pathExtension.lowercased()) {
                videoFileCount += 1
            }
            if fileCount >= maxFiles {
                truncated = true
                break
            }
        }
        return (fileCount, directoryCount, videoFileCount, totalBytes, truncated)
    }

    private func manifest() -> JSONObject {
        [
            "name": "321Doit",
            "server_version": Self.version,
            "protocol_version": Self.protocolVersion,
            "product": "Free, open-source, local-first filmmaking workstation for macOS",
            "allowed_roots": allowedRoots.map(\.path),
            "core_tools": [
                "Living Storyboard",
                "Production Planning",
                "Rapid Script Log",
                "Turbo Offload",
                "Media Conversion"
            ],
            "safety": [
                "No network transport",
                "No path access outside explicitly allowed roots",
                "Read and preflight before writes or execution",
                "Storyboard revision and field-lock validation",
                "Explicit accepted operation IDs",
                "Client-attested user confirmation",
                "Idempotent project writes and task starts",
                "Atomic project writes and local backups",
                "Verified offload and conversion outputs",
                "No source-card deletion or formatting"
            ],
            "execution": [
                "project_management": "list -> create/read/update -> confirmed move to Trash",
                "offload": "preflight -> confirmed start -> task status -> output/report paths",
                "media_conversion": "preflight -> confirmed start -> task status -> verified output/report paths",
                "production_planning": "read -> confirmed call-sheet upsert -> export",
                "script_log": "read -> confirmed Take record -> export",
                "storyboard": "read/analyze -> patch or complete scene write -> audit/undo"
            ]
        ]
    }

    private func toolResult(_ structured: JSONObject, isError: Bool) -> JSONObject {
        let text = (try? MCPJSON.compactString(structured)) ?? "{\"error\":true}"
        return [
            "content": [["type": "text", "text": text]],
            "structuredContent": structured,
            "isError": isError
        ]
    }

    private func receiptURL(for projectURL: URL) -> URL {
        ProjectRepository.storageDirectory(for: projectURL)
            .appendingPathComponent("agent_idempotency.json")
    }

    private func existingReceipt(
        projectURL: URL,
        tool: String,
        key: String
    ) throws -> JSONObject? {
        let url = receiptURL(for: projectURL)
        guard FileManager.default.fileExists(atPath: url.path),
              let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? JSONObject,
              let receipts = root["receipts"] as? JSONObject,
              let receipt = receipts[key] as? JSONObject else {
            return nil
        }
        guard receipt["tool"] as? String == tool else {
            throw MCPServerError.conflict("The idempotency key was already used for a different tool.")
        }
        return receipt["result"] as? JSONObject
    }

    private func storeReceipt(
        projectURL: URL,
        tool: String,
        key: String,
        result: JSONObject
    ) throws {
        let url = receiptURL(for: projectURL)
        var root: JSONObject = [
            "schema_version": 1,
            "receipts": JSONObject()
        ]
        if FileManager.default.fileExists(atPath: url.path),
           let existing = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? JSONObject {
            root = existing
        }
        var receipts = root["receipts"] as? JSONObject ?? [:]
        receipts[key] = [
            "tool": tool,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "result": result
        ]
        root["receipts"] = receipts
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func existingWorkspaceReceipt(
        containerURL: URL,
        tool: String,
        key: String,
        subject: String
    ) throws -> JSONObject? {
        let url = workspaceReceiptURL(containerURL: containerURL, tool: tool, key: key, subject: subject)
        guard FileManager.default.fileExists(atPath: url.path),
              let receipt = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? JSONObject else {
            return nil
        }
        guard receipt["tool"] as? String == tool,
              receipt["idempotency_key"] as? String == key,
              receipt["subject"] as? String == subject else {
            throw MCPServerError.conflict("The workspace idempotency receipt does not match this operation.")
        }
        return receipt["result"] as? JSONObject
    }

    private func storeWorkspaceReceipt(
        containerURL: URL,
        tool: String,
        key: String,
        subject: String,
        result: JSONObject
    ) throws {
        let url = workspaceReceiptURL(containerURL: containerURL, tool: tool, key: key, subject: subject)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let receipt: JSONObject = [
            "schema_version": 1,
            "tool": tool,
            "idempotency_key": key,
            "subject": subject,
            "created_at": ISO8601DateFormatter().string(from: Date()),
            "result": result
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func workspaceReceiptURL(
        containerURL: URL,
        tool: String,
        key: String,
        subject: String
    ) -> URL {
        let token = Self.stableToken("\(tool)\u{1f}\(key)\u{1f}\(subject)")
        return containerURL
            .appendingPathComponent(".321doit-agent-receipts", isDirectory: true)
            .appendingPathComponent("\(token).json")
    }

    private static func stableToken(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    private func bundledFFmpegPath() -> String? {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let candidate = executable
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Tools/ffmpeg")
        return FileManager.default.isExecutableFile(atPath: candidate.path) ? candidate.path : nil
    }

    private static func contains(_ candidate: URL, in root: URL) -> Bool {
        if candidate == root { return true }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return candidate.path.hasPrefix(rootPath)
    }

    private static func pathToken(_ path: String) -> String {
        Data(path.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func path(fromToken token: String) -> String? {
        var base64 = token
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func confirmedWriteKey(_ arguments: JSONObject) throws -> String {
        guard arguments["confirmed_by_user"] as? Bool == true else {
            throw MCPServerError.forbidden(
                "The MCP client must obtain explicit user confirmation before this write."
            )
        }
        guard let idempotencyKey = nonemptyString(arguments["idempotency_key"]) else {
            throw MCPServerError.invalidArguments("idempotency_key must not be empty.")
        }
        return idempotencyKey
    }

    private func shootingDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: value),
              formatter.string(from: date) == value else {
            return nil
        }
        return Calendar.current.startOfDay(for: date)
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func callSheetHTML(project: Project, day: ShootingDay, dateText: String) -> String {
        let callSheet = day.callSheet
        let timelineRows = callSheet.timeline.map { item in
            "<tr><td>\(html(item.time))</td><td>\(html(item.title))</td><td>\(html(item.note))</td></tr>"
        }.joined(separator: "\n")
        let sceneRows = callSheet.scenePlans.map { scene in
            "<tr><td>\(html(scene.sceneNumber))</td><td>\(html(scene.location))</td><td>\(html(scene.summary))</td></tr>"
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html lang="zh-CN">
        <head>
          <meta charset="utf-8">
          <title>\(html(callSheet.title.isEmpty ? "\(project.name) Call Sheet \(dateText)" : callSheet.title))</title>
          <style>
            body{font-family:-apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif;max-width:960px;margin:40px auto;padding:0 24px;color:#1d1d1f}
            h1{margin-bottom:4px} .meta{color:#666;margin-bottom:28px}
            table{width:100%;border-collapse:collapse;margin:12px 0 28px}
            th,td{border:1px solid #ddd;padding:8px;text-align:left;vertical-align:top}
            th{background:#f5f5f7}
          </style>
        </head>
        <body>
          <h1>\(html(callSheet.title.isEmpty ? project.name : callSheet.title))</h1>
          <div class="meta">\(html(dateText)) · \(html(callSheet.type.label(language: .en)))</div>
          <p><strong>Crew call:</strong> \(html(callSheet.callTime)) &nbsp; <strong>Start:</strong> \(html(callSheet.estimatedStartTime)) &nbsp; <strong>Wrap:</strong> \(html(callSheet.estimatedWrapTime))</p>
          <p><strong>Location:</strong> \(html(callSheet.mainLocation))</p>
          <p>\(html(callSheet.generalNote))</p>
          <h2>Timeline</h2>
          <table><thead><tr><th>Time</th><th>Plan</th><th>Note</th></tr></thead><tbody>\(timelineRows)</tbody></table>
          <h2>Scenes</h2>
          <table><thead><tr><th>Scene</th><th>Location</th><th>Summary</th></tr></thead><tbody>\(sceneRows)</tbody></table>
        </body>
        </html>
        """
    }

    private func html(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private func tool(
        _ name: String,
        title: String,
        description: String,
        properties: JSONObject,
        required: [String] = [],
        readOnly: Bool,
        destructive: Bool = false,
        idempotent: Bool
    ) -> JSONObject {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": [
                "type": "object",
                "properties": properties,
                "required": required,
                "additionalProperties": false
            ],
            "annotations": [
                "title": title,
                "readOnlyHint": readOnly,
                "destructiveHint": destructive,
                "idempotentHint": idempotent,
                "openWorldHint": false
            ]
        ]
    }

    private func pathTool(_ name: String, title: String, description: String) -> JSONObject {
        tool(
            name,
            title: title,
            description: description,
            properties: ["project_path": projectPathSchema()],
            required: ["project_path"],
            readOnly: true,
            idempotent: true
        )
    }

    private func projectPathSchema() -> JSONObject {
        stringSchema("Absolute path to an existing .321doit project package inside an allowed root.")
    }

    private func stringSchema(_ description: String, defaultValue: String? = nil) -> JSONObject {
        var schema: JSONObject = ["type": "string", "description": description]
        if let defaultValue { schema["default"] = defaultValue }
        return schema
    }

    private func booleanSchema(_ description: String) -> JSONObject {
        ["type": "boolean", "description": description]
    }

    private func integerSchema(_ description: String, defaultValue: Int) -> JSONObject {
        ["type": "integer", "description": description, "default": defaultValue]
    }

    private func arraySchema(items: JSONObject, description: String) -> JSONObject {
        ["type": "array", "items": items, "description": description]
    }

    private func enumSchema(
        _ values: [String],
        description: String,
        defaultValue: String? = nil
    ) -> JSONObject {
        var schema: JSONObject = [
            "type": "string",
            "enum": values,
            "description": description
        ]
        if let defaultValue { schema["default"] = defaultValue }
        return schema
    }
}
