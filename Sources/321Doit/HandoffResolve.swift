import AppKit
import Foundation

// MARK: - DaVinci Resolve handoff
//
// Generates per-job JSON + Python import files and a per-job README.
// One-click "send" launches Resolve and runs the script through its
// fuscript bridge (see ResolveLauncher).

struct ResolveImportPayload: Encodable, Equatable {
    var projectName: String
    var timelineName: String
    var frameRate: String
    var timelineWidth: String
    var timelineHeight: String
    var startTimecode: String
    var generateStarterTimeline: Bool
    var options: Options
    var bins: [Bin]
    var lut: LUT?

    struct Bin: Encodable, Equatable {
        var name: String
        var path: [String]
        var items: [Item]
    }

    struct Item: Encodable, Equatable {
        var name: String
        var originalPath: String
        var proxyPath: String?
        var cardId: String
        var reel: String
        // Script Log metadata
        var scene: String?
        var shot: String?
        var take: String?
        var cameraAngle: String?
        var notes: String?
        var status: String?
        var isCircleTake: Bool?
        var tags: [String]?
    }

    struct LUT: Encodable, Equatable {
        var enabled: Bool
        var path: String?
    }

    struct Options: Encodable, Equatable {
        var importOriginals: Bool
        var importProxies: Bool
        var writeSceneMetadata: Bool
        var writeShotMetadata: Bool
        var writeTakeMetadata: Bool
        var writeCameraMetadata: Bool
        var writeComments: Bool
        var writeKeywords: Bool
        var applyClipColors: Bool
        var applyFlags: Bool
        var statusMappings: StatusMappings
    }

    struct StatusMappings: Encodable, Equatable {
        var ok: ResolveStatusMapping
        var kp: ResolveStatusMapping
        var ng: ResolveStatusMapping
        var circle: ResolveStatusMapping
    }
}

enum HandoffResolveBuilder {

    static func write(
        manifest: HandoffManifest,
        offload: OffloadSettings,
        target: TargetReport,
        into directory: URL
    ) throws -> (jsonURL: URL, pyURL: URL, readmeURL: URL) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let payload = makePayload(manifest: manifest, offload: offload, target: target)
        let stem = OutputFileNamer.stem(projectName: manifest.project.name, date: offload.createdAt, attribute: "Resolve_Import")
        let jsonName = "\(stem).json"
        let scriptName = "\(stem).py"
        let jsonURL = directory.appendingPathComponent(jsonName)
        try writeJSON(payload, to: jsonURL)

        let pyURL = directory.appendingPathComponent(scriptName)
        try resolveScript(jsonRelativePath: jsonName)
            .write(to: pyURL, atomically: true, encoding: .utf8)
        try setExecutable(pyURL)

        let readmeURL = directory.appendingPathComponent(
            OutputFileNamer.fileName(projectName: manifest.project.name, date: offload.createdAt, attribute: "Resolve_README", extension: "md")
        )
        try readme(payload: payload, jsonFileName: jsonName, scriptFileName: scriptName)
            .write(to: readmeURL, atomically: true, encoding: .utf8)

        return (jsonURL, pyURL, readmeURL)
    }

    static func makePayload(
        manifest: HandoffManifest,
        offload: OffloadSettings,
        target: TargetReport
    ) -> ResolveImportPayload {
        let resolution = offload.handoff.resolution.size

        let bins = makeBins(media: manifest.media, includeProxies: offload.handoff.importProxies)

        let lut: ResolveImportPayload.LUT?
        if let lutPath = manifest.project.color.lutPath, !lutPath.isEmpty {
            lut = ResolveImportPayload.LUT(enabled: offload.handoff.importLUT, path: lutPath)
        } else {
            lut = nil
        }

        return ResolveImportPayload(
            projectName: manifest.project.name,
            timelineName: manifest.project.timeline.name,
            frameRate: manifest.project.frameRate.display,
            timelineWidth: String(resolution.width),
            timelineHeight: String(resolution.height),
            startTimecode: manifest.project.timeline.startTimecode,
            generateStarterTimeline: false,
            options: ResolveImportPayload.Options(
                importOriginals: offload.handoff.resolveImportOriginals,
                importProxies: offload.handoff.importProxies,
                writeSceneMetadata: offload.handoff.resolveWriteSceneMetadata,
                writeShotMetadata: offload.handoff.resolveWriteShotMetadata,
                writeTakeMetadata: offload.handoff.resolveWriteTakeMetadata,
                writeCameraMetadata: offload.handoff.resolveWriteCameraMetadata,
                writeComments: offload.handoff.resolveWriteComments,
                writeKeywords: offload.handoff.resolveWriteKeywords,
                applyClipColors: offload.handoff.resolveApplyClipColors,
                applyFlags: offload.handoff.resolveApplyFlags,
                statusMappings: ResolveImportPayload.StatusMappings(
                    ok: offload.handoff.resolveOKMapping,
                    kp: offload.handoff.resolveKPMapping,
                    ng: offload.handoff.resolveNGMapping,
                    circle: offload.handoff.resolveCircleMapping
                )
            ),
            bins: bins,
            lut: lut
        )
    }

    private static func makeBins(media: [HandoffMediaItem], includeProxies: Bool) -> [ResolveImportPayload.Bin] {
        // Group by scene and shot so editorial receives the same structure as the shooting plan.
        var grouped: [String: [ResolveImportPayload.Item]] = [:]
        var paths: [String: [String]] = [:]
        var ordering: [String] = []
        for clip in media {
            let card = clip.cardId.isEmpty ? "UNKNOWN_CARD" : clip.cardId
            let sceneName = sceneBinName(clip.metadata.scene)
            let shotName = shotBinName(clip.metadata.shot)
            let key = "\(sceneName)\u{1f}\(shotName)"
            if grouped[key] == nil {
                grouped[key] = []
                paths[key] = [sceneName, shotName]
                ordering.append(key)
            }
            let item = ResolveImportPayload.Item(
                name: clip.original.filename,
                originalPath: clip.original.path,
                proxyPath: includeProxies && clip.proxy?.exists == true ? clip.proxy?.path : nil,
                cardId: card,
                reel: clip.camera.reel,
                scene: clip.metadata.scene.isEmpty ? nil : clip.metadata.scene,
                shot: clip.metadata.shot.isEmpty ? nil : clip.metadata.shot,
                take: clip.metadata.take.isEmpty ? nil : clip.metadata.take,
                cameraAngle: clip.metadata.cameraAngle.isEmpty ? nil : clip.metadata.cameraAngle,
                notes: clip.metadata.notes.isEmpty ? nil : clip.metadata.notes,
                status: clip.metadata.status,
                isCircleTake: clip.metadata.isCircleTake,
                tags: clip.metadata.tags
            )
            grouped[key]?.append(item)
        }
        return ordering.map { key in
            ResolveImportPayload.Bin(
                name: (paths[key] ?? [key]).joined(separator: " / "),
                path: paths[key] ?? [key],
                items: (grouped[key] ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            )
        }
    }

    private static func sceneBinName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unmatched_Scene" }
        return "Scene_\(trimmed)"
    }

    private static func shotBinName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unmatched_Shot" }
        return "Shot_\(trimmed)"
    }

    private static func writeJSON(_ payload: ResolveImportPayload, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(payload).write(to: url, options: [.atomic])
    }

    private static func setExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: url.path
        )
    }

    // MARK: - README

    private static func readme(payload: ResolveImportPayload, jsonFileName: String, scriptFileName: String) -> String {
        """
        # DaVinci Resolve 按拍摄计划归类 / DaVinci Resolve Shooting-Plan Import

        由 321Doit 自动生成。不要手动修改 `\(jsonFileName)`，否则导入脚本可能会失败。

        ## 项目参数 / Project Settings

        - 项目名称 / Project Name: `\(payload.projectName)`
        - 时间线 / Timeline: `\(payload.timelineName)`
        - 分辨率 / Resolution: `\(payload.timelineWidth)×\(payload.timelineHeight)`
        - 帧率 / Frame Rate: `\(payload.frameRate)`
        - 起始码 / Start TC: `\(payload.startTimecode)`

        ## 一键导入 / One-click Import

        在 321Doit 中点击 **发送到 DaVinci Resolve** / *Send to DaVinci Resolve*。
        321Doit 会启动 / 激活 DaVinci Resolve 并运行 `\(scriptFileName)`。

        ## 手动导入 / Manual Import

        1. 打开 DaVinci Resolve。
        2. 在 *Preferences › System › General* 中确保 *External scripting using* = **Local**。
        3. 在终端运行：
           ```sh
           export RESOLVE_SCRIPT_API="/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting"
           export RESOLVE_SCRIPT_LIB="/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so"
           export PYTHONPATH="$PYTHONPATH:$RESOLVE_SCRIPT_API/Modules/"
           python3 "\(scriptFileName)"
           ```

        ## 行为说明 / Notes

        - 项目存在时不会覆盖，会自动追加后缀（例如 `\(payload.projectName)_001`）。
        - 按 `场次 > 镜头` 创建 Bin，文件名稳定排序，缺失代理仅 warning。
        - 按交接设置决定是否导入原片、链接代理、写入 Scene/Shot/Take/Camera/Comments/Keywords，并按 OK/KP/NG/优选条映射素材颜色或旗标。
        - DaVinci Resolve 导入只导入媒体并链接代理，不会新建 starter timeline。
        - LUT 默认仅放入 `05_HANDOFF/LUT/`；只有勾选 *Apply LUT on import* 才会尝试 `SetLUT`。
        - 不会修改原始素材或代理素材，所有引用都是绝对路径。
        """
    }

    // MARK: - Python script template
    //
    // Self-contained: reads the sibling `resolve_import.json`, talks to the
    // running Resolve via the standard fuscript bridge, returns a JSON status
    // line on stdout that 321Doit parses (see ResolveLauncher).

    static func resolveScript(jsonRelativePath: String) -> String {
        let header = """
        #!/usr/bin/env python3
        # -*- coding: utf-8 -*-
        # Generated by 321Doit. Do not hand-edit; regenerate from the manifest.

        import json
        import os
        import sys
        import time

        SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
        JSON_PATH = os.path.join(SCRIPT_DIR, "\(jsonRelativePath)")
        """
        let body = """

        def emit_result(payload):
            sys.stdout.write("321DOIT_RESULT_BEGIN\\n")
            sys.stdout.write(json.dumps(payload, ensure_ascii=False))
            sys.stdout.write("\\n321DOIT_RESULT_END\\n")
            sys.stdout.flush()


        def fail(error_code, message):
            emit_result({
                "ok": False,
                "errorCode": error_code,
                "message": message,
            })
            sys.exit(1)


        def load_resolve():
            api = os.environ.get(
                "RESOLVE_SCRIPT_API",
                "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting",
            )
            lib = os.environ.get(
                "RESOLVE_SCRIPT_LIB",
                "/Applications/DaVinci Resolve/DaVinci Resolve.app/Contents/Libraries/Fusion/fusionscript.so",
            )
            modules = os.path.join(api, "Modules")
            if modules not in sys.path:
                sys.path.append(modules)

            try:
                import DaVinciResolveScript as dvr_script
            except Exception as exc:  # pragma: no cover - depends on Resolve env.
                fail("RESOLVE_SCRIPTING_UNAVAILABLE", "Cannot import DaVinciResolveScript: %s" % exc)
                return None

            try:
                resolve = dvr_script.scriptapp("Resolve")
            except Exception as exc:
                fail("RESOLVE_NOT_RUNNING", "DaVinci Resolve scripting bridge is not available: %s" % exc)
                return None

            if resolve is None:
                fail("RESOLVE_NOT_RUNNING", "DaVinci Resolve scripting bridge is not available.")
                return None
            return resolve


        def project_name_with_suffix(project_manager, base_name):
            # Avoid overwriting existing Resolve projects of the same name.
            try:
                existing = project_manager.GetProjectListInCurrentFolder() or []
            except Exception:
                existing = []
            existing_lower = set([str(item).lower() for item in existing])
            if base_name.lower() not in existing_lower:
                return base_name
            for index in range(1, 1000):
                candidate = "%s_%03d" % (base_name, index)
                if candidate.lower() not in existing_lower:
                    return candidate
            return "%s_%d" % (base_name, int(time.time()))


        def set_project_settings(project, frame_rate, width, height, start_tc):
            try:
                project.SetSetting("timelineFrameRate", str(frame_rate))
            except Exception:
                pass
            try:
                project.SetSetting("timelineResolutionWidth", str(width))
            except Exception:
                pass
            try:
                project.SetSetting("timelineResolutionHeight", str(height))
            except Exception:
                pass
            try:
                project.SetSetting("timelineOutputResolutionWidth", str(width))
            except Exception:
                pass
            try:
                project.SetSetting("timelineOutputResolutionHeight", str(height))
            except Exception:
                pass
            try:
                project.SetSetting("timelineDefaultStartTimecode", str(start_tc))
            except Exception:
                pass


        def add_subfolder(media_pool, parent, name):
            try:
                children = parent.GetSubFolderList() or []
            except Exception:
                children = []
            for child in children:
                try:
                    if child.GetName() == name:
                        return child
                except Exception:
                    continue
            try:
                return media_pool.AddSubFolder(parent, name)
            except Exception:
                return parent


        def add_nested_folder(media_pool, parent, path):
            folder = parent
            for part in path or []:
                name = str(part or "").strip()
                if not name:
                    continue
                folder = add_subfolder(media_pool, folder, name)
            return folder


        def set_clip_proxy(item, proxy_path):
            if not proxy_path:
                return None
            for method_name in ("LinkProxyMedia", "SetProxyMedia"):
                fn = getattr(item, method_name, None)
                if fn is None:
                    continue
                try:
                    if fn(proxy_path):
                        return None
                except Exception as exc:
                    return str(exc)
            return "Resolve API rejected the proxy link."


        def main():
            try:
                with open(JSON_PATH, "r") as fp:
                    payload = json.load(fp)
            except Exception as exc:
                fail("INVALID_PAYLOAD", "resolve_import.json could not be read: %s" % exc)
                return

            resolve = load_resolve()
            project_manager = resolve.GetProjectManager()
            if project_manager is None:
                fail("RESOLVE_NOT_RUNNING", "DaVinci Resolve project manager unavailable.")
                return

            base_name = payload.get("projectName") or "321Doit_Project"
            project_name = project_name_with_suffix(project_manager, base_name)

            try:
                project = project_manager.CreateProject(project_name)
            except Exception as exc:
                fail("PROJECT_CREATE_FAILED", "Could not create project %s: %s" % (project_name, exc))
                return

            if project is None:
                fail("PROJECT_CREATE_FAILED", "Could not create project %s" % project_name)
                return

            try:
                project_manager.LoadProject(project_name)
            except Exception:
                pass

            try:
                set_project_settings(
                    project,
                    payload.get("frameRate", "25"),
                    payload.get("timelineWidth", "1920"),
                    payload.get("timelineHeight", "1080"),
                    payload.get("startTimecode", "01:00:00:00"),
                )
            except Exception:
                pass

            media_pool = project.GetMediaPool()
            if media_pool is None:
                fail("MEDIA_POOL_UNAVAILABLE", "Resolve media pool is unavailable.")
                return

            root = media_pool.GetRootFolder()
            project_folder = add_subfolder(media_pool, root, "321Doit_" + base_name)
            scene_root = add_subfolder(media_pool, project_folder, "By_Scene")

            imported_originals = 0
            linked_proxies = 0
            missing_proxies = []
            failed_proxy_links = []
            failed_media = []
            warnings = []
            timeline_clips = []

            def set_metadata(clip, field, value, item_name):
                if value is None or value == "":
                    return
                try:
                    accepted = clip.SetClipProperty(field, str(value))
                    if accepted is False:
                        warnings.append("Resolve did not accept metadata field %s for %s" % (field, item_name))
                except Exception as exc:
                    warnings.append("Failed metadata field %s for %s: %s" % (field, item_name, exc))

            def set_clip_color(clip, color, item_name):
                if not color or color == "None":
                    return
                try:
                    accepted = clip.SetClipColor(color)
                    if accepted is False:
                        warnings.append("Resolve did not accept clip color %s for %s" % (color, item_name))
                except Exception as exc:
                    warnings.append("Failed clip color %s for %s: %s" % (color, item_name, exc))

            def add_flag(clip, color, item_name):
                if not color or color == "None":
                    return
                fn = getattr(clip, "AddFlag", None)
                if fn is None:
                    warnings.append("Resolve AddFlag API is unavailable for %s" % item_name)
                    return
                try:
                    accepted = fn(color)
                    if accepted is False:
                        warnings.append("Resolve did not accept flag color %s for %s" % (color, item_name))
                except Exception as exc:
                    warnings.append("Failed flag color %s for %s: %s" % (color, item_name, exc))

            def clean_keyword(mapping):
                return str((mapping or {}).get("keyword") or "").strip()

            def color_value(mapping, key):
                value = str((mapping or {}).get(key) or "").strip()
                return None if not value or value == "None" else value

            def status_mapping(status, mappings):
                normalized = str(status or "").lower()
                if normalized in ("good", "ok"):
                    return mappings.get("ok") or {}
                if normalized == "ng":
                    return mappings.get("ng") or {}
                if normalized in ("hold", "kp"):
                    return mappings.get("kp") or {}
                return {}

            def apply_mapping(clip, mapping, item_name, options):
                if options.get("applyClipColors", True):
                    set_clip_color(clip, color_value(mapping, "clipColor"), item_name)
                if options.get("applyFlags", False):
                    add_flag(clip, color_value(mapping, "flagColor"), item_name)

            for bin_payload in payload.get("bins", []):
                options = payload.get("options") or {}
                mappings = options.get("statusMappings") or {}
                bin_path = bin_payload.get("path") or [bin_payload.get("name") or "Unmatched_Scene"]
                bin_folder = add_nested_folder(media_pool, scene_root, bin_path)
                try:
                    media_pool.SetCurrentFolder(bin_folder)
                except Exception:
                    pass
                for item in bin_payload.get("items", []):
                    original_path = item.get("originalPath")
                    proxy_path = item.get("proxyPath")
                    import_path = original_path if options.get("importOriginals", True) else proxy_path
                    import_kind = "original" if import_path == original_path else "proxy"
                    if not import_path:
                        failed_media.append({
                            "path": original_path or proxy_path,
                            "reason": "IMPORT_DISABLED",
                        })
                        warnings.append("Neither original nor proxy import is enabled for %s" % (item.get("name") or "unknown item"))
                        continue
                    if not os.path.exists(import_path):
                        failed_media.append({
                            "path": import_path,
                            "reason": "ORIGINAL_NOT_FOUND" if import_kind == "original" else "PROXY_NOT_FOUND",
                        })
                        continue
                    try:
                        clips = media_pool.ImportMedia([import_path]) or []
                    except Exception as exc:
                        failed_media.append({
                            "path": import_path,
                            "reason": "IMPORT_FAILED: %s" % exc,
                        })
                        continue
                    if not clips:
                        failed_media.append({
                            "path": import_path,
                            "reason": "Resolve refused the import call.",
                        })
                        continue
                    imported_originals += len(clips)
                    timeline_clips.extend(clips)

                    # Inject Script Log Metadata via DaVinci Resolve API
                    for clip in clips:
                        try:
                            item_name = item.get("name") or import_path
                            if options.get("writeSceneMetadata", True):
                                set_metadata(clip, "Scene", item.get("scene"), item_name)
                            if options.get("writeShotMetadata", True):
                                set_metadata(clip, "Shot", item.get("shot"), item_name)
                            if options.get("writeTakeMetadata", True):
                                set_metadata(clip, "Take", item.get("take"), item_name)
                            if item.get("cameraAngle") and options.get("writeCameraMetadata", True):
                                set_metadata(clip, "Camera", item.get("cameraAngle"), item_name)
                                set_metadata(clip, "Angle", item.get("cameraAngle"), item_name)
                            if options.get("writeComments", True):
                                set_metadata(clip, "Comments", item.get("notes"), item_name)

                            tags = item.get("tags") or []
                            status = str(item.get("status") or "").lower()

                            keywords = []
                            mapping = status_mapping(status, mappings)
                            if status == "good" or status == "ok":
                                set_metadata(clip, "Good", "1", item_name)
                            keyword = clean_keyword(mapping)
                            if keyword:
                                keywords.append(keyword)
                            if mapping:
                                apply_mapping(clip, mapping, item_name, options)

                            if item.get("isCircleTake"):
                                circle_mapping = mappings.get("circle") or {}
                                circle_keyword = clean_keyword(circle_mapping)
                                if circle_keyword:
                                    keywords.append(circle_keyword)
                                apply_mapping(clip, circle_mapping, item_name, options)

                            if options.get("writeKeywords", True) and item.get("scene"):
                                keywords.append("Scene_" + str(item.get("scene")))
                            if options.get("writeKeywords", True) and item.get("shot"):
                                keywords.append("Shot_" + str(item.get("shot")))

                            if options.get("writeKeywords", True):
                                keywords.extend(tags)
                            else:
                                keywords = []
                            if options.get("writeKeywords", True) and keywords:
                                set_metadata(clip, "Keywords", ",".join(keywords), item_name)

                        except Exception as e:
                            warnings.append("Failed to set metadata for %s: %s" % (item.get("name"), e))

                    if proxy_path and options.get("importProxies", True) and import_path != proxy_path:
                        if not os.path.exists(proxy_path):
                            missing_proxies.append({
                                "originalPath": original_path,
                                "proxyPath": proxy_path,
                            })
                            warnings.append("Proxy missing on disk: %s" % proxy_path)
                            continue
                        for clip in clips:
                            link_error = set_clip_proxy(clip, proxy_path)
                            if link_error is None:
                                linked_proxies += 1
                            else:
                                failed_proxy_links.append({
                                    "originalPath": original_path,
                                    "proxyPath": proxy_path,
                                    "error": link_error,
                                })

            if payload.get("generateStarterTimeline", False) and timeline_clips:
                try:
                    media_pool.SetCurrentFolder(scene_root)
                except Exception:
                    pass
                timeline_name = payload.get("timelineName", "Day01_Assembly")
                try:
                    timeline = media_pool.CreateTimelineFromClips(timeline_name, timeline_clips)
                except Exception as exc:
                    timeline = None
                    warnings.append("Could not create starter timeline: %s" % exc)

                lut_payload = payload.get("lut") or {}
                if timeline and lut_payload.get("enabled") and lut_payload.get("path"):
                    try:
                        project.RefreshLUTList()
                    except Exception:
                        pass
                    lut_path = lut_payload.get("path")
                    try:
                        track_count = timeline.GetTrackCount("video") or 0
                        for v_idx in range(1, track_count + 1):
                            items = timeline.GetItemListInTrack("video", v_idx) or []
                            for ti in items:
                                try:
                                    if not ti.SetLUT(1, lut_path):
                                        warnings.append("LUT copied but not applied for clip %s" % ti.GetName())
                                except Exception as exc:
                                    warnings.append("SetLUT failed: %s" % exc)
                    except Exception as exc:
                        warnings.append("LUT pass skipped: %s" % exc)

            try:
                project_manager.SaveProject()
            except Exception:
                pass

            emit_result({
                "ok": True,
                "projectName": project_name,
                "importedOriginals": imported_originals,
                "linkedProxies": linked_proxies,
                "missingProxies": missing_proxies,
                "failedProxyLinks": failed_proxy_links,
                "failedMedia": failed_media,
                "warnings": warnings,
            })


        if __name__ == "__main__":
            main()
        """
        return header + body
    }
}
