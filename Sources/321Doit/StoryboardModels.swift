import Foundation

enum StoryboardMarkdownRendering {
    static func attributedString(from markdown: String) -> AttributedString {
        let displayMarkdown = markdown.replacingOccurrences(
            of: #"~~(.+?)~~"#,
            with: "$1",
            options: .regularExpression
        )
        return (try? AttributedString(
            markdown: displayMarkdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(displayMarkdown)
    }

    static func plainText(from markdown: String) -> String {
        String(attributedString(from: markdown).characters)
    }
}

enum StoryboardShotSize: String, Codable, CaseIterable, Identifiable {
    case extremeWide
    case wide
    case full
    case medium
    case mediumCloseUp
    case closeUp
    case extremeCloseUp

    var id: String { rawValue }
}

enum StoryboardCameraAngle: String, Codable, CaseIterable, Identifiable {
    case eyeLevel
    case high
    case low
    case overhead
    case dutch
    case pointOfView

    var id: String { rawValue }
}

enum StoryboardCameraMotionKind: String, Codable, CaseIterable, Identifiable {
    case locked
    case push
    case pull
    case pan
    case tilt
    case dolly
    case truck
    case crane
    case handheld
    case steadicam
    case zoom
    case follow
    case rise
    case fall
    case orbit

    var id: String { rawValue }

    static let directorWheelCases: [StoryboardCameraMotionKind] = [
        .push, .pull, .pan, .truck, .follow, .rise, .fall, .orbit, .locked
    ]
}

struct StoryboardPoint: Codable, Equatable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

struct StoryboardFrame: Codable, Equatable {
    var assetID: UUID?
    var cropScale: Double
    var cropOffset: StoryboardPoint

    init(
        assetID: UUID? = nil,
        cropScale: Double = 1,
        cropOffset: StoryboardPoint = StoryboardPoint(x: 0, y: 0)
    ) {
        self.assetID = assetID
        self.cropScale = cropScale
        self.cropOffset = cropOffset
    }
}

struct StoryboardCanvasElement: Identifiable, Codable, Equatable {
    var id: UUID
    var assetID: UUID
    var position: StoryboardPoint
    var size: StoryboardSize
    var rotationDegrees: Double
    var flippedHorizontally: Bool
    var flippedVertically: Bool
    var opacity: Double

    init(
        id: UUID = UUID(),
        assetID: UUID,
        position: StoryboardPoint = StoryboardPoint(x: 0.5, y: 0.5),
        size: StoryboardSize = StoryboardSize(width: 0.38, height: 0.38),
        rotationDegrees: Double = 0,
        flippedHorizontally: Bool = false,
        flippedVertically: Bool = false,
        opacity: Double = 1
    ) {
        self.id = id
        self.assetID = assetID
        self.position = position
        self.size = size
        self.rotationDegrees = rotationDegrees
        self.flippedHorizontally = flippedHorizontally
        self.flippedVertically = flippedVertically
        self.opacity = opacity
    }
}

struct StoryboardCharacterInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var position: StoryboardPoint
    var facingDegrees: Double
    var note: String

    init(
        id: UUID = UUID(),
        name: String,
        position: StoryboardPoint,
        facingDegrees: Double = 0,
        note: String = ""
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.facingDegrees = facingDegrees
        self.note = note
    }
}

struct StoryboardCameraPlacement: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var position: StoryboardPoint
    var rotationDegrees: Double
    var fieldOfViewDegrees: Double
    var equivalentFocalLengthMM: Double?
    var range: Double

    init(
        id: UUID = UUID(),
        name: String = "机位",
        position: StoryboardPoint = StoryboardPoint(x: 0.16, y: 0.82),
        rotationDegrees: Double = -28,
        fieldOfViewDegrees: Double = 52,
        equivalentFocalLengthMM: Double? = 35,
        range: Double = 0.46
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.rotationDegrees = rotationDegrees
        self.fieldOfViewDegrees = fieldOfViewDegrees
        self.equivalentFocalLengthMM = equivalentFocalLengthMM
        self.range = range
    }
}

struct StoryboardCameraMotion: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardCameraMotionKind
    var start: StoryboardPoint?
    var end: StoryboardPoint?
    var note: String
    var durationSeconds: Double?
    var direction: String?
    var easing: StoryboardMotionEasing?

    init(
        id: UUID = UUID(),
        kind: StoryboardCameraMotionKind = .locked,
        start: StoryboardPoint? = nil,
        end: StoryboardPoint? = nil,
        note: String = "",
        durationSeconds: Double? = nil,
        direction: String? = nil,
        easing: StoryboardMotionEasing? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.note = note
        self.durationSeconds = durationSeconds
        self.direction = direction
        self.easing = easing
    }
}

struct StoryboardMovementPath: Identifiable, Codable, Equatable {
    var id: UUID
    var subjectID: UUID?
    var points: [StoryboardPoint]
    var note: String
    var kind: StoryboardMovementPathKind?
    var startSeconds: Double?
    var durationSeconds: Double?
    var displayText: String?
    var fontSize: Double?

    init(
        id: UUID = UUID(),
        subjectID: UUID? = nil,
        points: [StoryboardPoint] = [],
        note: String = "",
        kind: StoryboardMovementPathKind? = nil,
        startSeconds: Double? = nil,
        durationSeconds: Double? = nil,
        displayText: String? = nil,
        fontSize: Double? = nil
    ) {
        self.id = id
        self.subjectID = subjectID
        self.points = points
        self.note = note
        self.kind = kind
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.displayText = displayText
        self.fontSize = fontSize
    }
}

enum StoryboardAnnotationKind: String, Codable {
    case freehand
    case arrow
    case rectangle
    case text
}

struct StoryboardAnnotation: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardAnnotationKind
    var points: [StoryboardPoint]
    var text: String
    var colorHex: String

    init(
        id: UUID = UUID(),
        kind: StoryboardAnnotationKind,
        points: [StoryboardPoint] = [],
        text: String = "",
        colorHex: String = "#FF3B30"
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.text = text
        self.colorHex = colorHex
    }
}

/// Groups drawing annotations into a user-visible canvas layer while keeping
/// the annotation payload backward-compatible with existing storyboard files.
struct StoryboardAnnotationLayer: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var annotationIDs: [UUID]

    init(
        id: UUID = UUID(),
        name: String = "绘画 1",
        annotationIDs: [UUID] = []
    ) {
        self.id = id
        self.name = name
        self.annotationIDs = annotationIDs
    }
}

enum StoryboardCanvasLayerKind: String, Codable, Equatable {
    case image
    case drawing
}

/// A reference into the shot's unified, bottom-to-top canvas stack.
/// Background artwork is deliberately excluded and always stays locked below it.
struct StoryboardCanvasLayerReference: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardCanvasLayerKind

    init(id: UUID, kind: StoryboardCanvasLayerKind) {
        self.id = id
        self.kind = kind
    }
}

enum StoryboardAudioCueKind: String, Codable, CaseIterable, Identifiable {
    case dialogue
    case music
    case soundEffect
    case ambience

    var id: String { rawValue }
}

struct StoryboardAudioCue: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: StoryboardAudioCueKind
    var text: String
    var startSeconds: Double
    var durationSeconds: Double
    var assetID: UUID?

    init(
        id: UUID = UUID(),
        kind: StoryboardAudioCueKind,
        text: String,
        startSeconds: Double = 0,
        durationSeconds: Double = 0,
        assetID: UUID? = nil
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.assetID = assetID
    }
}

struct StoryboardShot: Identifiable, Codable, Equatable {
    var id: UUID
    var shotNumber: String
    var description: String
    var durationSeconds: Double
    var shotSize: StoryboardShotSize
    var cameraAngle: StoryboardCameraAngle
    var lens: String
    var frame: StoryboardFrame
    var canvasElements: [StoryboardCanvasElement]?
    var characters: [StoryboardCharacterInstance]
    var cameraPlacements: [StoryboardCameraPlacement]?
    var cameraMotions: [StoryboardCameraMotion]
    var movementPaths: [StoryboardMovementPath]
    var annotations: [StoryboardAnnotation]
    var annotationLayers: [StoryboardAnnotationLayer]?
    var canvasLayerOrder: [StoryboardCanvasLayerReference]?
    var audioCues: [StoryboardAudioCue]
    var notes: String
    var title: String?
    var directorIntent: String?
    var soundDescription: String?
    var transition: StoryboardTransitionKind?
    var screenDirection: StoryboardScreenDirection?
    var expectedTakes: Int?
    var productionDifficulty: Int?
    var propIDs: [UUID]?
    var specialEquipment: [String]?
    var createdBy: StoryboardCreatedBy?

    init(
        id: UUID = UUID(),
        shotNumber: String,
        description: String = "",
        durationSeconds: Double = 3,
        shotSize: StoryboardShotSize = .medium,
        cameraAngle: StoryboardCameraAngle = .eyeLevel,
        lens: String = "",
        frame: StoryboardFrame = StoryboardFrame(),
        canvasElements: [StoryboardCanvasElement]? = nil,
        characters: [StoryboardCharacterInstance] = [],
        cameraPlacements: [StoryboardCameraPlacement]? = nil,
        cameraMotions: [StoryboardCameraMotion] = [],
        movementPaths: [StoryboardMovementPath] = [],
        annotations: [StoryboardAnnotation] = [],
        annotationLayers: [StoryboardAnnotationLayer]? = nil,
        canvasLayerOrder: [StoryboardCanvasLayerReference]? = nil,
        audioCues: [StoryboardAudioCue] = [],
        notes: String = "",
        title: String? = nil,
        directorIntent: String? = nil,
        soundDescription: String? = nil,
        transition: StoryboardTransitionKind? = nil,
        screenDirection: StoryboardScreenDirection? = nil,
        expectedTakes: Int? = nil,
        productionDifficulty: Int? = nil,
        propIDs: [UUID]? = nil,
        specialEquipment: [String]? = nil,
        createdBy: StoryboardCreatedBy? = nil
    ) {
        self.id = id
        self.shotNumber = shotNumber
        self.description = description
        self.durationSeconds = durationSeconds
        self.shotSize = shotSize
        self.cameraAngle = cameraAngle
        self.lens = lens
        self.frame = frame
        self.canvasElements = canvasElements
        self.characters = characters
        self.cameraPlacements = cameraPlacements
        self.cameraMotions = cameraMotions
        self.movementPaths = movementPaths
        self.annotations = annotations
        self.annotationLayers = annotationLayers
        self.canvasLayerOrder = canvasLayerOrder
        self.audioCues = audioCues
        self.notes = notes
        self.title = title
        self.directorIntent = directorIntent
        self.soundDescription = soundDescription
        self.transition = transition
        self.screenDirection = screenDirection
        self.expectedTakes = expectedTakes
        self.productionDifficulty = productionDifficulty
        self.propIDs = propIDs
        self.specialEquipment = specialEquipment
        self.createdBy = createdBy
    }
}

extension StoryboardShot {
    /// Creates the following shot while preserving production continuity.
    /// User-authored content, visual artwork, and sound start empty; every
    /// other shot field carries forward from the preceding shot.
    func nextShotCopy(shotNumber: String) -> StoryboardShot {
        var copy = self
        copy.id = UUID()
        copy.shotNumber = shotNumber
        copy.description = ""
        copy.title = nil

        copy.frame = StoryboardFrame()
        copy.canvasElements = nil
        copy.annotations = []
        copy.annotationLayers = nil
        copy.canvasLayerOrder = nil

        copy.soundDescription = nil
        copy.audioCues = []

        var characterIDs: [UUID: UUID] = [:]
        copy.characters = copy.characters.map { character in
            var duplicated = character
            duplicated.id = UUID()
            characterIDs[character.id] = duplicated.id
            return duplicated
        }

        var cameraIDs: [UUID: UUID] = [:]
        copy.cameraPlacements = copy.cameraPlacements?.map { camera in
            var duplicated = camera
            duplicated.id = UUID()
            cameraIDs[camera.id] = duplicated.id
            return duplicated
        }

        copy.cameraMotions = copy.cameraMotions.map { motion in
            var duplicated = motion
            duplicated.id = UUID()
            return duplicated
        }

        copy.movementPaths = copy.movementPaths.map { path in
            var duplicated = path
            duplicated.id = UUID()
            if let subjectID = path.subjectID {
                duplicated.subjectID = characterIDs[subjectID] ?? cameraIDs[subjectID] ?? subjectID
            }
            return duplicated
        }
        return copy
    }

    /// Returns a complete, valid bottom-to-top stack. Older files have no
    /// explicit order, so their former rendering order (images, then ink) is
    /// preserved automatically.
    var resolvedCanvasLayerOrder: [StoryboardCanvasLayerReference] {
        let imageIDs = Set((canvasElements ?? []).map(\.id))
        let drawingIDs = Set((annotationLayers ?? []).map(\.id))
        var seen = Set<UUID>()
        var result: [StoryboardCanvasLayerReference] = []

        for reference in canvasLayerOrder ?? [] {
            let exists = reference.kind == .image
                ? imageIDs.contains(reference.id)
                : drawingIDs.contains(reference.id)
            guard exists, seen.insert(reference.id).inserted else { continue }
            result.append(reference)
        }
        for element in canvasElements ?? [] where seen.insert(element.id).inserted {
            result.append(StoryboardCanvasLayerReference(id: element.id, kind: .image))
        }
        for layer in annotationLayers ?? [] where seen.insert(layer.id).inserted {
            result.append(StoryboardCanvasLayerReference(id: layer.id, kind: .drawing))
        }
        return result
    }
}

struct StoryboardScene: Identifiable, Codable, Equatable {
    var id: UUID
    var sceneNumber: String
    var title: String
    var synopsis: String
    var location: String
    var timeOfDay: String
    var shots: [StoryboardShot]
    var interiorExterior: StoryboardInteriorExterior?
    var directorIntent: String?
    var targetDurationSeconds: Double?
    var locationID: UUID?
    var space: StoryboardSceneSpace?

    init(
        id: UUID = UUID(),
        sceneNumber: String,
        title: String = "",
        synopsis: String = "",
        location: String = "",
        timeOfDay: String = "",
        shots: [StoryboardShot] = [],
        interiorExterior: StoryboardInteriorExterior? = nil,
        directorIntent: String? = nil,
        targetDurationSeconds: Double? = nil,
        locationID: UUID? = nil,
        space: StoryboardSceneSpace? = nil
    ) {
        self.id = id
        self.sceneNumber = sceneNumber
        self.title = title
        self.synopsis = synopsis
        self.location = location
        self.timeOfDay = timeOfDay
        self.shots = shots
        self.interiorExterior = interiorExterior
        self.directorIntent = directorIntent
        self.targetDurationSeconds = targetDurationSeconds
        self.locationID = locationID
        self.space = space
    }
}

extension StoryboardScene {
    /// Living Storyboard uses a simple, scene-local 1...N sequence. Legacy
    /// projects used values such as 1A/1B and kept a separate shot title; both
    /// are normalized without discarding any text.
    var livingStoryboardNormalizedShots: [StoryboardShot] {
        shots.enumerated().map { offset, original in
            var shot = original
            shot.shotNumber = String(offset + 1)

            if let legacyTitle = shot.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyTitle.isEmpty {
                let description = shot.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if description.isEmpty {
                    shot.description = legacyTitle
                } else if description != legacyTitle && !description.hasPrefix(legacyTitle + "\n") {
                    shot.description = legacyTitle + "\n\n" + shot.description
                }
            }
            shot.title = nil
            return shot
        }
    }
}

struct StoryboardAssetVersion: Identifiable, Codable, Equatable {
    var id: UUID
    var relativePath: String
    var createdAt: Date
    var source: String
    var checksum: String?
    var parentVersionID: UUID?
    var prompt: String?
    var maskAssetID: UUID?
    var createdBy: String?

    init(
        id: UUID = UUID(),
        relativePath: String,
        createdAt: Date = Date(),
        source: String,
        checksum: String? = nil,
        parentVersionID: UUID? = nil,
        prompt: String? = nil,
        maskAssetID: UUID? = nil,
        createdBy: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.source = source
        self.checksum = checksum
        self.parentVersionID = parentVersionID
        self.prompt = prompt
        self.maskAssetID = maskAssetID
        self.createdBy = createdBy
    }
}

enum StoryboardAssetKind: String, Codable, CaseIterable, Identifiable {
    case image
    case audio
    case reference

    var id: String { rawValue }
}

struct StoryboardAsset: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var versions: [StoryboardAssetVersion]
    var activeVersionID: UUID?
    var kind: StoryboardAssetKind?

    init(
        id: UUID = UUID(),
        name: String,
        versions: [StoryboardAssetVersion] = [],
        activeVersionID: UUID? = nil,
        kind: StoryboardAssetKind? = .image
    ) {
        self.id = id
        self.name = name
        self.versions = versions
        self.activeVersionID = activeVersionID ?? versions.last?.id
        self.kind = kind
    }
}

struct StoryboardFieldLock: Identifiable, Codable, Equatable {
    var id: UUID
    var entityID: UUID
    var field: String
    var owner: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        entityID: UUID,
        field: String = "*",
        owner: String = "user",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.entityID = entityID
        self.field = field
        self.owner = owner
        self.createdAt = createdAt
    }
}

struct StoryboardDocument: Identifiable, Codable, Equatable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: UUID
    var linkedProjectID: UUID?
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var revision: Int
    var scenes: [StoryboardScene]
    var assets: [StoryboardAsset]
    var fieldLocks: [StoryboardFieldLock]
    var production: StoryboardProductionData?

    init(
        schemaVersion: Int = StoryboardDocument.currentSchemaVersion,
        id: UUID = UUID(),
        linkedProjectID: UUID? = nil,
        title: String = "未命名分镜",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        revision: Int = 0,
        scenes: [StoryboardScene] = [],
        assets: [StoryboardAsset] = [],
        fieldLocks: [StoryboardFieldLock] = [],
        production: StoryboardProductionData? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.linkedProjectID = linkedProjectID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.revision = revision
        self.scenes = scenes
        self.assets = assets
        self.fieldLocks = fieldLocks
        self.production = production
    }

    func scene(id: UUID) -> StoryboardScene? {
        scenes.first { $0.id == id }
    }

    func shot(id: UUID) -> StoryboardShot? {
        scenes.lazy.compactMap { $0.shots.first { $0.id == id } }.first
    }
}
