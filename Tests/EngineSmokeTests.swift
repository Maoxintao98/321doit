import AppKit
import CoreGraphics
import CryptoKit
import Foundation

@main
struct EngineSmokeTests {
    static func main() async throws {
        try testXXHash64()
        try testChecksumAlgorithms()
        try testC4Hash()
        try testSparkleSignatureRoundTrip()
        try testAppcastParserExtractsSignedEnclosure()
        try testNamingAndFiltering()
        try testSourceSymlinkRejected()
        try testOutputFileNamer()
        try testApplicationLogger()
        try testLUTFiltergraphEscaping()
        try testFFmpegLocatorFallback()
        try testScriptLogExporter()
        try testProjectRepositoryCanonicalSnapshot()
        try testFCPXMLHandoffRendering()
        try await testOffloadEngine()
        try await testAscMHLv2Layout()
        try await testAscMHLv2OfficialCrossValidation()
        try await testTemporaryCleanup()
        try await testManifestThrottle()
        try await testStrictResumeDetectsSameSizeSameMTimeTamper()
        try await testMultiTargetPartialFailure()
        try await testReportWriteFailureIsNotSuccess()
        try await testAuditLogGeneration()
        try await testCJKAndEmojiPaths()
        try await testCancellationDuringCopy()
        try testMediaProbeParsing()
        try testMediaCompatibilityMatrix()
        try testMediaReencodeFlags()
        try testMediaL10nKeys()
        try testStoryboardCommandBus()
        try testLivingStoryboardNormalization()
        try testLivingStoryboardNextShotInheritance()
        try testStoryboardMarkdownRendering()
        try testStoryboardIMEPlaceholderState()
        try testStoryboardAtomicTransactions()
        try testStoryboardLocksAndRevisions()
        try testStoryboardPersistence()
        try testStoryboardLayerValidation()
        try testStoryboardAnimaticCanvasCaching()
        try testStoryboardFieldSpecificLocks()
        try testStoryboardPatchLifecycle()
        try testStoryboardDeterministicAnalysisAndExports()
        try await testMediaProbeIntegration()
        try await testMediaConversionPipelineIntegration()
        if ProcessInfo.processInfo.environment["RUN_PDF_SAMPLES"] == "1" {
            try await testPDFPaginationSamples()
        }
        print("321Doit smoke tests passed")
    }

    private static func testStoryboardCommandBus() throws {
        let scene = StoryboardScene(sceneNumber: "1", title: "码头", location: "外景")
        var bus = try StoryboardCommandBus(document: StoryboardDocument(title: "测试分镜"))

        try bus.apply(StoryboardTransaction(
            baseRevision: bus.document.revision,
            source: .ui,
            title: "新增场次",
            mutations: [.addScene(scene: scene, index: nil)]
        ))
        try expect(bus.document.scenes.count == 1, "Storyboard scene should be added")
        try expect(bus.document.revision == 1, "Storyboard revision should advance after a transaction")

        let shot = StoryboardShot(
            shotNumber: "1A",
            description: "主角走入画面",
            durationSeconds: 4,
            shotSize: .wide,
            cameraAngle: .low
        )
        try bus.apply(StoryboardTransaction(
            baseRevision: bus.document.revision,
            source: .wheel,
            title: "新增镜头",
            mutations: [.addShot(sceneID: scene.id, shot: shot, index: nil)]
        ))
        try expect(bus.document.scenes[0].shots.first == shot, "Storyboard shot should be added")
        try expect(bus.canUndo, "Storyboard command bus should expose undo")

        _ = bus.undo()
        try expect(bus.document.scenes[0].shots.isEmpty, "Undo should remove the added shot")
        let undoRevision = bus.document.revision
        _ = bus.redo()
        try expect(bus.document.scenes[0].shots.count == 1, "Redo should restore the added shot")
        try expect(bus.document.revision == undoRevision + 1, "Undo/redo must keep revisions monotonic")
    }

    private static func testLivingStoryboardNormalization() throws {
        let first = StoryboardShot(shotNumber: "8A", title: "雨中入画")
        let second = StoryboardShot(shotNumber: "8B", description: "切到近景", title: "人物反应")
        let scene = StoryboardScene(sceneNumber: "8", shots: [first, second])
        let normalized = scene.livingStoryboardNormalizedShots

        try expect(normalized.map(\.shotNumber) == ["1", "2"], "Living Storyboard shot numbers must be scene-local integers")
        try expect(normalized[0].description == "雨中入画", "Legacy shot title should move into the content field")
        try expect(normalized[1].description == "人物反应\n\n切到近景", "Legacy title and description should both be preserved")
        try expect(normalized.allSatisfy { $0.title == nil }, "Living Storyboard should remove the obsolete shot title field")
    }

    private static func testLivingStoryboardNextShotInheritance() throws {
        let assetID = UUID()
        let character = StoryboardCharacterInstance(
            name: "主角",
            position: StoryboardPoint(x: 0.4, y: 0.6)
        )
        let camera = StoryboardCameraPlacement(
            name: "A 机",
            position: StoryboardPoint(x: 0.2, y: 0.8)
        )
        let blockingText = StoryboardMovementPath(
            subjectID: character.id,
            points: [
                StoryboardPoint(x: 0.2, y: 0.2),
                StoryboardPoint(x: 0.5, y: 0.35)
            ],
            note: "blocking-text",
            kind: .prop,
            displayText: "门口",
            fontSize: 32
        )
        let annotation = StoryboardAnnotation(
            kind: .freehand,
            points: [StoryboardPoint(x: 0.1, y: 0.1), StoryboardPoint(x: 0.9, y: 0.9)]
        )
        let previous = StoryboardShot(
            shotNumber: "1",
            description: "主角走进门",
            durationSeconds: 4.5,
            shotSize: .wide,
            cameraAngle: .low,
            lens: "35mm",
            frame: StoryboardFrame(assetID: assetID),
            canvasElements: [StoryboardCanvasElement(assetID: assetID)],
            characters: [character],
            cameraPlacements: [camera],
            cameraMotions: [StoryboardCameraMotion(kind: .dolly)],
            movementPaths: [blockingText],
            annotations: [annotation],
            annotationLayers: [StoryboardAnnotationLayer(annotationIDs: [annotation.id])],
            audioCues: [StoryboardAudioCue(kind: .ambience, text: "雨声")],
            notes: "夜戏",
            title: "旧镜头标题",
            directorIntent: "保持压迫感",
            soundDescription: "雨声与脚步",
            expectedTakes: 3,
            productionDifficulty: 2,
            specialEquipment: ["轨道"]
        )

        let next = previous.nextShotCopy(shotNumber: "2")
        try expect(next.id != previous.id && next.shotNumber == "2", "Next shot must receive a new identity and sequential number")
        try expect(next.description.isEmpty && next.title == nil, "Next shot content must start empty")
        try expect(next.frame == StoryboardFrame(), "Next shot frame asset must start empty")
        try expect(next.canvasElements == nil && next.annotations.isEmpty, "Next shot artwork must start empty")
        try expect(next.annotationLayers == nil && next.canvasLayerOrder == nil, "Next shot artwork layers must start empty")
        try expect(next.soundDescription == nil && next.audioCues.isEmpty, "Next shot sound must start empty")
        try expect(next.durationSeconds == previous.durationSeconds, "Next shot duration must inherit")
        try expect(next.shotSize == previous.shotSize && next.cameraAngle == previous.cameraAngle, "Next shot shot size and angle must inherit")
        try expect(next.lens == previous.lens && next.cameraMotions.map(\.kind) == previous.cameraMotions.map(\.kind), "Next shot lens and camera motion must inherit")
        try expect(next.characters.map(\.name) == previous.characters.map(\.name), "Next shot characters must inherit")
        try expect(next.cameraPlacements?.map(\.name) == previous.cameraPlacements?.map(\.name), "Next shot cameras must inherit")
        try expect(next.movementPaths.map(\.displayText) == previous.movementPaths.map(\.displayText), "Next shot blocking paths and text must inherit")
        try expect(next.characters[0].id != previous.characters[0].id, "Inherited characters must receive fresh identifiers")
        try expect(next.cameraPlacements?[0].id != previous.cameraPlacements?[0].id, "Inherited cameras must receive fresh identifiers")
        try expect(next.cameraMotions[0].id != previous.cameraMotions[0].id, "Inherited camera motions must receive fresh identifiers")
        try expect(next.movementPaths[0].id != previous.movementPaths[0].id, "Inherited blocking paths must receive fresh identifiers")
        try expect(next.movementPaths[0].subjectID == next.characters[0].id, "Inherited path subjects must point to the duplicated subject")
        try expect(next.notes == previous.notes && next.directorIntent == previous.directorIntent, "Next shot production notes must inherit")
        try expect(next.expectedTakes == previous.expectedTakes && next.specialEquipment == previous.specialEquipment, "Next shot production settings must inherit")
        try StoryboardCommandBus.validate(
            StoryboardDocument(
                scenes: [StoryboardScene(sceneNumber: "1", shots: [previous, next])],
                assets: [StoryboardAsset(id: assetID, name: "测试画面")]
            )
        )

        let encodedPath = try JSONEncoder().encode(blockingText)
        let decodedPath = try JSONDecoder().decode(StoryboardMovementPath.self, from: encodedPath)
        try expect(decodedPath == blockingText, "Blocking text and font size must survive project save and reload")
    }

    private static func testStoryboardMarkdownRendering() throws {
        let markdown = "**主角入画**，随后 ~~停下~~"
        try expect(
            StoryboardMarkdownRendering.plainText(from: markdown) == "主角入画，随后 停下",
            "Storyboard summaries must not expose Markdown delimiters"
        )
    }

    private static func testStoryboardIMEPlaceholderState() throws {
        try expect(
            StoryboardRichTextMetrics.editorParagraphStyle.lineHeightMultiple == 1.5,
            "Storyboard rich-text editor must retain 1.5x line spacing"
        )

        let textView = StoryboardRichNSTextView()
        var placeholderIsVisible = true
        textView.contentStateChanged = { placeholderIsVisible = $0 }

        textView.setMarkedText(
            "feng c",
            selectedRange: NSRange(location: 6, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        try expect(
            !placeholderIsVisible,
            "Storyboard placeholder must hide while an input method is composing marked text"
        )

        textView.unmarkText()
        textView.string = ""
        textView.didChangeText()
        try expect(
            placeholderIsVisible,
            "Storyboard placeholder should return after committed content is deleted"
        )
    }

    private static func testStoryboardAtomicTransactions() throws {
        let scene = StoryboardScene(sceneNumber: "7")
        var bus = try StoryboardCommandBus(document: StoryboardDocument(scenes: [scene]))
        let validShot = StoryboardShot(shotNumber: "7A")
        let invalidShot = StoryboardShot(shotNumber: "7B", durationSeconds: 0)
        let before = bus.document

        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: before.revision,
                source: .ui,
                title: "批量新增镜头",
                mutations: [
                    .addShot(sceneID: scene.id, shot: validShot, index: nil),
                    .addShot(sceneID: scene.id, shot: invalidShot, index: nil)
                ]
            ))
            throw TestFailure("Invalid storyboard transaction should fail")
        } catch let error as StoryboardCommandError {
            guard case .invalidValue = error else {
                throw TestFailure("Unexpected storyboard validation error: \(error)")
            }
        }

        try expect(bus.document == before, "Failed storyboard transaction must not partially mutate data")
    }

    private static func testStoryboardLocksAndRevisions() throws {
        let shot = StoryboardShot(shotNumber: "3A")
        let scene = StoryboardScene(sceneNumber: "3", shots: [shot])
        let lock = StoryboardFieldLock(entityID: shot.id, field: "description")
        var bus = try StoryboardCommandBus(
            document: StoryboardDocument(scenes: [scene], fieldLocks: [lock])
        )
        var changed = shot
        changed.description = "Agent 不应覆盖"

        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: bus.document.revision,
                source: .agent,
                title: "Agent 修改镜头",
                mutations: [.updateShot(sceneID: scene.id, shotID: shot.id, shot: changed)]
            ))
            throw TestFailure("Agent must not overwrite a locked storyboard entity")
        } catch StoryboardCommandError.lockedEntity {
            // Expected.
        }

        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: bus.document.revision,
                source: .agent,
                title: "Agent 删除场次",
                mutations: [.removeScene(sceneID: scene.id)]
            ))
            throw TestFailure("Agent must not delete a scene containing a locked shot")
        } catch StoryboardCommandError.lockedEntity {
            // Expected.
        }

        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: bus.document.revision,
                source: .agent,
                title: "Agent 解除锁定",
                mutations: [.setFieldLock(lock: lock, isLocked: false)]
            ))
            throw TestFailure("Agent must not change user locks")
        } catch StoryboardCommandError.invalidValue {
            // Expected.
        }

        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: 99,
                source: .ui,
                title: "过期修改",
                mutations: [.updateShot(sceneID: scene.id, shotID: shot.id, shot: changed)]
            ))
            throw TestFailure("Stale storyboard transaction should fail")
        } catch StoryboardCommandError.staleRevision(let expected, let received) {
            try expect(expected == 0 && received == 99, "Stale revision should report both revisions")
        }
    }

    private static func testStoryboardPersistence() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-storyboard-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let assetVersion = StoryboardAssetVersion(
            relativePath: "assets/frame-001.png",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            source: "import"
        )
        let asset = StoryboardAsset(name: "首帧", versions: [assetVersion])
        let freehand = StoryboardAnnotation(
            kind: .freehand,
            points: [
                StoryboardPoint(x: 0.1, y: 0.2),
                StoryboardPoint(x: 0.7, y: 0.8)
            ],
            colorHex: "#FF3B30"
        )
        let arrow = StoryboardAnnotation(
            kind: .arrow,
            points: [
                StoryboardPoint(x: 0.2, y: 0.8),
                StoryboardPoint(x: 0.8, y: 0.2)
            ],
            colorHex: "#0A84FF"
        )
        let canvasElement = StoryboardCanvasElement(assetID: asset.id, flippedHorizontally: true)
        let drawingLayer = StoryboardAnnotationLayer(name: "绘画 1", annotationIDs: [freehand.id, arrow.id])
        let shot = StoryboardShot(
            shotNumber: "1A",
            shotSize: .closeUp,
            cameraAngle: .low,
            frame: StoryboardFrame(assetID: asset.id),
            canvasElements: [canvasElement],
            cameraPlacements: [
                StoryboardCameraPlacement(
                    name: "A 机",
                    position: StoryboardPoint(x: 0.2, y: 0.8),
                    rotationDegrees: -32,
                    fieldOfViewDegrees: 48,
                    equivalentFocalLengthMM: 50,
                    range: 0.5
                )
            ],
            cameraMotions: [StoryboardCameraMotion(kind: .dolly)],
            annotations: [freehand, arrow],
            annotationLayers: [drawingLayer],
            canvasLayerOrder: [
                StoryboardCanvasLayerReference(id: drawingLayer.id, kind: .drawing),
                StoryboardCanvasLayerReference(id: canvasElement.id, kind: .image)
            ]
        )
        let document = StoryboardDocument(
            title: "持久化测试",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            revision: 4,
            scenes: [StoryboardScene(sceneNumber: "1", shots: [shot])],
            assets: [asset]
        )
        let url = root.appendingPathComponent("storyboard.json")
        try StoryboardRepository.save(document, to: url)
        let loaded = try StoryboardRepository.load(from: url)
        try expect(loaded == document, "Storyboard JSON should round-trip without losing structure")
        try expect(loaded.scenes[0].shots[0].annotations.count == 2, "Storyboard drawing should persist")
        try expect(loaded.scenes[0].shots[0].annotationLayers?.first?.annotationIDs.count == 2, "Storyboard drawing layer should persist")
        try expect(loaded.scenes[0].shots[0].canvasLayerOrder?.map(\.id) == [drawingLayer.id, canvasElement.id], "Unified canvas layer order should persist")
        try expect(loaded.scenes[0].shots[0].canvasElements?.first?.flippedHorizontally == true, "Canvas element transforms should persist")
        try expect(loaded.scenes[0].shots[0].cameraPlacements?.first?.name == "A 机", "Camera placement should persist")
        try expect(loaded.scenes[0].shots[0].cameraPlacements?.first?.equivalentFocalLengthMM == 50, "Equivalent focal length should persist")
        try expect(loaded.scenes[0].shots[0].cameraMotions.first?.kind == .dolly, "Director wheel motion should persist")

        do {
            _ = try StoryboardRepository.resolveAssetURL(
                relativePath: "../outside.png",
                storyboardURL: url
            )
            throw TestFailure("Storyboard asset paths must not escape the project directory")
        } catch StoryboardCommandError.invalidValue {
            // Expected.
        }

        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("321doit-storyboard-outside-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let symlink = root.appendingPathComponent("linked-assets")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: outside)
        do {
            _ = try StoryboardRepository.resolveAssetURL(
                relativePath: "linked-assets/outside.png",
                storyboardURL: url
            )
            throw TestFailure("Storyboard asset paths must not escape through symbolic links")
        } catch StoryboardCommandError.invalidValue {
            // Expected.
        }

        var updatedDocument = document
        updatedDocument.title = "第二版分镜"
        updatedDocument.revision += 1
        try StoryboardRepository.save(updatedDocument, to: url)
        try Data("corrupt storyboard".utf8).write(to: url, options: .atomic)
        let recoveredStoryboard = try StoryboardRepository.load(from: url)
        try expect(recoveredStoryboard == document, "A corrupt storyboard must recover from its newest valid local backup")
    }

    private static func testStoryboardLayerValidation() throws {
        let annotation = StoryboardAnnotation(
            kind: .freehand,
            points: [StoryboardPoint(x: 0.1, y: 0.1), StoryboardPoint(x: 0.9, y: 0.9)]
        )
        let shot = StoryboardShot(
            shotNumber: "1A",
            annotations: [annotation],
            annotationLayers: [
                StoryboardAnnotationLayer(name: "绘画 1", annotationIDs: [annotation.id]),
                StoryboardAnnotationLayer(name: "绘画 2", annotationIDs: [annotation.id])
            ]
        )
        do {
            try StoryboardCommandBus.validate(
                StoryboardDocument(scenes: [StoryboardScene(sceneNumber: "1", shots: [shot])])
            )
            throw TestFailure("A storyboard annotation must not belong to multiple drawing layers")
        } catch StoryboardCommandError.invalidValue {
            // Expected.
        }
    }

    private static func testStoryboardAnimaticCanvasCaching() throws {
        let assetID = UUID()
        let image = NSImage(size: NSSize(width: 16, height: 9))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 9).fill()
        image.unlockFocus()

        let scene = StoryboardScene(
            sceneNumber: "1",
            shots: [
                StoryboardShot(shotNumber: "1A", durationSeconds: 0.1, frame: StoryboardFrame(assetID: assetID)),
                StoryboardShot(shotNumber: "1B", durationSeconds: 0.1, frame: StoryboardFrame(assetID: assetID))
            ]
        )
        let output = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-animatic-cache-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        var resolverCalls = 0
        try StoryboardAnimaticExporter.export(
            scene: scene,
            to: output,
            ffmpegURL: URL(fileURLWithPath: "/usr/bin/true"),
            imageResolver: { id in
                guard id != nil else { return nil }
                resolverCalls += 1
                return image
            }
        )
        try expect(resolverCalls == scene.shots.count, "Animatic canvas should be composed once per shot")
    }

    private static func testStoryboardFieldSpecificLocks() throws {
        let shot = StoryboardShot(shotNumber: "8A", durationSeconds: 3, shotSize: .wide)
        let scene = StoryboardScene(sceneNumber: "8", shots: [shot])
        let lock = StoryboardFieldLock(entityID: shot.id, field: "shotSize")
        var bus = try StoryboardCommandBus(document: StoryboardDocument(scenes: [scene], fieldLocks: [lock]))

        var durationOnly = shot
        durationOnly.durationSeconds = 4
        try bus.apply(StoryboardTransaction(
            baseRevision: bus.document.revision,
            source: .ui,
            title: "调整未锁定时长",
            mutations: [.updateShot(sceneID: scene.id, shotID: shot.id, shot: durationOnly)]
        ))
        try expect(bus.document.shot(id: shot.id)?.durationSeconds == 4, "A field lock must not block unrelated fields")

        var forbidden = durationOnly
        forbidden.shotSize = .closeUp
        do {
            try bus.apply(StoryboardTransaction(
                baseRevision: bus.document.revision,
                source: .ui,
                title: "修改锁定景别",
                mutations: [.updateShot(sceneID: scene.id, shotID: shot.id, shot: forbidden)]
            ))
            throw TestFailure("UI must not bypass a field lock")
        } catch StoryboardCommandError.lockedEntity {
            // Expected.
        }
    }

    private static func testStoryboardPatchLifecycle() throws {
        let a = StoryboardShot(shotNumber: "9A", description: "建立", durationSeconds: 4)
        let b = StoryboardShot(shotNumber: "9B", description: "重复反应", durationSeconds: 3)
        let c = StoryboardShot(shotNumber: "9C", description: "关键落点", durationSeconds: 5)
        let scene = StoryboardScene(sceneNumber: "9", shots: [a, b, c], targetDurationSeconds: 8)
        let document = StoryboardDocument(scenes: [scene])
        var changedA = a
        changedA.durationSeconds = 3
        let patch = StoryboardPatch(
            projectID: document.id,
            sceneID: scene.id,
            baseRevision: document.revision,
            description: "压缩节奏",
            operations: [
                StoryboardPatchOperation(kind: .updateShot(sceneID: scene.id, shotID: a.id, replacement: changedA), reason: "缩短建立", risk: .low),
                StoryboardPatchOperation(kind: .deleteShot(sceneID: scene.id, shotID: b.id), reason: "信息重复", risk: .high)
            ],
            constraints: StoryboardPatchConstraints(maximumDurationSeconds: 8, lockedShotIDs: [c.id]),
            agentName: "test",
            model: "deterministic",
            userInstruction: "压缩到8秒"
        )
        let preview = try StoryboardPatchEngine.preview(patch, in: document)
        try expect(preview.afterShotCount == 2, "Patch preview must simulate deletion")
        try expect(abs(preview.afterDurationSeconds - 8) < 0.001, "Patch preview must calculate resulting duration")
        try expect(preview.diffs.count == 2, "Patch preview must expose per-operation diffs")

        var bus = try StoryboardCommandBus(document: document)
        let mutations = try StoryboardPatchEngine.mutations(for: patch, in: document, accepting: preview.acceptedOperationIDs)
        try bus.apply(StoryboardTransaction(
            id: patch.id,
            baseRevision: patch.baseRevision,
            source: .agent,
            title: patch.description,
            mutations: mutations
        ))
        try expect(bus.document.scene(id: scene.id)?.shots.count == 2, "Accepted patch must apply atomically")
        _ = bus.undo()
        try expect(bus.document.scene(id: scene.id)?.shots == scene.shots, "A patch must undo as one transaction")

        var stale = patch
        stale.baseRevision = 99
        do {
            _ = try StoryboardPatchEngine.preview(stale, in: document)
            throw TestFailure("Stale patch must not preview")
        } catch StoryboardCommandError.staleRevision {
            // Expected.
        }
    }

    private static func testStoryboardDeterministicAnalysisAndExports() throws {
        let a = StoryboardShot(
            shotNumber: "10A",
            description: "人物向右离画",
            durationSeconds: 0.3,
            shotSize: .extremeWide,
            screenDirection: .leftToRight
        )
        let b = StoryboardShot(
            shotNumber: "10B",
            description: "人物反向进入",
            durationSeconds: 2,
            shotSize: .extremeCloseUp,
            screenDirection: .rightToLeft,
            productionDifficulty: 5,
            specialEquipment: ["crane"]
        )
        let scene = StoryboardScene(sceneNumber: "10", shots: [a, b], targetDurationSeconds: 1)
        let document = StoryboardDocument(title: "分析导出", scenes: [scene])
        let issues = StoryboardAnalysisEngine.analyze(document: document)
        try expect(issues.contains { $0.category == .timing }, "Analysis must flag timing risk")
        try expect(issues.contains { $0.category == .continuity }, "Analysis must flag screen-direction/size continuity risk")
        try expect(issues.contains { $0.category == .production }, "Analysis must flag production difficulty/equipment risk")

        let csv = String(data: try StoryboardExporter.data(for: .csv, document: document, imageResolver: { _ in nil }), encoding: .utf8) ?? ""
        try expect(csv.contains("10A") && csv.contains("10B"), "CSV must include every shot")
        let otio = try JSONSerialization.jsonObject(with: StoryboardExporter.data(for: .otio, document: document, imageResolver: { _ in nil })) as? [String: Any]
        try expect(otio?["OTIO_SCHEMA"] != nil, "OTIO export must declare its schema")
    }

    private static func testScriptLogExporter() throws {
        let take = Take(
            sceneNumber: "12",
            shotNumber: "A",
            takeNumber: 3,
            cameraLabel: "B",
            status: .good,
            isCircleTake: true,
            pictureUsable: true,
            soundUsable: false,
            performanceRating: 5,
            technicalRating: 4,
            performanceNote: "strong performance",
            technicalNote: "boom shadow",
            generalNote: "director likes it",
            cameraRecords: [
                CameraRecord(
                    cameraLabel: "A机",
                    status: .good,
                    clipName: "A001_C003.mov",
                    cardName: "A001",
                    tcIn: "01:00:00:00",
                    tcOut: "01:00:10:00",
                    pictureAvailable: true,
                    audioAvailable: false,
                    notes: "main camera"
                )
            ],
            linkedClips: [
                ClipReference(
                    fileName: "A001_C003.mov",
                    filePath: "/Volumes/DIT/A001_C003.mov",
                    cameraCard: "A001",
                    checksum: "abc123",
                    proxyPath: "/Volumes/DIT/proxy/A001_C003.mov",
                    offloadSessionId: "session-1"
                )
            ],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let project = Project(
            name: "Script Log Test",
            productionName: "Unit",
            director: "Director",
            dp: "DP",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            shootingDays: [
                ShootingDay(
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    label: "Day 1",
                    scenes: [
                        ScriptScene(
                            sceneNumber: "12",
                            description: "Interior",
                            shots: [
                                Shot(
                                    shotNumber: "A",
                                    cameraSetup: "B",
                                    takes: [take]
                                )
                            ]
                        )
                    ]
                )
            ]
        )

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-script-log-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let csvURL = root.appendingPathComponent("script_log.csv")
        try ScriptLogExporter.writeCSV(project: project, to: csvURL)
        let csv = try String(contentsOf: csvURL, encoding: .utf8)
        try expect(csv.contains("项目,拍摄日,场次,镜头,条次,主机位,状态"), "Script Log CSV header missing")
        try expect(csv.contains("Script Log Test,Day 1,12,A,3,B,OK,是,是,否,5,4"), "Script Log CSV row missing key values")
        try expect(csv.contains("A机 OK"), "Script Log CSV should include camera records")
        try expect(csv.contains("A001_C003.mov"), "Script Log CSV should include linked clip file names")

        let jsonURL = root.appendingPathComponent("script_log.json")
        try ScriptLogExporter.writeJSON(project: project, to: jsonURL)
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        try expect(json.contains("\"shootingDays\""), "Script Log JSON should include shootingDays")
        try expect(json.contains("\"linkedClips\""), "Script Log JSON should include linkedClips")
    }

    private static func testOutputFileNamer() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone.current
        components.year = 2026
        components.month = 5
        components.day = 10
        components.hour = 12
        components.minute = 34
        components.second = 56
        guard let date = components.date else {
            throw TestFailure("Could not build deterministic date")
        }

        let name = OutputFileNamer.fileName(projectName: "Project A", date: date, attribute: "Copy Report", extension: "pdf")
        try expect(name == "PROJECT_A_20260510_123456_COPY_REPORT.pdf", "Unexpected output filename: \(name)")
    }

    private static func testXXHash64() throws {
        let empty = formatHash(XXHash64.hash(data: Data()))
        try expect(empty == "ef46db3751d8e999", "xxHash64 empty mismatch: \(empty)")

        let hello = formatHash(XXHash64.hash(data: Data("hello".utf8)))
        try expect(hello == "26c7827d889f6da3", "xxHash64 hello mismatch: \(hello)")

        let checksumHello = Checksum.hash(data: Data("hello".utf8), algorithm: .xxhash64)
        try expect(checksumHello == hello, "C xxHash64 sink mismatch: \(checksumHello)")

        let compatibilityHello = Checksum.hash(
            data: Data("hello".utf8),
            algorithm: .xxhash64,
            xxHash64Implementation: .compatibility
        )
        try expect(compatibilityHello == hello, "Swift xxHash64 compatibility mismatch: \(compatibilityHello)")
    }

    private static func testChecksumAlgorithms() throws {
        let hello = Data("hello".utf8)

        let md5 = Checksum.hash(data: hello, algorithm: .md5)
        try expect(md5 == "5d41402abc4b2a76b9719d911017c592", "MD5 hello mismatch: \(md5)")

        let sha256 = Checksum.hash(data: hello, algorithm: .sha256)
        try expect(sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824", "SHA-256 hello mismatch: \(sha256)")
    }

    private static func testC4Hash() throws {
        // Known values cross-checked against the reference ascmhl 1.2 Python
        // implementation. Empty file and "hello" cover the leading-zero
        // padding edge case as well as a typical non-zero digest.
        let empty = C4Hash.hash(data: Data())
        try expect(
            empty == "c459dsjfscH38cYeXXYogktxf4Cd9ibshE3BHUo6a58hBXmRQdZrAkZzsWcbWtDg5oQstpDuni4Hirj75GEmTc1sFT",
            "C4 hash of empty payload mismatch: \(empty)"
        )

        let hello = C4Hash.hash(data: Data("hello".utf8))
        try expect(
            hello == "c447Fm3BJZQ62765jMZJH4m28hrDM7Szbj9CUmj4F4gnvyDYXYz4WfnK2nYRhFvRgYEectEXYBYWLDpLo6XGNAfKdt",
            "C4 hash of 'hello' mismatch: \(hello)"
        )

        try expect(empty.count == 90, "C4 hash must be 90 chars, got \(empty.count)")
        try expect(empty.hasPrefix("c4"), "C4 hash must start with 'c4'")

        // Streaming form should agree with in-memory form on the same payload.
        let streamingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("c4-stream-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: streamingURL) }
        try Data("hello".utf8).write(to: streamingURL)
        let streamed = try C4Hash.hashFile(at: streamingURL)
        try expect(streamed == hello, "C4 streaming form must match in-memory form: \(streamed) vs \(hello)")
    }

    /// Generates a fresh Curve25519 key pair, signs a payload with the
    /// CLI-side `SparkleEdSignature.sign`, and verifies it with the same
    /// helper the app uses at runtime. Catches drift between the signing
    /// pipeline and the runtime verifier — drift that would otherwise only
    /// surface as broken updates in production.
    private static func testSparkleSignatureRoundTrip() throws {
        // Generate ephemeral key for the test
        let priv = Curve25519.Signing.PrivateKey()
        let payload = Data("321Doit appcast roundtrip test \(UUID().uuidString)".utf8)
        let sig = try SparkleEdSignature.sign(artifact: payload, privateKeyRaw: priv.rawRepresentation)

        let pubKey = try SparkleEdSignature.makePublicKey(fromBase64: priv.publicKey.rawRepresentation.base64EncodedString())
        try SparkleEdSignature.verify(artifact: payload, signatureBase64: sig, publicKey: pubKey)

        // Tampering must surface as a thrown error, not a silently-passing verify.
        var tampered = payload
        tampered[0] ^= 0xFF
        var threwOnTamper = false
        do {
            try SparkleEdSignature.verify(artifact: tampered, signatureBase64: sig, publicKey: pubKey)
        } catch SparkleEdSignature.SignatureError.invalidSignature {
            threwOnTamper = true
        }
        try expect(threwOnTamper, "Tampered payload must fail Sparkle signature verification")
    }

    /// Builds a minimal Sparkle appcast XML in memory, parses it, and
    /// confirms the parser surfaces every field the runtime check needs:
    /// version, build, signed enclosure URL, signature, length, channel.
    private static func testAppcastParserExtractsSignedEnclosure() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <title>321Doit</title>
            <item>
              <title>321Doit 0.4.0</title>
              <pubDate>Thu, 07 May 2026 04:30:29 +0000</pubDate>
              <sparkle:releaseNotesLink>https://example.com/notes</sparkle:releaseNotesLink>
              <enclosure url="https://example.com/321Doit-0.4.0.dmg"
                         sparkle:shortVersionString="0.4.0"
                         sparkle:version="10"
                         length="123456"
                         type="application/octet-stream"
                         sparkle:edSignature="AAAA" />
            </item>
            <item>
              <title>321Doit 0.5beta1</title>
              <enclosure url="https://example.com/321Doit-0.5beta1.dmg"
                         sparkle:shortVersionString="0.5beta1"
                         sparkle:version="11"
                         length="654321"
                         sparkle:edSignature="BBBB" />
              <sparkle:channel>beta</sparkle:channel>
            </item>
          </channel>
        </rss>
        """
        let entries = try AppcastParser.parse(xmlData: Data(xml.utf8))
        try expect(entries.count == 2, "Parser must return both <item> entries")

        guard let stable = entries.first(where: { $0.version == "0.4.0" }) else {
            throw TestFailure("Stable 0.4.0 entry missing from parser output")
        }
        try expect(stable.build == "10", "build version mismatch: \(stable.build ?? "nil")")
        try expect(stable.downloadURL.absoluteString == "https://example.com/321Doit-0.4.0.dmg", "download URL mismatch: \(stable.downloadURL)")
        try expect(stable.signature == "AAAA", "signature mismatch: \(stable.signature)")
        try expect(stable.lengthBytes == 123456, "length mismatch: \(String(describing: stable.lengthBytes))")
        try expect(stable.releaseNotesURL?.absoluteString == "https://example.com/notes", "release notes URL mismatch")
        try expect(stable.isPrerelease == false, "0.4.0 should not be flagged as prerelease")

        guard let beta = entries.first(where: { $0.version == "0.5beta1" }) else {
            throw TestFailure("Beta entry missing from parser output")
        }
        try expect(beta.isPrerelease, "0.5beta1 should be flagged as prerelease (via version + channel)")

        // Version comparison sanity: the runtime check uses this to decide
        // whether to surface an update at all, so a regression here is a
        // silent "no updates" forever.
        try expect(UpdateChecker.versionCompare("0.4.0", "0.3beta2") == .orderedDescending, "0.4.0 should rank above 0.3beta2")
        try expect(UpdateChecker.versionCompare("0.3beta2", "0.3beta2") == .orderedSame, "Equal versions should compare equal")
        try expect(UpdateChecker.versionCompare("0.3beta1", "0.3beta2") == .orderedAscending, "0.3beta1 should rank below 0.3beta2")
        try expect(
            UpdateChecker.releaseCompare(version: "0.6", build: "17", toVersion: "0.6", build: "12") == .orderedDescending,
            "A newer internal build must be offered even when the short version is unchanged"
        )
        try expect(
            UpdateChecker.releaseCompare(version: "0.6", build: "12", toVersion: "0.6", build: "17") == .orderedAscending,
            "An older internal build must not replace a newer installed build"
        )
        try expect(
            UpdateChecker.releaseCompare(version: "0.7", build: "1", toVersion: "0.6", build: "999") == .orderedDescending,
            "Short version must take precedence over build number"
        )
    }

    private static func testNamingAndFiltering() throws {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 5
        components.day = 3
        let date = components.date!

        let name = makeOutputFolderName(project: "My Film", date: date, card: "A001")
        try expect(name == "MY_FILM_20260503_A001", "Unexpected output name: \(name)")
        try expect(isMacJunk(".DS_Store"), "Expected .DS_Store to be junk")
        try expect(isMacJunk("._clip.mov"), "Expected AppleDouble file to be junk")
        try expect(!isMacJunk("clip.mov"), "Expected media file to be kept")
        try expect(spreadsheetSafeCSVField("=1+1") == "'=1+1", "CSV formulas must be neutralized")
        try expect(spreadsheetSafeCSVField("@SUM(A1:A2)").hasPrefix("'@"), "CSV @ formulas must be neutralized")
        try expect(spreadsheetSafeCSVField("safe,value") == "\"safe,value\"", "CSV quoting must remain RFC 4180 compatible")
    }

    private static func testSourceSymlinkRejected() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-source-link-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let outside = root.appendingPathComponent("outside.txt")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try Data("private-local-data".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: source.appendingPathComponent("linked.mov"),
            withDestinationURL: outside
        )

        do {
            _ = try enumerateSourceFiles(at: source)
            throw TestFailure("Source enumeration must reject symbolic links")
        } catch OffloadError.unsafeSourceLink(_) {
            // Expected: a card must never be able to copy data outside its root.
        }
    }

    private static func testApplicationLogger() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-app-log-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let expired = root.appendingPathComponent("321Doit-2000-01-01.log")
        try Data("expired\n".utf8).write(to: expired)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 946_684_800)],
            ofItemAtPath: expired.path
        )

        AppLogger.configure(
            folderPath: root.path,
            retentionDays: 7,
            minimumLevel: .debug,
            writeText: true,
            writeJSON: true
        )
        AppLogger.log(.warning, category: "test", "diagnostic line one\nline two")

        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        guard let textURL = files.first(where: { $0.pathExtension == "log" }),
              let jsonURL = files.first(where: { $0.pathExtension == "jsonl" }) else {
            throw TestFailure("Application logger must write daily text and JSONL files")
        }
        try expect(textURL != expired, "Expired logs must be pruned using the retention policy")
        let text = try String(contentsOf: textURL, encoding: .utf8)
        try expect(text.contains("[WARN] [test] diagnostic line one\\nline two"), "Text diagnostics must be single-line and categorized")

        let jsonLine = try String(contentsOf: jsonURL, encoding: .utf8)
            .split(separator: "\n")
            .first
            .map(String.init) ?? ""
        let object = try JSONSerialization.jsonObject(with: Data(jsonLine.utf8)) as? [String: Any]
        try expect(object?["category"] as? String == "test", "JSONL diagnostics must preserve the category")
        try expect(object?["appVersion"] as? String == "0.7", "Application logs must carry the current internal version")
        try expect(object?["appBuild"] as? String == "1", "Application logs must carry the current internal build")
    }

    private static func testProjectRepositoryCanonicalSnapshot() throws {
        let parent = URL(fileURLWithPath: NSTemporaryDirectory())
        let folder = ProjectRepository.projectPackageURL(
            in: parent,
            projectName: "Atomic/Project-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: folder) }
        try expect(folder.pathExtension == "321doit", "Project packages must use the .321doit extension")
        try expect(!folder.lastPathComponent.contains("/"), "Project package names must be Finder-safe")
        let project = Project(
            name: "Atomic Project",
            productionName: "Production A",
            director: "Director",
            shootingDays: []
        )

        try ProjectRepository.save(project, to: folder)
        try expect(ProjectRepository.isProjectFolder(folder), "A saved .321doit package must be recognized as a project")
        try expect(
            FileManager.default.fileExists(atPath: ProjectRepository.projectStateJSONURL(for: folder).path),
            "Canonical project_state.json must be written"
        )
        try Data("corrupt legacy metadata".utf8).write(to: ProjectRepository.projectJSONURL(for: folder), options: .atomic)
        try Data("corrupt legacy log".utf8).write(to: ProjectRepository.scriptLogJSONURL(for: folder), options: .atomic)
        let loaded = try ProjectRepository.load(from: folder)
        try expect(loaded.id == project.id, "Canonical project ID must win over torn legacy files")
        try expect(loaded.name == project.name, "Canonical project metadata must win over torn legacy files")
        try expect(loaded.productionName == project.productionName, "Canonical production metadata must be preserved")
        try expect(loaded.shootingDays == project.shootingDays, "Canonical shooting days must win over torn legacy files")

        // A previous app version may legitimately edit both compatibility
        // files after the canonical snapshot. A consistent, newer pair must
        // be imported so downgrading never silently discards user changes.
        let legacyProject = Project(
            id: project.id,
            name: "Edited by Older Version",
            productionName: "Production B",
            director: "Legacy Director",
            shootingDays: []
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacyProject.metadataOnly)
            .write(to: ProjectRepository.projectJSONURL(for: folder), options: .atomic)
        try encoder.encode(ScriptLogDocument(
            projectID: legacyProject.id,
            shootingDays: legacyProject.shootingDays,
            updatedAt: Date()
        )).write(to: ProjectRepository.scriptLogJSONURL(for: folder), options: .atomic)

        let stateAttributes = try FileManager.default.attributesOfItem(
            atPath: ProjectRepository.projectStateJSONURL(for: folder).path
        )
        guard let stateDate = stateAttributes[.modificationDate] as? Date else {
            throw TestFailure("Canonical project snapshot must have a modification date")
        }
        let newerDate = stateDate.addingTimeInterval(10)
        for url in [ProjectRepository.projectJSONURL(for: folder), ProjectRepository.scriptLogJSONURL(for: folder)] {
            try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: url.path)
        }

        let downgradedEdit = try ProjectRepository.load(from: folder)
        try expect(downgradedEdit.id == legacyProject.id, "A consistent legacy pair must preserve the project ID")
        try expect(downgradedEdit.name == legacyProject.name, "A newer consistent legacy pair must win")
        try expect(downgradedEdit.productionName == legacyProject.productionName, "Newer legacy production metadata must be imported")

        // Saving a new revision keeps a throttled local history. If both the
        // canonical snapshot and compatibility pair later become unreadable,
        // the newest valid backup must prevent a blank-project fallback.
        try ProjectRepository.save(legacyProject, to: folder)
        try Data("corrupt canonical".utf8).write(to: ProjectRepository.projectStateJSONURL(for: folder), options: .atomic)
        try Data("corrupt metadata".utf8).write(to: ProjectRepository.projectJSONURL(for: folder), options: .atomic)
        try Data("corrupt log".utf8).write(to: ProjectRepository.scriptLogJSONURL(for: folder), options: .atomic)
        let recovered = try ProjectRepository.load(from: folder)
        try expect(recovered.id == project.id, "Project backup recovery must preserve identity")
        try expect(recovered.name == project.name, "Project backup recovery must return the last valid backed-up revision")
    }

    private static func testLUTFiltergraphEscaping() throws {
        let path = "/tmp/中文 空格/emoji😀/a'b\"c:d\\e,f[g].cube"
        let escaped = ProxyTranscoder.ffmpegFiltergraphEscapedPath(path)
        for required in ["\\ ", "\\'", "\\\"", "\\:", "\\\\", "\\,", "\\[", "\\]"] {
            try expect(escaped.contains(required), "Missing LUT filter escape \(required) in \(escaped)")
        }
        let filter = ProxyTranscoder.lut3dFilter(path: path, intensity: 0.5)
        try expect(filter.contains("lut3d=file="), "LUT filter should use explicit file option: \(filter)")
    }

    private static func testFFmpegLocatorFallback() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitFFmpegLocator-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let fakeFFmpeg = bin.appendingPathComponent("ffmpeg")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: fakeFFmpeg)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeFFmpeg.path)

        let invalidConfigured = root.appendingPathComponent("old/missing/ffmpeg").path
        let fallback = FFmpegLocator.executableURL(
            configuredPath: invalidConfigured,
            autoSearchPaths: [fakeFFmpeg.path]
        )
        try expect(fallback?.path == fakeFFmpeg.path, "Invalid custom FFmpeg path should fall back to auto-detect")

        let configuredDirectory = FFmpegLocator.executableURL(
            configuredPath: bin.path,
            autoSearchPaths: []
        )
        try expect(configuredDirectory?.path == fakeFFmpeg.path, "Configured FFmpeg directory should resolve bin/ffmpeg")
    }

    private static func testFCPXMLHandoffRendering() throws {
        var settings = OffloadSettings(
            projectName: "项目 中文",
            cardNumber: "A001",
            operatorName: "Unit Test",
            camera: "Sony FX6",
            location: "Stage",
            notes: "Handoff render test",
            sourceURL: URL(fileURLWithPath: "/tmp/source"),
            targetRoots: [URL(fileURLWithPath: "/tmp/target")],
            createdAt: Date(timeIntervalSince1970: 1_777_777_777),
            generateProxies: false
        )
        settings.handoff.target = .finalCut
        settings.handoff.frameRate = .fps25
        settings.handoff.resolution = .hd1080

        let originalPath = "/Volumes/RAID/项目 中文/01_ORIGINALS/A001/clip 1.mov"
        let proxyPath = "/Volumes/RAID/项目 中文/02_PROXY/A001/clip 1_proxy.mov"
        let audioPath = "/Volumes/RAID/项目 中文/03_AUDIO/sync.wav"
        let manifest = HandoffManifest(
            createdBy: .current(),
            project: HandoffProject(
                name: "项目 中文",
                shootDay: "Day01",
                date: "2026-05-06",
                frameRate: HandoffFrameRateInfo(display: "25", numerator: 25, denominator: 1),
                timeline: HandoffTimelineInfo(name: "Day01_Assembly", width: 1920, height: 1080, startTimecode: "01:00:00:00", dropFrame: false),
                color: HandoffColorInfo(mode: "Rec.709 / sRGB", lutPath: nil, applyLutOnImport: false)
            ),
            media: [
                HandoffMediaItem(
                    id: "A001_clip_0123456789abcdef",
                    cardId: "A001",
                    camera: HandoffCamera(vendor: "Sony", model: "FX6", reel: "A001"),
                    original: HandoffMediaFile(
                        path: originalPath,
                        fileUrl: HandoffURL.fileURL(forAbsolutePath: originalPath),
                        filename: "clip 1.mov",
                        sizeBytes: 123,
                        codec: "apcn",
                        width: 3840,
                        height: 2160,
                        durationFrames: 250,
                        durationSeconds: 10,
                        startTimecode: "01:00:00:00",
                        hasVideo: true,
                        hasAudio: true,
                        audioChannels: 2,
                        audioSampleRate: 48000
                    ),
                    proxy: HandoffMediaProxy(
                        path: proxyPath,
                        fileUrl: HandoffURL.fileURL(forAbsolutePath: proxyPath),
                        exists: true,
                        codec: "ProRes 422 Proxy"
                    ),
                    hashes: HandoffHashes(algorithm: "xxh64", value: "0123456789abcdef"),
                    metadata: HandoffMetadata(scene: "", shot: "", take: "", cameraAngle: "", notes: "")
                ),
                HandoffMediaItem(
                    id: "A001_sync_fedcba9876543210",
                    cardId: "A001",
                    camera: HandoffCamera(vendor: "Sony", model: "FX6", reel: "A001"),
                    original: HandoffMediaFile(
                        path: audioPath,
                        fileUrl: HandoffURL.fileURL(forAbsolutePath: audioPath),
                        filename: "sync.wav",
                        sizeBytes: 456,
                        codec: "lpcm",
                        width: 0,
                        height: 0,
                        durationFrames: 250,
                        durationSeconds: 10,
                        startTimecode: "00:00:00:00",
                        hasVideo: false,
                        hasAudio: true,
                        audioChannels: 2,
                        audioSampleRate: 48000
                    ),
                    proxy: nil,
                    hashes: HandoffHashes(algorithm: "xxh64", value: "fedcba9876543210"),
                    metadata: HandoffMetadata(scene: "", shot: "", take: "", cameraAngle: "", notes: "")
                )
            ],
            reports: HandoffReportRefs(mhl: nil, pdf: nil, csv: nil, json: nil, txt: nil, sidecar: nil),
            handoff: HandoffSummary(target: "finalCut", generatedFiles: [], notes: "")
        )

        let xml = FCPXMLBuilder.renderXML(manifest: manifest, offload: settings)
        guard let data = xml.data(using: .utf8) else {
            throw TestFailure("FCPXML was not UTF-8 encodable")
        }
        _ = try XMLDocument(data: data, options: [])
        try expect(xml.contains("kind=\"proxy-media\""), "FCPXML should declare proxy media-rep")
        try expect(xml.contains("clip%201.mov"), "FCPXML should percent-encode spaces in file URLs")
        try expect(xml.contains("%E9%A1%B9%E7%9B%AE"), "FCPXML should percent-encode Chinese file URLs")
        try expect(xml.contains("FFVideoFormat3840x2160p25"), "FCPXML should emit source-resolution format resources")
        try expect(xml.contains("hasVideo=\"0\" hasAudio=\"1\""), "FCPXML should preserve audio-only media")
        try expect(!xml.contains(".333333"), "FCPXML should avoid floating-point seconds")
        let tcStart = FCPXMLBuilder.parseTimecodeAsRationalSeconds(
            timecode: "01:00:00:00",
            fpsNumerator: 24000,
            fpsDenominator: 1001
        )
        try expect(tcStart.xml == "3600s", "23.976 whole-hour timecode should remain exact, got \(tcStart.xml)")
    }

    private static func testHandoffPackageBuilder() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitHandoffTests-\(UUID().uuidString)", isDirectory: true)
        let output = root.appendingPathComponent("PROJECT_20260506_A001", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: output.appendingPathComponent("AUDIO", isDirectory: true), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: output.appendingPathComponent("AUDIO/sync.wav"))
        let lutURL = root.appendingPathComponent("show lut.cube")
        try Data("LUT_3D_SIZE 2\n".utf8).write(to: lutURL)

        var profile = TranscodeProfile.default
        profile.lutPath = lutURL.path
        var settings = OffloadSettings(
            projectName: "项目 中文",
            cardNumber: "A001",
            operatorName: "Unit Test",
            camera: "Sony FX6",
            location: "Stage",
            notes: "Handoff package test",
            sourceURL: root.appendingPathComponent("CARD", isDirectory: true),
            targetRoots: [root],
            createdAt: Date(timeIntervalSince1970: 1_777_777_777),
            generateProxies: false,
            transcodeProfile: profile
        )
        settings.handoff.target = .both
        settings.handoff.importLUT = true

        let report = TargetReport(
            rootURL: root,
            outputURL: output,
            packageMode: .safeCopy,
            state: .completed,
            copiedBytes: 5,
            verifiedBytes: 5,
            error: nil,
            mhlURL: nil,
            pdfURL: nil,
            csvURL: nil,
            jsonURL: nil,
            txtURL: nil,
            sidecarURL: nil,
            proxyURL: nil,
            proxyFilesCreated: 0,
            proxyErrors: []
        )
        let record = FileCopyRecord(
            relativePath: "AUDIO/sync.wav",
            size: 5,
            modifiedAt: Date(timeIntervalSince1970: 1_777_777_778),
            sourceHash: "0123456789abcdef",
            targetResults: [
                FileTargetResult(
                    rootPath: root.path,
                    outputPath: output.appendingPathComponent("AUDIO/sync.wav").path,
                    copied: true,
                    verified: true,
                    hash: "0123456789abcdef",
                    error: nil
                )
            ]
        )

        let handoff = try await HandoffPackageBuilder.build(offload: settings, target: report, files: [record])
        guard let manifestURL = handoff.manifestURL else {
            throw TestFailure("Handoff manifest was not generated")
        }
        let manifestData = try Data(contentsOf: manifestURL)
        guard let manifestJSON = try JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let media = manifestJSON["media"] as? [[String: Any]],
              let project = manifestJSON["project"] as? [String: Any],
              let color = project["color"] as? [String: Any] else {
            throw TestFailure("Handoff manifest JSON shape was invalid")
        }
        try expect(media.count == 1, "Audio-only files should be included in handoff media")
        try expect((color["lutPath"] as? String)?.contains("/05_HANDOFF/LUT/show lut.cube") == true, "Manifest LUT should point at staged 05_HANDOFF/LUT copy")
        try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("05_HANDOFF/LUT/show lut.cube").path), "LUT should be copied into 05_HANDOFF/LUT")
        let resolveFiles = try FileManager.default.contentsOfDirectory(
            at: output.appendingPathComponent("05_HANDOFF/Resolve", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        try expect(resolveFiles.contains(where: { $0.pathExtension == "py" && !$0.lastPathComponent.contains("resolve_import") }), "Resolve script should be generated with a normalized per-job name")
        let fcpFiles = try FileManager.default.contentsOfDirectory(
            at: output.appendingPathComponent("05_HANDOFF/FinalCutPro", isDirectory: true),
            includingPropertiesForKeys: nil
        )
        try expect(fcpFiles.contains(where: { $0.pathExtension == "fcpxmld" && FileManager.default.fileExists(atPath: $0.appendingPathComponent("Info.fcpxml").path) }), "FCPXMLD should be generated with a normalized per-job name")
    }

    private static func testOffloadEngine() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let nested = source.appendingPathComponent("DCIM/A001", isDirectory: true)
        let targetA = root.appendingPathComponent("BackupA", isDirectory: true)
        let targetB = root.appendingPathComponent("BackupB", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetB, withIntermediateDirectories: true)
        try Data("camera-data".utf8).write(to: nested.appendingPathComponent("clip.mov"))
        try Data().write(to: nested.appendingPathComponent("empty.bin"))
        try Data("junk".utf8).write(to: source.appendingPathComponent(".DS_Store"))

        let createdAt = Date(timeIntervalSince1970: 1_777_777_777)
        let settings = OffloadSettings(
            projectName: "TEST",
            cardNumber: "A001",
            operatorName: "Unit Test",
            camera: "Camera A",
            location: "Stage",
            notes: "Smoke test",
            sourceURL: source,
            targetRoots: [targetA, targetB],
            createdAt: createdAt,
            generateProxies: false
        )

        var snapshots = 0
        let report = try await OffloadEngine().run(settings: settings) { _ in
            snapshots += 1
        }

        try expect(snapshots > 0, "Expected progress snapshots")
        try expect(report.totalFiles == 2, "Expected two source files, got \(report.totalFiles)")
        try expect(report.successfulTargets.count == 2, "Expected two successful targets")

        for target in [targetA, targetB] {
            let output = target.appendingPathComponent(settings.outputFolderName, isDirectory: true)
            try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("MEDIA/A001/DCIM/A001/clip.mov").path), "Missing copied clip")
            try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("MEDIA/A001/ascmhl").path), "Missing ascmhl folder at media root")
            let pdfs = try FileManager.default.contentsOfDirectory(
                at: output.appendingPathComponent("REPORTS", isDirectory: true),
                includingPropertiesForKeys: nil
            ).filter { $0.pathExtension.lowercased() == "pdf" }
            try expect(!pdfs.isEmpty, "Missing PDF report")
            let checksumFiles = try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("CHECKSUMS", isDirectory: true), includingPropertiesForKeys: nil)
            try expect(checksumFiles.contains(where: { $0.pathExtension.lowercased() == "csv" && $0.lastPathComponent.uppercased().contains("CHECKSUMS") }), "Missing normalized checksum sidecar")
            try expect(try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("REPORTS", isDirectory: true), includingPropertiesForKeys: nil).contains(where: { $0.pathExtension.lowercased() == "csv" }), "Missing CSV report")
            try expect(try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("REPORTS", isDirectory: true), includingPropertiesForKeys: nil).contains(where: { $0.pathExtension.lowercased() == "json" }), "Missing JSON report")
            try expect(try FileManager.default.contentsOfDirectory(at: output.appendingPathComponent("REPORTS", isDirectory: true), includingPropertiesForKeys: nil).contains(where: { $0.pathExtension.lowercased() == "txt" }), "Missing TXT brief")
            try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(".321doit/session.json").path), "Missing resume manifest")
            try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(".321doit/task.json").path), "Missing stable task manifest")
            try expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(".321doit/layout-version").path), "Missing layout version")
            let taskData = try Data(contentsOf: output.appendingPathComponent(".321doit/task.json"))
            let taskJSON = try JSONSerialization.jsonObject(with: taskData) as? [String: Any]
            try expect(taskJSON?["schema"] as? String == "com.321doit.offload-task", "Unexpected task manifest schema")
            try expect(taskJSON?["schemaVersion"] as? Int == 2, "Unexpected task manifest version")
            try expect(taskJSON?["taskID"] as? String == settings.taskID.uuidString, "Task manifest must preserve task identity")
            try expect(!FileManager.default.fileExists(atPath: output.appendingPathComponent(".DS_Store").path), "Junk file should not copy")
        }

        try expect(report.settings.checksumAlgorithm == .xxhash64, "Unexpected default checksum algorithm")
        try expect(report.settings.copyBufferKB == 1024, "Unexpected default copy buffer")
        try expect(report.settings.sourceCardProfile.maker == "Generic", "Expected generic DCIM camera card detection")

        let resumedReport = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(resumedReport.successfulTargets.count == 2, "Expected resumed offload to succeed")
        try expect(resumedReport.files.allSatisfy { file in
            file.targetResults.allSatisfy(\.verified)
        }, "Expected resumed files to remain verified")

        var verifyOnlySettings = settings
        verifyOnlySettings.verifyOnly = true
        let verifyOnlyReport = try await OffloadEngine().run(settings: verifyOnlySettings) { _ in }
        try expect(verifyOnlyReport.successfulTargets.count == 2, "Expected verify-only run to succeed")
        try expect(verifyOnlyReport.files.allSatisfy { file in
            file.targetResults.allSatisfy(\.verified)
        }, "Expected verify-only files to verify cleanly")

        let proxyPath = ProxyTranscoder.proxyRelativePath(for: "DCIM/A001/clip.mov")
        try expect(proxyPath == "DCIM/A001/clip_proxy_prores.mov", "Unexpected proxy path: \(proxyPath)")
    }

    /// Runs an offload and confirms the on-disk ASC MHL v2.0 artifacts
    /// look right structurally — file present, well-formed XML, chain has
    /// matching c4 hash for the generation file. Does NOT shell out to the
    /// official tool (that's the next test).
    private static func testAscMHLv2Layout() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitAscMHLLayout-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("clip-1".utf8).write(to: source.appendingPathComponent("A001_C001.mov"))
        try Data("clip-2".utf8).write(to: source.appendingPathComponent("A001_C002.mov"))

        let createdAt = Date(timeIntervalSince1970: 1_777_777_777)
        let settings = OffloadSettings(
            projectName: "MHL_VAL",
            cardNumber: "A001",
            operatorName: "Cross Validator",
            camera: "",
            location: "",
            notes: "",
            sourceURL: source,
            targetRoots: [target],
            createdAt: createdAt,
            generateProxies: false
        )
        _ = try await OffloadEngine().run(settings: settings) { _ in }

        let outputURL = target.appendingPathComponent(settings.outputFolderName, isDirectory: true)
        let ascmhlDir = outputURL.appendingPathComponent("MEDIA/A001/ascmhl", isDirectory: true)
        try expect(
            FileManager.default.fileExists(atPath: ascmhlDir.path),
            "ASC MHL v2 directory missing at \(ascmhlDir.path)"
        )

        let entries = try FileManager.default.contentsOfDirectory(at: ascmhlDir, includingPropertiesForKeys: nil)
        let mhls = entries.filter { $0.pathExtension.lowercased() == "mhl" }
        try expect(mhls.count == 1, "Expected exactly one v2 MHL, got \(mhls.count)")
        let mhlURL = mhls[0]

        let mhlName = mhlURL.lastPathComponent
        try expect(
            mhlName.hasPrefix("0001_") && mhlName.hasSuffix(".mhl"),
            "MHL filename must follow NNNN_..._.mhl pattern, got \(mhlName)"
        )

        let xml = try String(contentsOf: mhlURL, encoding: .utf8)
        try expect(
            xml.contains("<hashlist version=\"2.0\" xmlns=\"urn:ASC:MHL:v2.0\">"),
            "v2 MHL must declare correct namespace; got prefix \(xml.prefix(200))"
        )
        try expect(xml.contains("<xxh64 action=\"original\""), "v2 MHL must use <xxh64> hash element")
        try expect(xml.contains("A001_C001.mov"), "v2 MHL must list A001_C001.mov")
        try expect(xml.contains("A001_C002.mov"), "v2 MHL must list A001_C002.mov")

        let chainURL = ascmhlDir.appendingPathComponent("ascmhl_chain.xml")
        let chain = try String(contentsOf: chainURL, encoding: .utf8)
        try expect(
            chain.contains("urn:ASC:MHL:DIRECTORY:v2.0"),
            "Chain XML must declare directory namespace"
        )
        let expectedC4 = try C4Hash.hashFile(at: mhlURL)
        try expect(
            chain.contains("<c4>\(expectedC4)</c4>"),
            "Chain XML must reference current c4 hash; expected \(expectedC4) in \(chain)"
        )
    }

    /// If the official `ascmhl` Python tool is on PATH, drive it against
    /// 321Doit's output and assert it parses + verifies cleanly. Otherwise
    /// skip with a clear message — we don't want this to be a hard
    /// dependency for `./run_tests.sh` on a fresh machine.
    private static func testAscMHLv2OfficialCrossValidation() async throws {
        guard let toolPath = locateAscMHLTool() else {
            print("    · skipped testAscMHLv2OfficialCrossValidation (run `./Tools/setup_ascmhl.sh` to install the pinned reference tool)")
            return
        }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitAscMHLOfficial-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("clip-1".utf8).write(to: source.appendingPathComponent("A001_C001.mov"))
        try Data("clip-2".utf8).write(to: source.appendingPathComponent("A001_C002.mov"))

        let createdAt = Date(timeIntervalSince1970: 1_777_777_777)
        let settings = OffloadSettings(
            projectName: "ASC_OFFICIAL",
            cardNumber: "A001",
            operatorName: "Cross Validator",
            camera: "",
            location: "",
            notes: "",
            sourceURL: source,
            targetRoots: [target],
            createdAt: createdAt,
            generateProxies: false
        )
        _ = try await OffloadEngine().run(settings: settings) { _ in }
        let outputURL = target.appendingPathComponent(settings.outputFolderName, isDirectory: true)
        let mediaRoot = outputURL.appendingPathComponent("MEDIA/A001", isDirectory: true)

        // `ascmhl info` should parse the manifest cleanly and exit 0.
        let infoOutput = try runProcess(toolPath, args: ["info", "-v", mediaRoot.path])
        try expect(
            infoOutput.exitCode == 0,
            "ascmhl info exited with \(infoOutput.exitCode); stdout=\(infoOutput.stdout); stderr=\(infoOutput.stderr)"
        )
        try expect(
            infoOutput.stdout.contains("Generation 1"),
            "ascmhl info should report generation 1; got: \(infoOutput.stdout)"
        )

        // `ascmhl diff` re-walks the tree and verifies hashes against the
        // manifest. Exit 0 means files on disk match the recorded hashes.
        let diffOutput = try runProcess(toolPath, args: ["diff", "-v", mediaRoot.path])
        try expect(
            diffOutput.exitCode == 0,
            "ascmhl diff exited with \(diffOutput.exitCode); stdout=\(diffOutput.stdout); stderr=\(diffOutput.stderr)"
        )
    }

    private static func locateAscMHLTool() -> String? {
        // Common install locations: PATH (which), per-user pip --user bin,
        // and homebrew. We probe each because pip's --user bin is not on
        // PATH by default on macOS.
        let candidates: [String] = [
            "\(FileManager.default.currentDirectoryPath)/build/ascmhl-venv/bin/ascmhl",
            "/usr/local/bin/ascmhl",
            "/opt/homebrew/bin/ascmhl",
            "\(NSHomeDirectory())/Library/Python/3.14/bin/ascmhl",
            "\(NSHomeDirectory())/Library/Python/3.13/bin/ascmhl",
            "\(NSHomeDirectory())/Library/Python/3.12/bin/ascmhl",
            "\(NSHomeDirectory())/Library/Python/3.11/bin/ascmhl",
            "\(NSHomeDirectory())/Library/Python/3.10/bin/ascmhl",
            "\(NSHomeDirectory())/.local/bin/ascmhl"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        // Last resort: ask the shell.
        let probe = (try? runProcess("/usr/bin/env", args: ["which", "ascmhl"])) ?? ProcessOutput(stdout: "", stderr: "", exitCode: 1)
        if probe.exitCode == 0 {
            let trimmed = probe.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, FileManager.default.isExecutableFile(atPath: trimmed) {
                return trimmed
            }
        }
        return nil
    }

    private struct ProcessOutput {
        var stdout: String
        var stderr: String
        var exitCode: Int32
    }

    private static func runProcess(_ launchPath: String, args: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessOutput(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    private static func assertNoTempFiles(in url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let file as URL in enumerator {
                try expect(!file.lastPathComponent.hasPrefix(".321doit-copying-"), "Found orphaned temp file: \(file.path)")
            }
        }
    }

    private static func testTemporaryCleanup() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitTempCleanup-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        
        let largeFileURL = source.appendingPathComponent("large.bin")
        let largeData = Data(repeating: 0x01, count: 1024 * 1024 * 50) // 50MB
        try largeData.write(to: largeFileURL)

        var settings = OffloadSettings(
            projectName: "TEST",
            cardNumber: "A001",
            operatorName: "Unit",
            camera: "Cam",
            location: "Stage",
            notes: "Temp Cleanup Test",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false,
            enableSpeedLimit: true,
            speedLimitMBps: 10 // slow down so we can cancel it
        )

        // 1. Test Cancellation
        let engine = OffloadEngine()
        let copyTask = Task {
            try await engine.run(settings: settings) { _ in }
        }
        
        try await Task.sleep(nanoseconds: 200_000_000)
        copyTask.cancel()
        
        var threwCancellation = false
        do {
            _ = try await copyTask.value
        } catch is CancellationError {
            threwCancellation = true
        } catch {
            threwCancellation = error.localizedDescription.contains("cancelled") || error is CancellationError
        }
        try expect(threwCancellation, "Expected task to be cancelled and throw")
        
        let outputFolder = target.appendingPathComponent(settings.outputFolderName, isDirectory: true)
        try assertNoTempFiles(in: target) // recursive scan

        // 2. Test successful copy doesn't delete final file
        settings.enableSpeedLimit = false
        let report = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(report.successfulTargets.count == 1, "Expected successful target")
        let finalFile = outputFolder.appendingPathComponent("MEDIA/A001/large.bin")
        try expect(FileManager.default.fileExists(atPath: finalFile.path), "Final file must exist after success, defer block shouldn't delete it")
        try assertNoTempFiles(in: target)

        // 3. Test generic I/O thrown error mid-copy
        let errorSource = source.appendingPathComponent("error.bin")
        try Data(repeating: 0x02, count: 1024 * 1024 * 5).write(to: errorSource) // 5MB
        
        OffloadEngine.testInjectErrorOnPath = "error.bin"
        defer { OffloadEngine.testInjectErrorOnPath = nil }
        
        var threwInjectedError = false
        do {
            let report = try await OffloadEngine().run(settings: settings) { _ in }
            print("Report state: \(report.successfulTargets.count) successful, files: \(report.files.count)")
            for f in report.files {
                print("Processed file: \(f.relativePath)")
            }
        } catch {
            threwInjectedError = true
            print("Caught injected error: \(error)")
        }
        try expect(threwInjectedError, "Expected task to fail due to injected error")
        try assertNoTempFiles(in: target)
    }

    private static func testManifestThrottle() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitThrottle-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        
        let numFiles = 50
        for i in 0..<numFiles {
            try Data("small file \(i)".utf8).write(to: source.appendingPathComponent("file_\(i).txt"))
        }

        let settings = OffloadSettings(
            projectName: "TEST",
            cardNumber: "A001",
            operatorName: "Unit",
            camera: "Cam",
            location: "Stage",
            notes: "Throttle Test",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false
        )

        var attemptedWriteCount = 0
        var actualWriteCount = 0
        var forceWriteCount = 0
        OffloadEngine.attemptedManifestWriteSpy = { _ in attemptedWriteCount += 1 }
        OffloadEngine.actualManifestWriteSpy = { force in
            actualWriteCount += 1
            if force { forceWriteCount += 1 }
        }
        defer {
            OffloadEngine.attemptedManifestWriteSpy = nil
            OffloadEngine.actualManifestWriteSpy = nil
        }

        let report = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(report.successfulTargets.count == 1, "Expected success")

        // Assert throttling
        try expect(forceWriteCount >= numFiles, "Force write should be called at least once per file (\(forceWriteCount))")
        try expect(actualWriteCount < attemptedWriteCount, "Actual writes should be significantly less than attempted. Attempted: \(attemptedWriteCount), Actual: \(actualWriteCount)")
        try expect(attemptedWriteCount >= (numFiles * 3), "Should have attempted many writes (pending -> copying -> verifying -> verified)")

        // Deep verification of JSON
        let sessionURL = target.appendingPathComponent(settings.outputFolderName).appendingPathComponent(".321doit/session.json")
        let sessionData = try Data(contentsOf: sessionURL)
        guard let session = try JSONSerialization.jsonObject(with: sessionData) as? [String: Any],
              let files = session["files"] as? [String: Any] else {
            throw TestFailure("session.json format invalid")
        }

        try expect(files.count == numFiles, "session.json should have \(numFiles) files")
        for i in 0..<numFiles {
            let key = "file_\(i).txt"
            guard let fileObj = files[key] as? [String: Any],
                  let status = fileObj["status"] as? String else {
                throw TestFailure("Missing or invalid status for \(key)")
            }
            try expect(status == "verified", "\(key) status must be verified, got \(status)")
        }
        }
    private static func testStrictResumeDetectsSameSizeSameMTimeTamper() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitStrictResume-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let fileURL = source.appendingPathComponent("file.txt")
        let originalContent = "v1-content"
        try Data(originalContent.utf8).write(to: fileURL)

        var settings = OffloadSettings(
            projectName: "TEST",
            cardNumber: "A001",
            operatorName: "Unit Test",
            camera: "Camera A",
            location: "Stage",
            notes: "Strict Resume Test",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false
        )

        // Initial copy
        _ = try await OffloadEngine().run(settings: settings) { _ in }

        let outputFolder = target.appendingPathComponent(settings.outputFolderName, isDirectory: true)
        let targetFileURL = outputFolder.appendingPathComponent("MEDIA/A001/file.txt")
        let targetContentV1 = try String(contentsOf: targetFileURL)
        try expect(targetContentV1 == originalContent, "Initial copy failed")

        // Corrupt target file but preserve size and mtime
        let attributes = try FileManager.default.attributesOfItem(atPath: targetFileURL.path)
        let mtime = attributes[.modificationDate] as! Date

        let corruptedContent = "v2-corrupt"
        try expect(originalContent.count == corruptedContent.count, "Test error: string lengths must match")
        try Data(corruptedContent.utf8).write(to: targetFileURL)
        try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: targetFileURL.path)

        // Non-strict resume
        settings.strictResume = false
        _ = try await OffloadEngine().run(settings: settings) { _ in }
        let targetContentV2 = try String(contentsOf: targetFileURL)
        try expect(targetContentV2 == corruptedContent, "Non-strict resume should trust mtime/size and skip, leaving file corrupted")

        // Strict resume
        settings.strictResume = true
        let strictReport = try await OffloadEngine().run(settings: settings) { _ in }
        let targetContentV3 = try String(contentsOf: targetFileURL)
        try expect(targetContentV3 == originalContent, "Strict resume must re-hash and overwrite the corrupted file")
        try expect(strictReport.successfulTargets.count == 1, "Strict resume should succeed after re-copying")
    }
    private static func testPDFPaginationSamples() async throws {
        let sampleRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/ReportHardeningSamples", isDirectory: true)
        try? FileManager.default.removeItem(at: sampleRoot)
        try FileManager.default.createDirectory(at: sampleRoot, withIntermediateDirectories: true)

        let ten = try await makeReportSample(fileCount: 10, sampleRoot: sampleRoot)
        try expect(ten.pageCount >= 1, "10-file PDF should have at least one page")

        let hundred = try await makeReportSample(fileCount: 100, sampleRoot: sampleRoot)
        try expect(hundred.pageCount > 1, "100-file PDF should paginate, got \(hundred.pageCount)")

        let thousand = try await makeReportSample(fileCount: 1_000, sampleRoot: sampleRoot)
        try expect(thousand.pageCount > hundred.pageCount, "1000-file PDF should have more pages than 100-file PDF")
        try expect(thousand.sessionJSON.contains("\"status\" : \"verified\""), "session.json should include verified status")
        try expect(thousand.sessionJSON.contains("\"verified\" : true"), "session.json should retain legacy verified bool")

        let summary = """
        10 files: \(ten.pageCount) PDF page(s)
        100 files: \(hundred.pageCount) PDF page(s)
        1000 files: \(thousand.pageCount) PDF page(s)
        1000 sample PDF: \(thousand.pdfURL.path)
        1000 sample session.json: \(thousand.sessionURL.path)
        """
        try summary.write(to: sampleRoot.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
    }

    private static func makeReportSample(fileCount: Int, sampleRoot: URL) async throws -> (pageCount: Int, pdfURL: URL, sessionURL: URL, sessionJSON: String) {
        let root = sampleRoot.appendingPathComponent("\(fileCount)-files", isDirectory: true)
        let source = root.appendingPathComponent("CARD 中文 空格 😀", isDirectory: true)
        let target = root.appendingPathComponent("Target Disk", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        for index in 0..<fileCount {
            let group = source.appendingPathComponent("素材 组 \(index % 10)", isDirectory: true)
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
            let longStem = "clip \(String(format: "%04d", index)) 中文 空格 😀 very very long path segment for pagination"
            let url = group.appendingPathComponent("\(longStem).mov")
            try Data("sample-\(index)".utf8).write(to: url)
        }

        let settings = OffloadSettings(
            projectName: "PDF分页测试",
            cardNumber: "A\(String(format: "%03d", fileCount))",
            operatorName: "Unit Test",
            camera: "CAM 中文",
            location: "Stage 😀",
            notes: "中文路径、空格路径、emoji 路径分页测试",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(timeIntervalSince1970: 1_777_000_000 + TimeInterval(fileCount)),
            generateProxies: false
        )

        let report = try await OffloadEngine().run(settings: settings) { _ in }
        guard let pdfURL = report.successfulTargets.first?.pdfURL else {
            throw TestFailure("Missing PDF for \(fileCount)-file sample")
        }
        guard let pdf = CGPDFDocument(pdfURL as CFURL) else {
            throw TestFailure("Could not read generated PDF: \(pdfURL.path)")
        }
        let sessionURL = report.successfulTargets[0].outputURL.appendingPathComponent(".321doit/session.json")
        let sessionJSON = try String(contentsOf: sessionURL, encoding: .utf8)
        return (pdf.numberOfPages, pdfURL, sessionURL, sessionJSON)
    }

    private static func testMultiTargetPartialFailure() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitPartialFail-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let targetA = root.appendingPathComponent("GoodDisk", isDirectory: true)
        let targetB = root.appendingPathComponent("BadDisk", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetB, withIntermediateDirectories: true)
        try Data("test-file-content-a".utf8).write(to: source.appendingPathComponent("clip_a.mov"))
        try Data("test-file-content-b".utf8).write(to: source.appendingPathComponent("clip_b.mov"))

        let settings = OffloadSettings(
            projectName: "PARTIAL",
            cardNumber: "A001",
            operatorName: "Unit",
            camera: "Cam",
            location: "",
            notes: "",
            sourceURL: source,
            targetRoots: [targetA, targetB],
            createdAt: Date(),
            generateProxies: false
        )

        let report = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(report.successfulTargets.count == 2, "Both targets should succeed initially")

        // Make targetB read-only so the second run fails on it
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555],
            ofItemAtPath: targetB.appendingPathComponent(settings.outputFolderName).path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: targetB.appendingPathComponent(settings.outputFolderName).path
            )
        }

        // Remove session.json from targetB so engine tries to re-copy
        let sessionB = targetB.appendingPathComponent(settings.outputFolderName)
            .appendingPathComponent(".321doit/session.json")
        let resumeB = targetB.appendingPathComponent(settings.outputFolderName)
            .appendingPathComponent(".321doit/resume-manifest.json")
        try? FileManager.default.removeItem(at: sessionB)
        try? FileManager.default.removeItem(at: resumeB)

        // Remove the originals subfolder so re-copy is needed
        let originalsB = targetB.appendingPathComponent(settings.outputFolderName)
            .appendingPathComponent("MEDIA")
        try? FileManager.default.removeItem(at: originalsB)

        // Create a new source file to force actual copy work
        try Data("new-content".utf8).write(to: source.appendingPathComponent("clip_c.mov"))
        var freshSettings = settings
        freshSettings.cardNumber = "A002"

        let report2 = try await OffloadEngine().run(settings: freshSettings) { _ in }
        try expect(report2.successfulTargets.count >= 1, "At least targetA should succeed even if targetB fails")

        let targetAClip = targetA.appendingPathComponent(freshSettings.outputFolderName)
            .appendingPathComponent("MEDIA/A002/clip_c.mov")
        try expect(FileManager.default.fileExists(atPath: targetAClip.path), "TargetA should have the new file despite targetB failing")
    }

    private static func testReportWriteFailureIsNotSuccess() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitReportFailure-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer {
            ReportWriter.testInjectWriteFailure = false
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("report-failure-regression".utf8).write(to: source.appendingPathComponent("clip.mov"))

        let settings = OffloadSettings(
            projectName: "REPORT_FAIL",
            cardNumber: "A001",
            operatorName: "Unit",
            camera: "Cam",
            location: "",
            notes: "",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false
        )

        ReportWriter.testInjectWriteFailure = true
        do {
            _ = try await OffloadEngine().run(settings: settings) { _ in }
            throw TestFailure("A mandatory report failure must fail the task")
        } catch OffloadError.reportGenerationFailed(let failures) {
            try expect(failures.count == 1, "Expected one surfaced report failure, got \(failures.count)")
        }
    }

    private static func testAuditLogGeneration() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitAudit-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("audit-test-clip".utf8).write(to: source.appendingPathComponent("A001_C001.mov"))
        try Data("audit-test-clip-2".utf8).write(to: source.appendingPathComponent("A001_C002.mov"))

        let settings = OffloadSettings(
            projectName: "AUDIT_TEST",
            cardNumber: "A001",
            operatorName: "Auditor",
            camera: "Test Cam",
            location: "Stage",
            notes: "Audit log test",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false
        )
        _ = try await OffloadEngine().run(settings: settings) { _ in }

        let auditURL = target.appendingPathComponent(settings.outputFolderName)
            .appendingPathComponent(".321doit/audit.json")
        try expect(FileManager.default.fileExists(atPath: auditURL.path), "audit.json must exist after successful offload")

        let data = try Data(contentsOf: auditURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TestFailure("audit.json is not valid JSON")
        }

        try expect((json["schema"] as? String) == "321doit-audit-v1", "Audit schema must be 321doit-audit-v1")

        guard let env = json["environment"] as? [String: Any] else {
            throw TestFailure("audit.json missing environment")
        }
        try expect(env["app"] as? String == "321Doit", "Audit must identify app name")
        try expect(env["version"] != nil, "Audit must include app version")
        try expect(env["hostname"] != nil, "Audit must include hostname for traceability")

        guard let task = json["task"] as? [String: Any] else {
            throw TestFailure("audit.json missing task")
        }
        try expect(task["project"] as? String == "AUDIT_TEST", "Audit must record project name")
        try expect(task["operator"] as? String == "Auditor", "Audit must record operator")

        guard let timing = json["timing"] as? [String: Any] else {
            throw TestFailure("audit.json missing timing")
        }
        try expect(timing["startedAt"] != nil, "Audit must record start time")
        try expect(timing["endedAt"] != nil, "Audit must record end time")
        try expect((timing["durationSeconds"] as? Int) != nil, "Audit must record duration")

        guard let summary = json["summary"] as? [String: Any] else {
            throw TestFailure("audit.json missing summary")
        }
        try expect(summary["totalFiles"] as? Int == 2, "Audit must report 2 files")
        try expect(summary["verifiedFiles"] as? Int == 2, "Audit must report 2 verified files")
        try expect(summary["failedFiles"] as? Int == 0, "Audit must report 0 failed files")

        guard let files = json["files"] as? [[String: Any]] else {
            throw TestFailure("audit.json missing files array")
        }
        try expect(files.count == 2, "Audit must list 2 file entries")
        for entry in files {
            try expect(entry["relativePath"] != nil, "Each audit entry must have relativePath")
            try expect(entry["sourceHash"] != nil, "Each audit entry must have sourceHash")
            try expect(entry["targetHash"] != nil, "Each audit entry must have targetHash")
            try expect(entry["verified"] as? Bool == true, "Each audit entry must be verified")
        }
    }

    private static func testCJKAndEmojiPaths() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321Doit中文路径-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("素材卡 😀", isDirectory: true)
        let nested = source.appendingPathComponent("DCIM/日拍 第一组", isDirectory: true)
        let target = root.appendingPathComponent("备份盘 目标", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("中文内容测试".utf8).write(to: nested.appendingPathComponent("镜头_001_中文名.mov"))
        try Data("emoji path test 🎬".utf8).write(to: nested.appendingPathComponent("clip 空格 & special.mov"))
        try Data("unicode paths".utf8).write(to: source.appendingPathComponent("émojis—déjà_vu.txt"))

        let settings = OffloadSettings(
            projectName: "中文项目 😀",
            cardNumber: "卡001",
            operatorName: "操作员",
            camera: "摄影机A",
            location: "片场",
            notes: "Unicode stress test",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false
        )

        let report = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(report.successfulTargets.count == 1, "CJK/emoji path offload must succeed")
        try expect(report.totalFiles == 3, "Must copy all 3 files with unicode paths")
        try expect(report.files.allSatisfy { $0.targetResults.allSatisfy(\.verified) }, "All files must verify with unicode paths")

        let auditURL = target.appendingPathComponent(settings.outputFolderName)
            .appendingPathComponent(".321doit/audit.json")
        try expect(FileManager.default.fileExists(atPath: auditURL.path), "audit.json must exist for CJK path offload")

        let data = try Data(contentsOf: auditURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]]
        try expect(files?.count == 3, "Audit must list all 3 CJK/emoji files")
    }

    private static func testCancellationDuringCopy() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321DoitCancel-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("CARD", isDirectory: true)
        let target = root.appendingPathComponent("Backup", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 20 * 1024 * 1024).write(to: source.appendingPathComponent("big.bin"))

        var settings = OffloadSettings(
            projectName: "CANCEL",
            cardNumber: "A001",
            operatorName: "Unit",
            camera: "",
            location: "",
            notes: "",
            sourceURL: source,
            targetRoots: [target],
            createdAt: Date(),
            generateProxies: false,
            enableSpeedLimit: true,
            speedLimitMBps: 5
        )

        let task = Task {
            try await OffloadEngine().run(settings: settings) { _ in }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        var threw = false
        do {
            _ = try await task.value
        } catch is CancellationError {
            threw = true
        } catch {
            threw = error.localizedDescription.contains("cancelled") || error is CancellationError
        }
        try expect(threw, "Cancellation during copy must propagate CancellationError")
        try assertNoTempFiles(in: target)

        // Verify the offload can be resumed after cancellation
        settings.enableSpeedLimit = false
        let resumed = try await OffloadEngine().run(settings: settings) { _ in }
        try expect(resumed.successfulTargets.count == 1, "Resume after cancellation must succeed")
        try expect(resumed.files.allSatisfy { $0.targetResults.allSatisfy(\.verified) }, "Resumed files must all verify")
    }

    // MARK: - Media Converter (Phase 1)

    private static func makeStream(
        index: Int, type: MediaStreamKind, codec: String, codecTagString: String = "",
        width: Int = 0, height: Int = 0, pixFmt: String = "",
        sampleRate: String = "", channels: String = "", channelLayout: String = "",
        sampleFmt: String = "", bitsPerRawSample: String = "", bitsPerSample: String = "",
        colorSpace: String = "", colorPrimaries: String = "",
        tags: [String: String] = [:]
    ) -> ProbedStream {
        ProbedStream(
            index: index, kind: type, codecName: codec, codecLongName: "", profile: "",
            codecTagString: codecTagString, width: width, height: height, pixFmt: pixFmt,
            sampleAspectRatio: "", displayAspectRatio: "", rFrameRate: "", avgFrameRate: "",
            bitsPerRawSample: bitsPerRawSample, sampleRate: sampleRate, channels: channels,
            channelLayout: channelLayout, sampleFmt: sampleFmt, bitsPerSample: bitsPerSample,
            timeBase: "", startTime: "", duration: "", nbFrames: "", bitRate: "",
            colorRange: "", colorSpace: colorSpace, colorTransfer: "", colorPrimaries: colorPrimaries,
            rotation: "", tags: tags, disposition: [:], sideData: []
        )
    }

    private static func makeMedia(streams: [ProbedStream], formatName: String = "mov,mp4,m4a,3gp,3g2,mj2") -> ProbedMedia {
        ProbedMedia(
            url: URL(fileURLWithPath: "/tmp/sample.\(formatName.split(separator: ",").first ?? "mov")"),
            format: ProbedFormat(
                formatName: formatName, formatLongName: "", filename: "", nbStreams: streams.count,
                duration: "1.0", startTime: "0.0", size: "1000", bitRate: "1000", tags: [:]
            ),
            streams: streams, chapters: []
        )
    }

    private static func testMediaProbeParsing() throws {
        // A representative (truncated-but-valid) ffprobe JSON payload.
        let json = """
        {
          "streams": [
            {"index":0,"codec_name":"h264","codec_long_name":"H.264","profile":"High","codec_type":"video","width":320,"height":240,"pix_fmt":"yuv420p","bits_per_raw_sample":"8","r_frame_rate":"25/1","time_base":"1/12800","start_time":"0.000000","duration":"1.000000","nb_frames":"25","color_space":"bt709","color_primaries":"bt709","disposition":{"default":1},"tags":{"timecode":"01:00:00:00","handler_name":"VideoHandler"}},
            {"index":1,"codec_name":"pcm_s16le","codec_long_name":"PCM signed 16-bit little-endian","codec_type":"audio","sample_rate":"44100","channels":1,"channel_layout":"mono","bits_per_sample":16,"time_base":"1/44100","start_time":"0.000000","duration":"1.000000","tags":{"handler_name":"SoundHandler"}}
          ],
          "format": {"filename":"sample.mov","nb_streams":2,"format_name":"mov,mp4,m4a,3gp,3g2,mj2","format_long_name":"QuickTime","duration":"1.000000","size":"1234","bit_rate":"9872","tags":{"title":"ProbeTest"}}
        }
        """
        let data = json.data(using: .utf8)!
        let probe = MediaProbeService(language: .en)
        guard let media = probe.parse(data, url: URL(fileURLWithPath: "/tmp/sample.mov")) else {
            try expect(false, "ffprobe JSON should parse")
            return
        }
        try expect(media.streams.count == 2, "should parse 2 streams")
        try expect(media.videoStreams.count == 1, "one video stream")
        try expect(media.audioStreams.count == 1, "one audio stream")
        try expect(media.videoStreams.first?.codecName == "h264", "video codec h264")
        try expect(media.audioStreams.first?.codecName == "pcm_s16le", "audio codec pcm_s16le")
        try expect(media.format.formatName.contains("mov"), "format name should contain mov")
        try expect(media.videoStreams.first?.tagTimecode == "01:00:00:00", "timecode tag preserved")
        try expect(media.videoStreams.first?.bitDepth == "8", "video bit depth 8")
    }

    private static func testMediaCompatibilityMatrix() throws {
        let service = MediaCompatibilityService(language: .en)

        // h264 + pcm_s16le MOV -> MKV rewrap: compatible.
        let mkvSrc = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264", width: 1920, height: 1080, pixFmt: "yuv420p"),
            makeStream(index: 1, type: .audio, codec: "pcm_s16le", sampleRate: "48000", channels: "1", channelLayout: "mono")
        ])
        let mkv = service.decide(probed: mkvSrc, mode: .rewrap, target: .mkv)
        try expect(mkv.verdict == .compatible, "MOV h264+pcm -> MKV should be compatible, got \(mkv.verdict)")

        // h264 + pcm_s16le MOV -> MP4 rewrap: PCM is NOT muxable into MP4 -> incompatible.
        let mp4Src = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264"),
            makeStream(index: 1, type: .audio, codec: "pcm_s16le")
        ])
        let mp4 = service.decide(probed: mp4Src, mode: .rewrap, target: .mp4)
        try expect(mp4.verdict == .incompatible, "MOV pcm -> MP4 should be incompatible (PCM), got \(mp4.verdict)")
        try expect(mp4.risks.contains { $0.severity == .blocking }, "should have a blocking risk")

        // mov_text subtitle MOV -> MKV rewrap: mov_text not muxable into MKV -> incompatible.
        let subSrc = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264"),
            makeStream(index: 1, type: .audio, codec: "aac"),
            makeStream(index: 2, type: .subtitle, codec: "mov_text")
        ])
        let sub = service.decide(probed: subSrc, mode: .rewrap, target: .mkv)
        try expect(sub.verdict == .incompatible, "mov_text -> MKV should be incompatible, got \(sub.verdict)")

        // pcm_s16le WAV -> FLAC lossless audio: compatible.
        let wavSrc = makeMedia(streams: [
            makeStream(index: 0, type: .audio, codec: "pcm_s16le", sampleRate: "48000", channels: "2", channelLayout: "stereo", bitsPerSample: "16")
        ], formatName: "wav")
        let flac = service.decide(probed: wavSrc, mode: .losslessAudio, target: .flac)
        try expect(flac.verdict == .compatible, "WAV pcm -> FLAC lossless should be compatible, got \(flac.verdict)")

        // aac -> FLAC lossless audio: aac is not a lossless source -> incompatible.
        let aacSrc = makeMedia(streams: [
            makeStream(index: 0, type: .audio, codec: "aac", sampleRate: "48000", channels: "2")
        ])
        let aacFlac = service.decide(probed: aacSrc, mode: .losslessAudio, target: .flac)
        try expect(aacFlac.verdict == .incompatible, "aac -> FLAC lossless should be incompatible, got \(aacFlac.verdict)")

        // Audio-only container with video present (rewrap) -> blocked.
        let vidSrc = makeMedia(streams: [makeStream(index: 0, type: .video, codec: "h264")])
        let wavVid = service.decide(probed: vidSrc, mode: .rewrap, target: .wav)
        try expect(wavVid.verdict == .incompatible, "rewrap video -> WAV should be blocked, got \(wavVid.verdict)")

        // Audio-only targets still need codec validation; AAC cannot be
        // stream-copied into WAV.
        let aacWav = service.decide(probed: aacSrc, mode: .rewrap, target: .wav)
        try expect(aacWav.verdict == .incompatible, "AAC -> WAV rewrap must be blocked")

        // ffprobe normally exposes a QuickTime timecode stream through its
        // tmcd codec tag rather than codec_name=timecode.
        let tmcdSrc = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264"),
            makeStream(index: 1, type: .data, codec: "unknown", codecTagString: "tmcd")
        ])
        try expect(tmcdSrc.hasQuickTimeTimecodeTrack, "tmcd must be detected as QuickTime timecode")
        let tmcdMov = service.decide(probed: tmcdSrc, mode: .rewrap, target: .mov)
        try expect(tmcdMov.verdict == .compatible, "retained tmcd is information, not a warning")
        try expect(tmcdMov.dataRetained, "MOV tmcd track must be reported retained")

        // A common camera clip: H.264 10-bit 4:2:2 + PCM + QuickTime
        // timecode in MOV. Nothing is being lost when the target is MOV.
        let cameraMov = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264", width: 1920, height: 1080, pixFmt: "yuv422p10le", bitsPerRawSample: "10"),
            makeStream(index: 1, type: .audio, codec: "pcm_s16be", sampleRate: "48000", channels: "2", bitsPerSample: "16"),
            makeStream(index: 2, type: .data, codec: "unknown", codecTagString: "tmcd", tags: ["timecode": "01:05:13:23"])
        ])
        let cameraMovResult = service.decide(probed: cameraMov, mode: .rewrap, target: .mov)
        try expect(cameraMovResult.verdict == .compatible, "normal camera MOV with timecode should be ready without warnings")

        // Camera-specific MP4 auxiliary data is not picture or sound. It must
        // be surfaced as a warning and omitted, never make a normal clip
        // impossible to convert.
        let cameraDataSrc = makeMedia(streams: [
            makeStream(index: 0, type: .video, codec: "h264"),
            makeStream(index: 1, type: .audio, codec: "aac"),
            makeStream(index: 2, type: .data, codec: "unknown", codecTagString: "mebx")
        ])
        let cameraDataMov = service.decide(probed: cameraDataSrc, mode: .rewrap, target: .mov)
        try expect(cameraDataMov.verdict == .compatibleWithWarnings, "camera auxiliary data should warn, not block")
        try expect(!cameraDataMov.dataRetained, "unsupported camera auxiliary data must be reported as omitted")
        try expect(cameraDataMov.risks.contains { $0.code == "MC_AUXILIARY_DATA_OMITTED" && $0.severity == .warning },
                   "camera auxiliary data warning should be explicit")

        // 32-bit depth into ALAC (M4A) lossless -> incompatible (ALAC max 24).
        let deepSrc = makeMedia(streams: [
            makeStream(index: 0, type: .audio, codec: "pcm_s32le", sampleRate: "48000", channels: "2", bitsPerSample: "32")
        ])
        let deepAlac = service.decide(probed: deepSrc, mode: .losslessAudio, target: .m4a)
        try expect(deepAlac.verdict == .incompatible, "32-bit pcm -> ALAC should be incompatible (depth), got \(deepAlac.verdict)")

        // Floating-point PCM cannot be represented losslessly by FLAC/ALAC,
        // but it can remain floating-point PCM in WAV.
        let floatSrc = makeMedia(streams: [
            makeStream(index: 0, type: .audio, codec: "pcm_f32le", sampleRate: "48000", channels: "2", channelLayout: "stereo", sampleFmt: "flt", bitsPerSample: "32")
        ], formatName: "wav")
        let floatFlac = service.decide(probed: floatSrc, mode: .losslessAudio, target: .flac)
        try expect(floatFlac.verdict == .incompatible, "float PCM -> FLAC is not mathematically lossless")
        let floatWav = service.decide(probed: floatSrc, mode: .losslessAudio, target: .wav)
        try expect(floatWav.verdict != .incompatible, "float PCM -> float WAV can remain lossless")

        let h264Settings = MediaTranscodeSettings(
            videoCodec: .h264,
            audioCodec: .aac,
            quality: .balanced,
            scale: .source,
            frameRate: .source
        )
        let h264MP4 = service.decide(probed: cameraMov, mode: .transcode, target: .mp4, transcode: h264Settings)
        try expect(h264MP4.verdict != .incompatible, "camera MOV should transcode to H.264 MP4")
        try expect(h264MP4.reencodesVideo, "video transcode must report video re-encoding")

        var proResSettings = h264Settings
        proResSettings.videoCodec = .prores422
        let proResMP4 = service.decide(probed: cameraMov, mode: .transcode, target: .mp4, transcode: proResSettings)
        try expect(proResMP4.verdict == .incompatible, "ProRes must not be offered in MP4")

        var vp9Settings = h264Settings
        vp9Settings.videoCodec = .vp9
        vp9Settings.audioCodec = .opus
        let vp9WebM = service.decide(probed: cameraMov, mode: .transcode, target: .webm, transcode: vp9Settings)
        try expect(vp9WebM.verdict != .incompatible, "VP9 + Opus should be valid in WebM")
    }

    private static func testMediaReencodeFlags() throws {
        try expect(MediaConversionMode.rewrap.reencodesVideo == false, "rewrap must not re-encode video")
        try expect(MediaConversionMode.rewrap.reencodesAudio == false, "rewrap must not re-encode audio")
        try expect(MediaConversionMode.losslessAudio.reencodesVideo == false, "lossless audio must not touch video")
        try expect(MediaConversionMode.losslessAudio.reencodesAudio == true, "lossless audio re-encodes audio")
        try expect(MediaConversionMode.transcode.reencodesVideo == true, "video transcode must re-encode video")
        try expect(MediaConversionMode.transcode.reencodesAudio == true, "video transcode may re-encode audio")
    }

    private static func testMediaL10nKeys() throws {
        for container in MediaContainer.allCases {
            try expect(!container.displayName(language: .zh).isEmpty, "zh name for \(container.rawValue)")
            try expect(!container.displayName(language: .en).isEmpty, "en name for \(container.rawValue)")
        }
        for mode in MediaConversionMode.allCases {
            try expect(!mode.displayName(language: .zh).isEmpty, "zh name for \(mode.rawValue)")
            try expect(!mode.displayName(language: .en).isEmpty, "en name for \(mode.rawValue)")
        }
        for codec in MediaVideoCodec.allCases {
            try expect(!codec.displayName.isEmpty, "display name for \(codec.rawValue)")
            try expect(!codec.supportedContainers.isEmpty, "container matrix for \(codec.rawValue)")
        }
        // Error code messages exist in both languages.
        for code in [MediaConversionError.dependencyMissing, .probeFailed, .probeTimedOut, .incompatibleContainer, .verificationFailed, .reportFailed] {
            try expect(!code.message(language: .zh).isEmpty, "zh message for \(code.rawValue)")
            try expect(!code.message(language: .en).isEmpty, "en message for \(code.rawValue)")
        }
    }

    private static func testMediaProbeIntegration() async throws {
        // Integration: generate a tiny media and probe it for real. Skips
        // gracefully if ffmpeg/ffprobe are not on the test machine.
        let probe = MediaProbeService(language: .en)
        guard probe.isAvailable(configuredFFmpegPath: nil) else { return }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-mc-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let src = root.appendingPathComponent("probe_src.mov")
        let fmpeg = FFmpegLocator.executableURL(configuredPath: nil)
        guard let ffmpeg = fmpeg else { return }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=1:size=320x240:rate=25",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
            "-c:v", "libx264", "-pix_fmt", "yuv420p",
            "-c:a", "pcm_s16le",
            src.path
        ]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "ffmpeg should generate test media")

        let result = probe.probeSync(url: src, configuredFFmpegPath: nil)
        switch result {
        case .success(let media):
            try expect(media.videoStreams.count == 1, "probed video stream count")
            try expect(media.audioStreams.count == 1, "probed audio stream count")
            try expect(media.videoStreams.first?.codecName == "h264", "probed video codec")
            try expect(media.audioStreams.first?.codecName == "pcm_s16le", "probed audio codec")
        case .failure(let code):
            try expect(false, "real probe should succeed, got \(code.rawValue)")
        }
    }

    private static func testMediaConversionPipelineIntegration() async throws {
        let probeService = MediaProbeService(language: .en)
        guard let ffmpeg = FFmpegLocator.executableURL(configuredPath: nil),
              probeService.isAvailable(configuredFFmpegPath: nil) else { return }

        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("321doit-convert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceMOV = root.appendingPathComponent("source.mov")
        let makeMOV = try await MediaProcessRunner.run(executableURL: ffmpeg, arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "testsrc=duration=0.4:size=96x64:rate=10",
            "-f", "lavfi", "-i", "sine=frequency=440:duration=0.4:sample_rate=48000",
            "-c:v", "mpeg4", "-c:a", "pcm_s16le", sourceMOV.path
        ])
        try expect(makeMOV.terminationStatus == 0, "could not generate rewrap fixture: \(makeMOV.stderrText)")
        guard case .success(let movProbe) = probeService.probeSync(url: sourceMOV, configuredFFmpegPath: nil) else {
            throw TestFailure("could not probe rewrap fixture")
        }

        let rewrapCompatibility = MediaCompatibilityService(language: .en)
            .decide(probed: movProbe, mode: .rewrap, target: .mkv)
        try expect(rewrapCompatibility.verdict != .incompatible, "MOV fixture should rewrap to MKV")
        let engine = MediaConversionEngine(language: .en, configuredFFmpegPath: "")
        let stagedMKV = try await engine.convert(
            sourceURL: sourceMOV,
            probed: movProbe,
            mode: .rewrap,
            target: .mkv,
            destinationDirectory: root,
            progress: { _ in }
        )
        try expect(FileManager.default.fileExists(atPath: stagedMKV.temporaryURL.path), "rewrap must create a staged file")
        try expect(!FileManager.default.fileExists(atPath: stagedMKV.finalURL.path), "unverified rewrap must not publish the final file")
        let verifier = MediaVerificationService(language: .en, configuredFFmpegPath: "")
        let (_, rewrapVerification) = try await verifier.verify(source: movProbe, outputURL: stagedMKV.temporaryURL, mode: .rewrap)
        try expect(rewrapVerification.passed, "rewrap content verification should pass: \(rewrapVerification.messages)")
        let finalMKV = try engine.commitVerifiedOutput(stagedMKV)
        try expect(FileManager.default.fileExists(atPath: finalMKV.path), "verified rewrap should publish atomically")

        let transcodeSettings = MediaTranscodeSettings(
            videoCodec: .h264,
            audioCodec: .aac,
            quality: .balanced,
            scale: .source,
            frameRate: .source
        )
        let transcodeCompatibility = MediaCompatibilityService(language: .en)
            .decide(probed: movProbe, mode: .transcode, target: .mp4, transcode: transcodeSettings)
        try expect(transcodeCompatibility.verdict != .incompatible, "MOV fixture should transcode to H.264 MP4")
        let stagedMP4 = try await engine.convert(
            sourceURL: sourceMOV,
            probed: movProbe,
            mode: .transcode,
            target: .mp4,
            transcodeSettings: transcodeSettings,
            destinationDirectory: root,
            progress: { _ in }
        )
        let (mp4Probe, transcodeVerification) = try await verifier.verify(
            source: movProbe,
            outputURL: stagedMP4.temporaryURL,
            mode: .transcode,
            transcodeSettings: transcodeSettings
        )
        try expect(transcodeVerification.passed, "H.264 MP4 verification should pass: \(transcodeVerification.messages)")
        try expect(mp4Probe.videoStreams.first?.codecName == "h264", "transcoded MP4 must contain H.264")
        let finalMP4 = try engine.commitVerifiedOutput(stagedMP4)
        try expect(FileManager.default.fileExists(atPath: finalMP4.path), "verified transcode should publish atomically")

        let webMSettings = MediaTranscodeSettings(
            videoCodec: .vp9,
            audioCodec: .opus,
            quality: .compact,
            scale: .source,
            frameRate: .source
        )
        let stagedWebM = try await engine.convert(
            sourceURL: sourceMOV,
            probed: movProbe,
            mode: .transcode,
            target: .webm,
            transcodeSettings: webMSettings,
            destinationDirectory: root,
            progress: { _ in }
        )
        let (webMProbe, webMVerification) = try await verifier.verify(
            source: movProbe,
            outputURL: stagedWebM.temporaryURL,
            mode: .transcode,
            transcodeSettings: webMSettings
        )
        try expect(webMVerification.passed, "VP9 WebM verification should pass: \(webMVerification.messages)")
        try expect(webMProbe.videoStreams.first?.codecName == "vp9", "transcoded WebM must contain VP9")
        try expect(webMProbe.audioStreams.first?.codecName == "opus", "transcoded WebM must contain Opus")
        _ = try engine.commitVerifiedOutput(stagedWebM)

        let sourceWAV = root.appendingPathComponent("source.wav")
        let makeWAV = try await MediaProcessRunner.run(executableURL: ffmpeg, arguments: [
            "-hide_banner", "-v", "error", "-y",
            "-f", "lavfi", "-i", "sine=frequency=880:duration=0.4:sample_rate=48000",
            "-c:a", "pcm_s24le", sourceWAV.path
        ])
        try expect(makeWAV.terminationStatus == 0, "could not generate WAV fixture")
        guard case .success(let wavProbe) = probeService.probeSync(url: sourceWAV, configuredFFmpegPath: nil) else {
            throw TestFailure("could not probe WAV fixture")
        }
        let audioCompatibility = MediaCompatibilityService(language: .en)
            .decide(probed: wavProbe, mode: .losslessAudio, target: .flac)
        try expect(audioCompatibility.verdict != .incompatible, "24-bit WAV should lossless-convert to FLAC")
        let stagedFLAC = try await engine.convert(
            sourceURL: sourceWAV,
            probed: wavProbe,
            mode: .losslessAudio,
            target: .flac,
            destinationDirectory: root,
            progress: { _ in }
        )
        let (flacProbe, audioVerification) = try await verifier.verify(source: wavProbe, outputURL: stagedFLAC.temporaryURL, mode: .losslessAudio)
        try expect(audioVerification.passed, "WAV -> FLAC canonical PCM verification should pass: \(audioVerification.messages)")
        let finalFLAC = try engine.commitVerifiedOutput(stagedFLAC)

        let report = MediaConversionReport(
            schema: "com.321doit.media-conversion-result",
            schemaVersion: 1,
            taskID: UUID(),
            createdAt: Date(),
            startedAt: stagedFLAC.startedAt,
            endedAt: stagedFLAC.completedAt,
            appVersion: "test",
            ffmpegVersion: stagedFLAC.ffmpegVersion,
            projectAssociationMode: "independent",
            linkedProjectID: nil,
            sourcePath: sourceWAV.path,
            outputPath: finalFLAC.path,
            sourceSizeBytes: wavProbe.sizeBytes,
            outputSizeBytes: flacProbe.sizeBytes,
            mode: .losslessAudio,
            targetContainer: .flac,
            transcodeSettings: nil,
            projectContext: nil,
            ffmpegArguments: stagedFLAC.ffmpegArguments,
            sourceProbe: wavProbe,
            outputProbe: flacProbe,
            compatibility: audioCompatibility,
            reencodesVideo: audioCompatibility.reencodesVideo,
            reencodesAudio: audioCompatibility.reencodesAudio,
            verification: audioVerification,
            warnings: audioCompatibility.risks,
            errors: []
        )
        let reportURL = try MediaConversionReportWriter.write(report, beside: finalFLAC)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MediaConversionReport.self, from: Data(contentsOf: reportURL))
        try expect(decoded.schema == "com.321doit.media-conversion-result", "conversion report schema mismatch")
        try expect(decoded.verification.passed, "conversion report must record verification success")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw TestFailure(message)
        }
    }
}

struct TestFailure: LocalizedError {
    let message: String
    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
