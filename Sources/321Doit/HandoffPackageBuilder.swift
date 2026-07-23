import Foundation

// MARK: - Post-handoff package builder
//
// Lays out the `05_HANDOFF/` folder and writes `manifest.json`,
// `Resolve/{PROJECT_TIME_ATTRIBUTE.json, PROJECT_TIME_ATTRIBUTE.py, README}` and
// `FinalCutPro/{PROJECT_TIME_ATTRIBUTE.fcpxmld, PROJECT_TIME_ATTRIBUTE.fcpxml, README}` according to
// the user's HandoffSettings.

enum HandoffPackageBuilder {

    /// Build the handoff package inside `target.outputURL`. Idempotent — overwrites
    /// previous artifacts in the same destination.
    static func build(
        offload: OffloadSettings,
        target: TargetReport,
        files: [FileCopyRecord]
    ) async throws -> HandoffOutput {
        let handoff = offload.handoff
        guard handoff.target != .none else {
            return HandoffOutput(rootURL: OffloadPackageLayout.handoffRoot(outputURL: target.outputURL))
        }

        let handoffRoot = OffloadPackageLayout.handoffRoot(outputURL: target.outputURL)
        try FileManager.default.createDirectory(at: handoffRoot, withIntermediateDirectories: true)

        var warnings: [String] = []

        // Stage the LUT before manifest generation so manifest.json can point at
        // the portable handoff copy instead of a user-local source path.
        if handoff.importLUT, let lutPath = offload.transcodeProfile.lutPath, !lutPath.isEmpty {
            stageLUT(into: handoffRoot.appendingPathComponent("LUT", isDirectory: true), source: lutPath, warnings: &warnings)
        }

        var scriptLogProject: Project?
        if handoff.injectScriptLogMetadata {
            scriptLogProject = loadScriptLogProject()
        }

        let manifest = await HandoffManifestBuilder.make(
            offload: offload,
            target: target,
            files: files,
            scriptLogProject: scriptLogProject
        )

        // Always write manifest.json — it is the single source of truth.
        let manifestURL = handoffRoot.appendingPathComponent("manifest.json")
        try HandoffManifestBuilder.write(manifest: manifest, to: manifestURL)

        var output = HandoffOutput(rootURL: handoffRoot, manifestURL: manifestURL)
        try writeSceneSortScript(into: handoffRoot)

        if handoff.target.includesResolve && handoff.generateImportScripts {
            let resolveDir = handoffRoot.appendingPathComponent("Resolve", isDirectory: true)
            let res = try HandoffResolveBuilder.write(
                manifest: manifest,
                offload: offload,
                target: target,
                into: resolveDir
            )
            output.resolveJSONURL = res.jsonURL
            output.resolveScriptURL = res.pyURL
        }

        if handoff.target.includesFinalCut {
            let fcpDir = handoffRoot.appendingPathComponent("FinalCutPro", isDirectory: true)
            let res = try FCPXMLBuilder.write(
                manifest: manifest,
                offload: offload,
                into: fcpDir
            )
            output.fcpxmldURL = res.fcpxmld
            output.fcpxmlCompatURL = res.compat
        }

        output.warnings = warnings
        return output
    }

    private static func writeSceneSortScript(into handoffRoot: URL) throws {
        let scriptURL = handoffRoot.appendingPathComponent("按拍摄计划归类.command")
        try sceneSortScript()
            .write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptURL.path
        )
    }

    private static func sceneSortScript() -> String {
        #"""
        #!/bin/zsh
        set -e

        SCRIPT_DIR="${0:A:h}"
        MANIFEST="$SCRIPT_DIR/manifest.json"

        DEST=$(/usr/bin/osascript -e 'POSIX path of (choose folder with prompt "选择要按拍摄计划归类的目标盘或文件夹")') || exit 0
        /usr/bin/python3 - "$MANIFEST" "$DEST" <<'PY'
        import json
        import os
        import sys

        manifest_path = sys.argv[1]
        destination = os.path.abspath(sys.argv[2])

        def clean(value, fallback):
            text = str(value or "").strip() or fallback
            for char in '/\\:*?"<>|':
                text = text.replace(char, "_")
            return text

        def unique_path(path):
            if not os.path.lexists(path):
                return path
            root, ext = os.path.splitext(path)
            index = 2
            while True:
                candidate = f"{root}_{index}{ext}"
                if not os.path.lexists(candidate):
                    return candidate
                index += 1

        with open(manifest_path, "r", encoding="utf-8") as fp:
            manifest = json.load(fp)

        project_name = clean((manifest.get("project") or {}).get("name"), "321Doit")
        root = os.path.join(destination, f"{project_name}_按拍摄计划归类")
        os.makedirs(root, exist_ok=True)

        linked = 0
        missing = []
        for item in manifest.get("media", []):
            metadata = item.get("metadata") or {}
            original = item.get("original") or {}
            source = original.get("path")
            if not source or not os.path.exists(source):
                missing.append(source or "(empty)")
                continue

            scene = clean(metadata.get("scene"), "未匹配场次")
            shot = clean(metadata.get("shot"), "未匹配镜头")
            take = clean(metadata.get("take"), "")
            camera = clean(metadata.get("cameraAngle"), "")
            status = clean(metadata.get("status"), "")

            folder = os.path.join(root, f"{scene}场" if not scene.endswith("场") and scene != "未匹配场次" else scene,
                                  f"{shot}镜" if not shot.endswith("镜") and shot != "未匹配镜头" else shot)
            os.makedirs(folder, exist_ok=True)

            prefix_parts = [part for part in [status.upper(), camera, f"T{take}" if take else ""] if part]
            filename = clean("_".join(prefix_parts + [os.path.basename(source)]), os.path.basename(source))
            target = unique_path(os.path.join(folder, filename))

            try:
                os.link(source, target)
            except Exception:
                os.symlink(source, target)
            linked += 1

        readme = os.path.join(root, "归类说明.txt")
        with open(readme, "w", encoding="utf-8") as fp:
            fp.write("321Doit 已按 场次 > 镜头 归类素材。\n")
            fp.write("优先创建硬链接；跨盘时创建指向已校验素材的符号链接。\n")
            fp.write(f"已归类: {linked}\n")
            if missing:
                fp.write("缺失素材:\n")
                for path in missing:
                    fp.write(f"- {path}\n")

        print(f"完成: {root}")
        PY

        /usr/bin/osascript -e 'display notification "按拍摄计划归类完成" with title "321Doit"'
        """#
    }

    private static func loadScriptLogProject() -> Project? {
        guard let folderPath = UserDefaults.standard.string(forKey: "321doit.scriptLog.projectFolder") else {
            return nil
        }

        let folder = URL(fileURLWithPath: folderPath)
        guard let project = try? ProjectRepository.load(from: folder) else { return nil }
        return project.shootingDays.isEmpty ? nil : project
    }

    // MARK: - LUT staging

    private static func stageLUT(into dir: URL, source path: String, warnings: inout [String]) {
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                return
            }
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.copyItem(atPath: path, toPath: dest.path)
            } else {
                warnings.append("LUT not found on disk: \(path)")
            }
        } catch {
            warnings.append("Could not stage LUT: \(error.localizedDescription)")
        }
    }
}
