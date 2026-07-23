import Foundation

enum MCPTestFailure: Error {
    case failed(String)
}

@main
enum MCPSmokeTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("321doit-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let projectURL = ProjectRepository.projectPackageURL(in: root, projectName: "Agent Test")
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try ProjectRepository.save(Project(name: "Agent Test"), to: projectURL)

        let first = StoryboardShot(
            shotNumber: "1",
            description: "Wide establishing shot",
            durationSeconds: 4
        )
        let second = StoryboardShot(
            shotNumber: "2",
            description: "Repeated reaction",
            durationSeconds: 3
        )
        let scene = StoryboardScene(sceneNumber: "1", shots: [first, second])
        var production = StoryboardProductionData()
        production.agentPermissionMode = .collaborate
        let document = StoryboardDocument(
            title: "Agent Test",
            scenes: [scene],
            production: production
        )
        try StoryboardRepository.saveProjectStoryboard(document, to: projectURL)

        let taskStoreURL = root.appendingPathComponent("mcp-tasks.json")
        let server = DoitMCPServer(
            allowedRoots: [root],
            executionCoordinator: MCPExecutionCoordinator(persistenceURL: taskStoreURL)
        )
        try expect(
            server.toolDefinitions().contains { $0["name"] as? String == "storyboard_apply_patch" },
            "MCP should advertise the guarded storyboard apply tool"
        )
        for toolName in [
            "project_create",
            "project_update_metadata",
            "project_move_to_trash",
            "offload_start",
            "media_conversion_start",
            "production_plan_upsert_call_sheet",
            "production_plan_export_call_sheet",
            "script_log_record_take",
            "script_log_export_report",
            "storyboard_write_scene",
            "task_get_status",
            "task_cancel"
        ] {
            try expect(
                server.toolDefinitions().contains { $0["name"] as? String == toolName },
                "MCP should advertise \(toolName)"
            )
        }

        let projects = try structured(server.callTool(
            name: "workspace_list_projects",
            arguments: ["max_depth": 3]
        ))
        try expect(projects["count"] as? Int == 1, "MCP should discover one project")

        let createdProject = try structured(server.callTool(
            name: "project_create",
            arguments: [
                "root_path": root.path,
                "name": "Mira Global Project",
                "director": "Mira Director",
                "confirmed_by_user": true,
                "idempotency_key": "project-create-global"
            ]
        ))
        guard let createdProjectPath = createdProject["project_path"] as? String else {
            throw MCPTestFailure.failed("Project creation should return its package path")
        }
        try expect(
            ProjectRepository.isProjectFolder(URL(fileURLWithPath: createdProjectPath)),
            "MCP should create a readable project package"
        )
        let repeatedCreate = try structured(server.callTool(
            name: "project_create",
            arguments: [
                "root_path": root.path,
                "name": "Mira Global Project",
                "director": "Mira Director",
                "confirmed_by_user": true,
                "idempotency_key": "project-create-global"
            ]
        ))
        try expect(
            repeatedCreate["project_id"] as? String == createdProject["project_id"] as? String,
            "Project creation must be idempotent"
        )

        let updatedProject = try structured(server.callTool(
            name: "project_update_metadata",
            arguments: [
                "project_path": createdProjectPath,
                "production_name": "Mira Production",
                "dp": "Mira DP",
                "confirmed_by_user": true,
                "idempotency_key": "project-update-global"
            ]
        ))
        try expect(updatedProject["updated"] as? Bool == true, "MCP should update project metadata")
        let reloadedCreatedProject = try ProjectRepository.load(from: URL(fileURLWithPath: createdProjectPath))
        try expect(
            reloadedCreatedProject.productionName == "Mira Production" && reloadedCreatedProject.dp == "Mira DP",
            "Project metadata update should preserve and persist requested fields"
        )

        let unconfirmedTrash = server.callTool(
            name: "project_move_to_trash",
            arguments: [
                "project_path": createdProjectPath,
                "confirmed_by_user": false,
                "idempotency_key": "project-trash-global"
            ]
        )
        try expect(unconfirmedTrash["isError"] as? Bool == true, "Project trash must require confirmation")
        let trashedProject = try structured(server.callTool(
            name: "project_move_to_trash",
            arguments: [
                "project_path": createdProjectPath,
                "confirmed_by_user": true,
                "idempotency_key": "project-trash-global"
            ]
        ))
        try expect(trashedProject["trashed"] as? Bool == true, "MCP should move a project to Trash")
        try expect(
            !FileManager.default.fileExists(atPath: createdProjectPath),
            "A trashed project must no longer exist at its original path"
        )
        let repeatedTrash = try structured(server.callTool(
            name: "project_move_to_trash",
            arguments: [
                "project_path": createdProjectPath,
                "confirmed_by_user": true,
                "idempotency_key": "project-trash-global"
            ]
        ))
        try expect(repeatedTrash["trashed"] as? Bool == true, "Project trash must be idempotent")
        if let trashedPath = trashedProject["trashed_path"] as? String, !trashedPath.isEmpty {
            try? FileManager.default.removeItem(atPath: trashedPath)
        }

        let proposal = try structured(server.callTool(
            name: "storyboard_propose_patch",
            arguments: [
                "project_path": projectURL.path,
                "scene_id": scene.id.uuidString,
                "instruction": "压缩到1个镜头"
            ]
        ))
        guard let handle = proposal["patch_handle"] as? String,
              let highRiskIDs = proposal["high_risk_operation_ids"] as? [String],
              let highRiskID = highRiskIDs.first else {
            throw MCPTestFailure.failed("Proposal should return an opaque handle and a high-risk deletion")
        }
        try expect(
            (proposal["accepted_operation_ids"] as? [String])?.isEmpty == true,
            "High-risk patch operations must not be selected by default"
        )

        let unconfirmed = server.callTool(
            name: "storyboard_apply_patch",
            arguments: [
                "patch_handle": handle,
                "accepted_operation_ids": [highRiskID],
                "confirmed_by_user": false,
                "idempotency_key": "apply-unconfirmed"
            ]
        )
        try expect(unconfirmed["isError"] as? Bool == true, "Unconfirmed writes must be rejected")

        var suggestDocument = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        var suggestProduction = suggestDocument.production ?? StoryboardProductionData()
        suggestProduction.agentPermissionMode = .suggest
        suggestDocument.production = suggestProduction
        try StoryboardRepository.saveProjectStoryboard(suggestDocument, to: projectURL)

        let suggestDenied = server.callTool(
            name: "storyboard_apply_patch",
            arguments: [
                "patch_handle": handle,
                "accepted_operation_ids": [highRiskID],
                "confirmed_by_user": true,
                "idempotency_key": "apply-suggest-denied"
            ]
        )
        try expect(
            suggestDenied["isError"] as? Bool == true,
            "Suggest mode must remain read-only below the UI layer"
        )

        var collaborateDocument = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        var collaborateProduction = collaborateDocument.production ?? StoryboardProductionData()
        collaborateProduction.agentPermissionMode = .collaborate
        collaborateDocument.production = collaborateProduction
        try StoryboardRepository.saveProjectStoryboard(collaborateDocument, to: projectURL)

        let applyArguments: JSONObject = [
            "patch_handle": handle,
            "accepted_operation_ids": [highRiskID],
            "confirmed_by_user": true,
            "idempotency_key": "apply-confirmed-once"
        ]
        let applied = try structured(server.callTool(
            name: "storyboard_apply_patch",
            arguments: applyArguments
        ))
        try expect(applied["applied"] as? Bool == true, "Confirmed collaborate-mode write should apply")
        let revisionAfterApply = try StoryboardRepository.loadProjectStoryboard(from: projectURL).revision

        let repeated = try structured(server.callTool(
            name: "storyboard_apply_patch",
            arguments: applyArguments
        ))
        try expect(repeated["applied"] as? Bool == true, "Idempotent retry should return the first result")
        try expect(
            try StoryboardRepository.loadProjectStoryboard(from: projectURL).revision == revisionAfterApply,
            "Idempotent retry must not advance the storyboard revision"
        )

        let undone = try structured(server.callTool(
            name: "storyboard_undo_last_agent_change",
            arguments: [
                "project_path": projectURL.path,
                "confirmed_by_user": true,
                "idempotency_key": "undo-confirmed-once"
            ]
        ))
        try expect(undone["undone"] as? Bool == true, "Confirmed undo should succeed")
        let restored = try StoryboardRepository.loadProjectStoryboard(from: projectURL)
        try expect(restored.scenes.first?.shots.count == 2, "Undo should restore both original shots")
        try expect(
            restored.production?.agentLogs.last?.tools == ["storyboard_undo_last_agent_change"],
            "Undo should leave a local audit entry"
        )

        let callSheetDenied = server.callTool(
            name: "production_plan_upsert_call_sheet",
            arguments: [
                "project_path": projectURL.path,
                "date": "2026-07-19",
                "confirmed_by_user": false,
                "idempotency_key": "call-sheet-denied"
            ]
        )
        try expect(callSheetDenied["isError"] as? Bool == true, "Unconfirmed call-sheet writes must be rejected")

        let callSheet = try structured(server.callTool(
            name: "production_plan_upsert_call_sheet",
            arguments: [
                "project_path": projectURL.path,
                "date": "2026-07-19",
                "title": "Day 1",
                "call_time": "06:30",
                "estimated_start_time": "07:30",
                "estimated_wrap_time": "19:00",
                "main_location": "Studio A",
                "general_note": "Shoot scenes 1 and 2.",
                "timeline": [
                    ["time": "06:30", "title": "Crew Call", "category": "crewCall", "key_milestone": true],
                    ["time": "07:30", "title": "First Shot", "category": "shooting", "key_milestone": true]
                ],
                "confirmed_by_user": true,
                "idempotency_key": "call-sheet-write-once"
            ]
        ))
        try expect(callSheet["written"] as? Bool == true, "Agent should write a call sheet")
        let callSheetReport = try structured(server.callTool(
            name: "production_plan_export_call_sheet",
            arguments: [
                "project_path": projectURL.path,
                "date": "2026-07-19",
                "format": "html",
                "idempotency_key": "call-sheet-export-once"
            ]
        ))
        try expect(
            FileManager.default.fileExists(atPath: callSheetReport["report_path"] as? String ?? ""),
            "Call-sheet export should return an existing report path"
        )

        let take = try structured(server.callTool(
            name: "script_log_record_take",
            arguments: [
                "project_path": projectURL.path,
                "date": "2026-07-19",
                "scene_number": "1",
                "shot_number": "1",
                "camera_label": "A",
                "status": "good",
                "circle_take": true,
                "notes": "Best performance",
                "clip_name": "A001C001",
                "card_name": "A01",
                "confirmed_by_user": true,
                "idempotency_key": "take-write-once"
            ]
        ))
        try expect(take["recorded"] as? Bool == true, "Agent should record a script take")
        let scriptReport = try structured(server.callTool(
            name: "script_log_export_report",
            arguments: [
                "project_path": projectURL.path,
                "format": "json",
                "idempotency_key": "script-report-once"
            ]
        ))
        try expect(
            FileManager.default.fileExists(atPath: scriptReport["report_path"] as? String ?? ""),
            "Script-log export should return an existing report path"
        )

        let writtenScene = try structured(server.callTool(
            name: "storyboard_write_scene",
            arguments: [
                "project_path": projectURL.path,
                "scene_number": "2",
                "title": "Arrival",
                "synopsis": "The lead enters an empty studio.",
                "location": "Studio A",
                "time_of_day": "Morning",
                "director_intent": "Build quiet anticipation.",
                "shots": [
                    [
                        "shot_number": "1",
                        "description": "Wide shot of the empty studio.",
                        "duration_seconds": 4.0,
                        "shot_size": "wide",
                        "camera_angle": "eyeLevel",
                        "camera_motion": "locked",
                        "sound": "Room tone"
                    ],
                    [
                        "shot_number": "2",
                        "description": "The door opens and the lead enters.",
                        "duration_seconds": 3.0,
                        "shot_size": "medium",
                        "camera_angle": "eyeLevel",
                        "camera_motion": "push",
                        "sound": "Door hinge"
                    ]
                ],
                "confirmed_by_user": true,
                "idempotency_key": "storyboard-write-scene-once"
            ]
        ))
        try expect(writtenScene["written"] as? Bool == true, "Agent should write a complete storyboard scene")
        try expect(
            try StoryboardRepository.loadProjectStoryboard(from: projectURL).scenes.count == 2,
            "Storyboard scene write should persist"
        )
        let unsafeReplacement = server.callTool(
            name: "storyboard_write_scene",
            arguments: [
                "project_path": projectURL.path,
                "scene_id": writtenScene["scene_id"] as? String ?? "",
                "scene_number": "2",
                "shots": [["shot_number": "1", "description": "This must not replace the scene."]],
                "confirmed_by_user": true,
                "idempotency_key": "storyboard-replace-must-fail"
            ]
        )
        try expect(
            unsafeReplacement["isError"] as? Bool == true,
            "Basic storyboard scene writes must never replace an existing scene"
        )

        let card = root.appendingPathComponent("CameraCard", isDirectory: true)
        try FileManager.default.createDirectory(
            at: card.appendingPathComponent("PRIVATE/M4ROOT/CLIP", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("mock".utf8).write(
            to: card.appendingPathComponent("PRIVATE/M4ROOT/CLIP/C0001.MP4")
        )
        let offload = try structured(server.callTool(
            name: "offload_preflight",
            arguments: ["source_path": card.path, "max_files": 100]
        ))
        let source = offload["source"] as? JSONObject
        try expect(
            (source?["camera_profile"] as? JSONObject)?["maker"] as? String == "Sony",
            "Offload preflight should identify a Sony M4ROOT card"
        )
        try expect(offload["read_only"] as? Bool == true, "Offload MCP tool must remain preflight-only")

        let offloadTarget = root.appendingPathComponent("OffloadTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: offloadTarget, withIntermediateDirectories: true)
        let startedOffload = try structured(server.callTool(
            name: "offload_start",
            arguments: [
                "source_path": card.path,
                "target_paths": [offloadTarget.path],
                "project_name": "Agent Test",
                "card_number": "A01",
                "operator_name": "MCP Test",
                "checksum": "xxhash64",
                "strict_resume": true,
                "confirmed_by_user": true,
                "idempotency_key": "offload-start-once"
            ]
        ))
        guard let offloadTaskID = startedOffload["task_id"] as? String else {
            throw MCPTestFailure.failed("Offload start should return a task ID")
        }
        let completedOffload = try waitForTask(server, taskID: offloadTaskID)
        try expect(completedOffload["state"] as? String == "completed", "Agent offload should complete")
        let offloadResult = completedOffload["result"] as? JSONObject
        let targetResults = offloadResult?["targets"] as? [JSONObject]
        let reportPaths = targetResults?.first?["report_paths"] as? JSONObject
        try expect(
            FileManager.default.fileExists(atPath: reportPaths?["json"] as? String ?? ""),
            "Offload should return an existing JSON report path"
        )
        let restartedServer = DoitMCPServer(
            allowedRoots: [root],
            executionCoordinator: MCPExecutionCoordinator(persistenceURL: taskStoreURL)
        )
        let restoredOffload = try structured(restartedServer.callTool(
            name: "task_get_status",
            arguments: ["task_id": offloadTaskID]
        ))
        try expect(
            restoredOffload["state"] as? String == "completed",
            "Completed MCP tasks must remain queryable after an MCP restart"
        )

        let mediaSource = root.appendingPathComponent("tone.wav")
        try makeSilentWAV().write(to: mediaSource, options: .atomic)
        let conversionTarget = root.appendingPathComponent("ConversionTarget", isDirectory: true)
        try FileManager.default.createDirectory(at: conversionTarget, withIntermediateDirectories: true)
        let startedConversion = try structured(server.callTool(
            name: "media_conversion_start",
            arguments: [
                "media_paths": [mediaSource.path],
                "destination_path": conversionTarget.path,
                "mode": "losslessAudio",
                "target_container": "flac",
                "confirmed_by_user": true,
                "idempotency_key": "conversion-start-once"
            ]
        ))
        guard let conversionTaskID = startedConversion["task_id"] as? String else {
            throw MCPTestFailure.failed("Media conversion start should return a task ID")
        }
        let completedConversion = try waitForTask(server, taskID: conversionTaskID)
        try expect(completedConversion["state"] as? String == "completed", "Agent media conversion should complete")
        let conversionResult = completedConversion["result"] as? JSONObject
        let outputs = conversionResult?["outputs"] as? [JSONObject]
        try expect(
            FileManager.default.fileExists(atPath: outputs?.first?["output_path"] as? String ?? ""),
            "Media conversion should return an existing output path"
        )
        try expect(
            FileManager.default.fileExists(atPath: outputs?.first?["report_path"] as? String ?? ""),
            "Media conversion should return an existing report path"
        )

        let outside = server.callTool(
            name: "project_read_snapshot",
            arguments: ["project_path": "/"]
        )
        try expect(outside["isError"] as? Bool == true, "Paths outside allowed roots must be rejected")

        print("321Doit MCP smoke tests passed")
    }

    private static func waitForTask(
        _ server: DoitMCPServer,
        taskID: String,
        timeout: TimeInterval = 20
    ) throws -> JSONObject {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let status = try structured(server.callTool(
                name: "task_get_status",
                arguments: ["task_id": taskID]
            ))
            if ["completed", "failed", "cancelled"].contains(status["state"] as? String ?? "") {
                if status["state"] as? String == "failed" {
                    throw MCPTestFailure.failed(status["error"] as? String ?? "Background task failed")
                }
                return status
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw MCPTestFailure.failed("Timed out waiting for task \(taskID)")
    }

    private static func makeSilentWAV(sampleRate: UInt32 = 8_000, sampleCount: UInt32 = 800) -> Data {
        let dataSize = sampleCount * 2
        var data = Data()
        func appendASCII(_ value: String) { data.append(contentsOf: value.utf8) }
        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        appendASCII("RIFF")
        appendUInt32(36 + dataSize)
        appendASCII("WAVEfmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(sampleRate)
        appendUInt32(sampleRate * 2)
        appendUInt16(2)
        appendUInt16(16)
        appendASCII("data")
        appendUInt32(dataSize)
        data.append(Data(count: Int(dataSize)))
        return data
    }

    private static func structured(_ result: JSONObject) throws -> JSONObject {
        if result["isError"] as? Bool == true {
            let details = result["structuredContent"] as? JSONObject
            throw MCPTestFailure.failed(details?["message"] as? String ?? "MCP tool failed")
        }
        guard let structured = result["structuredContent"] as? JSONObject else {
            throw MCPTestFailure.failed("MCP tool did not return structured content")
        }
        return structured
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw MCPTestFailure.failed(message) }
    }
}
