import Foundation

struct ShootingDay: Identifiable, Codable, Equatable {
    var id: UUID
    var date: Date
    var label: String
    var scenes: [ScriptScene]
    var callSheet: ShootingDayCallSheet

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        label: String = "",
        scenes: [ScriptScene] = [],
        callSheet: ShootingDayCallSheet = ShootingDayCallSheet()
    ) {
        self.id = id
        self.date = date
        self.label = label
        self.scenes = scenes
        self.callSheet = callSheet
    }

    private enum CodingKeys: String, CodingKey {
        case id, date, label, scenes, callSheet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        scenes = try c.decodeIfPresent([ScriptScene].self, forKey: .scenes) ?? []
        callSheet = try c.decodeIfPresent(ShootingDayCallSheet.self, forKey: .callSheet) ?? ShootingDayCallSheet()
    }
}

enum ShootingDayType: String, Codable, CaseIterable, Identifiable {
    case shooting
    case rest
    case travel
    case pickup
    case rehearsal
    case fitting
    case techScout
    case cameraTest
    case wrap

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .shooting: return L10n.t("拍摄日", "Shooting Day", language: language)
        case .rest: return L10n.t("休息日", "Rest Day", language: language)
        case .travel: return L10n.t("转场日", "Travel Day", language: language)
        case .pickup: return L10n.t("补拍日", "Pickup Day", language: language)
        case .rehearsal: return L10n.t("围读 / 排练", "Read-through / Rehearsal", language: language)
        case .fitting: return L10n.t("定妆日", "Fitting Day", language: language)
        case .techScout: return L10n.t("勘景日", "Tech Scout", language: language)
        case .cameraTest: return L10n.t("设备测试日", "Camera Test", language: language)
        case .wrap: return L10n.t("杀青日", "Wrap Day", language: language)
        }
    }
}

enum ShootingDayCallSheetStatus: String, Codable, CaseIterable, Identifiable {
    case empty
    case draft
    case published
    case revised
    case completed
    case risky

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .empty: return L10n.t("未生成", "Not Created", language: language)
        case .draft: return L10n.t("草稿", "Draft", language: language)
        case .published: return L10n.t("已发布", "Published", language: language)
        case .revised: return L10n.t("已修改", "Revised", language: language)
        case .completed: return L10n.t("已完成", "Completed", language: language)
        case .risky: return L10n.t("有风险", "At Risk", language: language)
        }
    }
}

enum TimelineCategory: String, Codable, CaseIterable, Identifiable {
    case crewCall
    case castCall
    case makeup
    case wardrobe
    case shooting
    case meal
    case companyMove
    case wrap
    case custom

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .crewCall: return L10n.t("全组到场", "Crew Call", language: language)
        case .castCall: return L10n.t("演员通告", "Cast Call", language: language)
        case .makeup: return L10n.t("化妆", "Makeup", language: language)
        case .wardrobe: return L10n.t("服装", "Wardrobe", language: language)
        case .shooting: return L10n.t("拍摄", "Shooting", language: language)
        case .meal: return L10n.t("餐食", "Meal", language: language)
        case .companyMove: return L10n.t("转场", "Company Move", language: language)
        case .wrap: return L10n.t("收工", "Wrap", language: language)
        case .custom: return L10n.t("自定义", "Custom", language: language)
        }
    }
}

struct ShootingDayCallSheet: Codable, Equatable {
    var title: String
    var type: ShootingDayType
    var status: ShootingDayCallSheetStatus
    var callTime: String
    var estimatedStartTime: String
    var estimatedWrapTime: String
    var mainLocation: String
    var weatherNote: String
    var sunriseTime: String
    var sunsetTime: String
    var generalNote: String
    var timeline: [DayTimelineItem]
    var scenePlans: [DayScenePlan]
    var castCalls: [CastCall]
    var departmentCalls: [DepartmentCall]
    var locationInfo: LocationInfo
    var cameraPlans: [CameraCardPlan]
    var ditPlan: DITPlan
    var revisions: [CallSheetRevision]
    var updatedAt: Date

    init(
        title: String = "",
        type: ShootingDayType = .shooting,
        status: ShootingDayCallSheetStatus = .draft,
        callTime: String = "",
        estimatedStartTime: String = "",
        estimatedWrapTime: String = "",
        mainLocation: String = "",
        weatherNote: String = "",
        sunriseTime: String = "",
        sunsetTime: String = "",
        generalNote: String = "",
        timeline: [DayTimelineItem] = DayTimelineItem.defaultItems(),
        scenePlans: [DayScenePlan] = [],
        castCalls: [CastCall] = [],
        departmentCalls: [DepartmentCall] = DepartmentCall.defaultDepartments(),
        locationInfo: LocationInfo = LocationInfo(),
        cameraPlans: [CameraCardPlan] = CameraCardPlan.defaultPlans(),
        ditPlan: DITPlan = DITPlan(),
        revisions: [CallSheetRevision] = [],
        updatedAt: Date = Date()
    ) {
        self.title = title
        self.type = type
        self.status = status
        self.callTime = callTime
        self.estimatedStartTime = estimatedStartTime
        self.estimatedWrapTime = estimatedWrapTime
        self.mainLocation = mainLocation
        self.weatherNote = weatherNote
        self.sunriseTime = sunriseTime
        self.sunsetTime = sunsetTime
        self.generalNote = generalNote
        self.timeline = timeline
        self.scenePlans = scenePlans
        self.castCalls = castCalls
        self.departmentCalls = departmentCalls
        self.locationInfo = locationInfo
        self.cameraPlans = cameraPlans
        self.ditPlan = ditPlan
        self.revisions = revisions
        self.updatedAt = updatedAt
    }
}

struct DayTimelineItem: Identifiable, Codable, Equatable {
    var id: UUID
    var time: String
    var title: String
    var category: TimelineCategory
    var relatedDepartment: String
    var isKeyMilestone: Bool
    var note: String

    init(
        id: UUID = UUID(),
        time: String = "",
        title: String = "",
        category: TimelineCategory = .custom,
        relatedDepartment: String = "",
        isKeyMilestone: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.time = time
        self.title = title
        self.category = category
        self.relatedDepartment = relatedDepartment
        self.isKeyMilestone = isKeyMilestone
        self.note = note
    }

    static func defaultItems(language: AppLanguage = .system) -> [DayTimelineItem] {
        func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: language) }
        return [
            DayTimelineItem(time: "06:30", title: t("全组通告", "Crew Call"), category: .crewCall, isKeyMilestone: true),
            DayTimelineItem(time: "07:30", title: t("预计开机", "Start Shooting"), category: .shooting, isKeyMilestone: true),
            DayTimelineItem(time: "12:00", title: t("午饭", "Meal Break"), category: .meal),
            DayTimelineItem(time: "19:00", title: t("预计收工", "Wrap"), category: .wrap, isKeyMilestone: true)
        ]
    }
}

struct DayScenePlan: Identifiable, Codable, Equatable {
    var id: UUID
    var sceneID: UUID?
    var sceneNumber: String
    var shotNumber: String
    var dayNight: String
    var interiorExterior: String
    var location: String
    var summary: String
    var cast: [String]
    var cameraUnits: [String]
    var estimatedPages: String
    var isMustShoot: Bool
    var isCompleted: Bool
    var note: String

    init(
        id: UUID = UUID(),
        sceneID: UUID? = nil,
        sceneNumber: String = "",
        shotNumber: String = "",
        dayNight: String = "",
        interiorExterior: String = "",
        location: String = "",
        summary: String = "",
        cast: [String] = [],
        cameraUnits: [String] = [],
        estimatedPages: String = "",
        isMustShoot: Bool = true,
        isCompleted: Bool = false,
        note: String = ""
    ) {
        self.id = id
        self.sceneID = sceneID
        self.sceneNumber = sceneNumber
        self.shotNumber = shotNumber
        self.dayNight = dayNight
        self.interiorExterior = interiorExterior
        self.location = location
        self.summary = summary
        self.cast = cast
        self.cameraUnits = cameraUnits
        self.estimatedPages = estimatedPages
        self.isMustShoot = isMustShoot
        self.isCompleted = isCompleted
        self.note = note
    }
}

struct CastCall: Identifiable, Codable, Equatable {
    var id: UUID
    var performerName: String
    var characterName: String
    var callTime: String
    var makeupTime: String
    var wardrobeTime: String
    var standbyTime: String
    var phone: String
    var note: String
    var showInExport: Bool

    init(
        id: UUID = UUID(),
        performerName: String = "",
        characterName: String = "",
        callTime: String = "",
        makeupTime: String = "",
        wardrobeTime: String = "",
        standbyTime: String = "",
        phone: String = "",
        note: String = "",
        showInExport: Bool = true
    ) {
        self.id = id
        self.performerName = performerName
        self.characterName = characterName
        self.callTime = callTime
        self.makeupTime = makeupTime
        self.wardrobeTime = wardrobeTime
        self.standbyTime = standbyTime
        self.phone = phone
        self.note = note
        self.showInExport = showInExport
    }
}

struct DepartmentCall: Identifiable, Codable, Equatable {
    var id: UUID
    var departmentName: String
    var callTime: String
    var leadName: String
    var phone: String
    var note: String
    var showInExport: Bool

    init(
        id: UUID = UUID(),
        departmentName: String = "",
        callTime: String = "",
        leadName: String = "",
        phone: String = "",
        note: String = "",
        showInExport: Bool = true
    ) {
        self.id = id
        self.departmentName = departmentName
        self.callTime = callTime
        self.leadName = leadName
        self.phone = phone
        self.note = note
        self.showInExport = showInExport
    }

    static func defaultDepartments(language: AppLanguage = .system) -> [DepartmentCall] {
        [DepartmentCall(departmentName: L10n.t("导演组", "Director", language: language))]
    }
}

struct LocationInfo: Codable, Equatable {
    var meetingPoint: String
    var shootingLocation: String
    var parkingLocation: String
    var companyMoveNote: String
    var nearestHospital: String
    var emergencyContactName: String
    var emergencyContactPhone: String
    var safetyNotes: [String]

    init(
        meetingPoint: String = "",
        shootingLocation: String = "",
        parkingLocation: String = "",
        companyMoveNote: String = "",
        nearestHospital: String = "",
        emergencyContactName: String = "",
        emergencyContactPhone: String = "",
        safetyNotes: [String] = []
    ) {
        self.meetingPoint = meetingPoint
        self.shootingLocation = shootingLocation
        self.parkingLocation = parkingLocation
        self.companyMoveNote = companyMoveNote
        self.nearestHospital = nearestHospital
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.safetyNotes = safetyNotes
    }

    private enum CodingKeys: String, CodingKey {
        case meetingPoint, shootingLocation, parkingLocation, companyMoveNote
        case nearestHospital, emergencyContactName, emergencyContactPhone, safetyNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meetingPoint = try c.decodeIfPresent(String.self, forKey: .meetingPoint) ?? ""
        shootingLocation = try c.decodeIfPresent(String.self, forKey: .shootingLocation) ?? ""
        parkingLocation = try c.decodeIfPresent(String.self, forKey: .parkingLocation) ?? ""
        companyMoveNote = try c.decodeIfPresent(String.self, forKey: .companyMoveNote) ?? ""
        nearestHospital = try c.decodeIfPresent(String.self, forKey: .nearestHospital) ?? ""
        emergencyContactName = try c.decodeIfPresent(String.self, forKey: .emergencyContactName) ?? ""
        emergencyContactPhone = try c.decodeIfPresent(String.self, forKey: .emergencyContactPhone) ?? ""
        safetyNotes = try c.decodeIfPresent([String].self, forKey: .safetyNotes) ?? []
    }
}

struct CameraCardPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var unitName: String
    var cameraID: UUID?
    var cameraName: String
    var lensNote: String
    var recordingFormat: String
    var frameRate: String
    var resolution: String
    var colorProfile: String
    var expectedCardIDs: [String]
    var note: String

    init(
        id: UUID = UUID(),
        unitName: String = "",
        cameraID: UUID? = nil,
        cameraName: String = "",
        lensNote: String = "",
        recordingFormat: String = "",
        frameRate: String = "",
        resolution: String = "",
        colorProfile: String = "",
        expectedCardIDs: [String] = [],
        note: String = ""
    ) {
        self.id = id
        self.unitName = unitName
        self.cameraID = cameraID
        self.cameraName = cameraName
        self.lensNote = lensNote
        self.recordingFormat = recordingFormat
        self.frameRate = frameRate
        self.resolution = resolution
        self.colorProfile = colorProfile
        self.expectedCardIDs = expectedCardIDs
        self.note = note
    }

    static func defaultPlans(language: AppLanguage = .system) -> [CameraCardPlan] {
        let a = L10n.t("A机", "Cam A", language: language)
        let b = L10n.t("B机", "Cam B", language: language)
        return [
            CameraCardPlan(unitName: a, expectedCardIDs: ["A01"]),
            CameraCardPlan(unitName: b, expectedCardIDs: ["B01"])
        ]
    }
}

struct DITPlan: Codable, Equatable {
    var ditName: String
    var checksumAlgorithm: String
    var primaryDestinationName: String
    var backupDestinationName: String
    var shouldGenerateMHL: Bool
    var shouldGeneratePDFReport: Bool
    var proxyFormat: String
    var proxyWithLUT: Bool
    var shouldGenerateHandoffPackage: Bool
    var note: String

    init(
        ditName: String = "",
        checksumAlgorithm: String = "xxHash64",
        primaryDestinationName: String = "",
        backupDestinationName: String = "",
        shouldGenerateMHL: Bool = true,
        shouldGeneratePDFReport: Bool = true,
        proxyFormat: String = "H.264",
        proxyWithLUT: Bool = false,
        shouldGenerateHandoffPackage: Bool = true,
        note: String = ""
    ) {
        self.ditName = ditName
        self.checksumAlgorithm = checksumAlgorithm
        self.primaryDestinationName = primaryDestinationName
        self.backupDestinationName = backupDestinationName
        self.shouldGenerateMHL = shouldGenerateMHL
        self.shouldGeneratePDFReport = shouldGeneratePDFReport
        self.proxyFormat = proxyFormat
        self.proxyWithLUT = proxyWithLUT
        self.shouldGenerateHandoffPackage = shouldGenerateHandoffPackage
        self.note = note
    }
}

struct CallSheetRevision: Identifiable, Codable, Equatable {
    var id: UUID
    var revisionCode: String
    var createdAt: Date
    var summary: String
    var changedFields: [String]

    init(
        id: UUID = UUID(),
        revisionCode: String = "Rev.1",
        createdAt: Date = Date(),
        summary: String = "",
        changedFields: [String] = []
    ) {
        self.id = id
        self.revisionCode = revisionCode
        self.createdAt = createdAt
        self.summary = summary
        self.changedFields = changedFields
    }
}

enum CheckLevel: String, Codable, CaseIterable {
    case info
    case warning
    case critical
}

enum ShootingDaySection: String, Codable, CaseIterable {
    case overview
    case timeline
    case scenes
    case cast
    case departments
    case location
    case camera
    case dit
    case export
}

struct ShootingDayCheckResult: Identifiable, Equatable {
    var id = UUID()
    var level: CheckLevel
    var message: String
    var relatedSection: ShootingDaySection
}

enum CallSheetExportFormat: String, CaseIterable, Identifiable {
    case html
    case json

    var id: String { rawValue }

    func label(language: AppLanguage) -> String {
        switch self {
        case .html: return L10n.t("HTML 预览", "HTML Preview", language: language)
        case .json: return L10n.t("JSON 数据", "JSON Data", language: language)
        }
    }

    var fileExtension: String { rawValue }
}

struct ScriptScene: Identifiable, Codable, Equatable {
    var id: UUID
    var sceneNumber: String
    var description: String
    var shots: [Shot]

    init(
        id: UUID = UUID(),
        sceneNumber: String = "",
        description: String = "",
        shots: [Shot] = []
    ) {
        self.id = id
        self.sceneNumber = sceneNumber
        self.description = description
        self.shots = shots
    }
}

struct Shot: Identifiable, Codable, Equatable {
    var id: UUID
    var shotNumber: String
    var cameraSetup: String
    var takes: [Take]

    init(
        id: UUID = UUID(),
        shotNumber: String = "1",
        cameraSetup: String = "A",
        takes: [Take] = []
    ) {
        self.id = id
        self.shotNumber = shotNumber
        self.cameraSetup = cameraSetup
        self.takes = takes
    }
}

enum RecordType: String, Codable, Equatable {
    case take
    case faultEvent
}

struct CameraFaultBackup: Codable, Equatable {
    var cameraRecordID: UUID
    var status: TakeStatus
    var rollState: CameraRollState
}

struct FaultEventBackup: Codable, Equatable {
    var status: TakeStatus
    var isCircleTake: Bool
    var cameraBackups: [CameraFaultBackup]
}

struct Take: Identifiable, Codable, Equatable {
    var id: UUID
    var recordType: RecordType
    var sceneNumber: String
    var shotNumber: String
    var takeNumber: Int
    var cameraLabel: String
    var status: TakeStatus
    var isCircleTake: Bool
    var pictureUsable: Bool
    var soundUsable: Bool
    var performanceRating: Int
    var technicalRating: Int
    var performanceNote: String
    var technicalNote: String
    var generalNote: String
    var quickTags: [String]
    var cameraRecords: [CameraRecord]
    var linkedClips: [ClipReference]
    var faultBackup: FaultEventBackup?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        recordType: RecordType = .take,
        sceneNumber: String = "1",
        shotNumber: String = "1",
        takeNumber: Int = 1,
        cameraLabel: String = "A",
        status: TakeStatus = .hold,
        isCircleTake: Bool = false,
        pictureUsable: Bool = true,
        soundUsable: Bool = true,
        performanceRating: Int = 3,
        technicalRating: Int = 3,
        performanceNote: String = "",
        technicalNote: String = "",
        generalNote: String = "",
        quickTags: [String] = [],
        cameraRecords: [CameraRecord] = CameraRecord.defaultRecords(),
        linkedClips: [ClipReference] = [],
        faultBackup: FaultEventBackup? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.recordType = recordType
        self.sceneNumber = sceneNumber
        self.shotNumber = shotNumber
        self.takeNumber = takeNumber
        self.cameraLabel = cameraLabel
        self.status = status
        self.isCircleTake = isCircleTake
        self.pictureUsable = pictureUsable
        self.soundUsable = soundUsable
        self.performanceRating = performanceRating
        self.technicalRating = technicalRating
        self.performanceNote = performanceNote
        self.technicalNote = technicalNote
        self.generalNote = generalNote
        self.quickTags = quickTags
        self.cameraRecords = cameraRecords.isEmpty ? CameraRecord.defaultRecords() : cameraRecords
        self.linkedClips = linkedClips
        self.faultBackup = faultBackup
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, recordType, sceneNumber, shotNumber, takeNumber, cameraLabel
        case status, isCircleTake, pictureUsable, soundUsable
        case performanceRating, technicalRating
        case performanceNote, technicalNote, generalNote
        case quickTags, cameraRecords, linkedClips, faultBackup, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        recordType = try c.decodeIfPresent(RecordType.self, forKey: .recordType) ?? .take
        sceneNumber = try c.decodeIfPresent(String.self, forKey: .sceneNumber) ?? "1"
        shotNumber = try c.decodeIfPresent(String.self, forKey: .shotNumber) ?? "1"
        takeNumber = try c.decodeIfPresent(Int.self, forKey: .takeNumber) ?? 1
        cameraLabel = try c.decodeIfPresent(String.self, forKey: .cameraLabel) ?? "A"
        status = try c.decodeIfPresent(TakeStatus.self, forKey: .status) ?? .hold
        isCircleTake = try c.decodeIfPresent(Bool.self, forKey: .isCircleTake) ?? false
        pictureUsable = try c.decodeIfPresent(Bool.self, forKey: .pictureUsable) ?? true
        soundUsable = try c.decodeIfPresent(Bool.self, forKey: .soundUsable) ?? true
        performanceRating = try c.decodeIfPresent(Int.self, forKey: .performanceRating) ?? 3
        technicalRating = try c.decodeIfPresent(Int.self, forKey: .technicalRating) ?? 3
        performanceNote = try c.decodeIfPresent(String.self, forKey: .performanceNote) ?? ""
        technicalNote = try c.decodeIfPresent(String.self, forKey: .technicalNote) ?? ""
        generalNote = try c.decodeIfPresent(String.self, forKey: .generalNote) ?? ""
        quickTags = try c.decodeIfPresent([String].self, forKey: .quickTags) ?? []
        let decodedRecords = try c.decodeIfPresent([CameraRecord].self, forKey: .cameraRecords) ?? []
        cameraRecords = decodedRecords.isEmpty ? CameraRecord.defaultRecords(cameraLabel: cameraLabel) : decodedRecords
        linkedClips = try c.decodeIfPresent([ClipReference].self, forKey: .linkedClips) ?? []
        faultBackup = try c.decodeIfPresent(FaultEventBackup.self, forKey: .faultBackup)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }

    func duplicated(nextTakeNumber: Int) -> Take {
        var copy = self
        let now = Date()
        copy.id = UUID()
        copy.takeNumber = nextTakeNumber
        copy.createdAt = now
        copy.updatedAt = now
        return copy
    }
}

enum CameraRollState: String, Codable, Equatable, CaseIterable {
    case recorded
    case noRoll
    case faultConsumed

    func label(language: AppLanguage) -> String {
        switch self {
        case .recorded: return L10n.t("已录制", "Recorded", language: language)
        case .noRoll: return L10n.t("未开机", "No Roll", language: language)
        case .faultConsumed: return L10n.t("故障占用", "Fault Consumed", language: language)
        }
    }
}

struct CameraRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var cameraLabel: String
    var status: TakeStatus
    var rollState: CameraRollState
    var clipName: String
    var cardName: String
    var tcIn: String
    var tcOut: String
    var pictureAvailable: Bool
    var audioAvailable: Bool
    var notes: String

    init(
        id: UUID = UUID(),
        cameraLabel: String,
        status: TakeStatus = .hold,
        rollState: CameraRollState = .recorded,
        clipName: String = "",
        cardName: String = "",
        tcIn: String = "",
        tcOut: String = "",
        pictureAvailable: Bool = true,
        audioAvailable: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.cameraLabel = cameraLabel
        self.status = status
        self.rollState = rollState
        self.clipName = clipName
        self.cardName = cardName
        self.tcIn = tcIn
        self.tcOut = tcOut
        self.pictureAvailable = pictureAvailable
        self.audioAvailable = audioAvailable
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case id, cameraLabel, status, rollState, clipName, cardName
        case tcIn, tcOut, pictureAvailable, audioAvailable, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cameraLabel = try c.decodeIfPresent(String.self, forKey: .cameraLabel) ?? "Unknown"
        status = try c.decodeIfPresent(TakeStatus.self, forKey: .status) ?? .hold
        rollState = try c.decodeIfPresent(CameraRollState.self, forKey: .rollState) ?? .recorded
        clipName = try c.decodeIfPresent(String.self, forKey: .clipName) ?? ""
        cardName = try c.decodeIfPresent(String.self, forKey: .cardName) ?? ""
        tcIn = try c.decodeIfPresent(String.self, forKey: .tcIn) ?? ""
        tcOut = try c.decodeIfPresent(String.self, forKey: .tcOut) ?? ""
        pictureAvailable = try c.decodeIfPresent(Bool.self, forKey: .pictureAvailable) ?? true
        audioAvailable = try c.decodeIfPresent(Bool.self, forKey: .audioAvailable) ?? true
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    static func defaultRecords(cameraLabel: String = "A", language: AppLanguage = .system) -> [CameraRecord] {
        let labels = ["A", "B", "C"]
        return labels.map { label in
            let cam = L10n.t("\(label)机", "Cam \(label)", language: language)
            return CameraRecord(cameraLabel: cam, status: label == cameraLabel ? .hold : .hold)
        }
    }
}

struct ClipReference: Identifiable, Codable, Equatable {
    var id: UUID
    var fileName: String
    var filePath: String
    var cameraCard: String
    var checksum: String
    var proxyPath: String
    var offloadSessionId: String

    init(
        id: UUID = UUID(),
        fileName: String = "",
        filePath: String = "",
        cameraCard: String = "",
        checksum: String = "",
        proxyPath: String = "",
        offloadSessionId: String = ""
    ) {
        self.id = id
        self.fileName = fileName
        self.filePath = filePath
        self.cameraCard = cameraCard
        self.checksum = checksum
        self.proxyPath = proxyPath
        self.offloadSessionId = offloadSessionId
    }
}

enum TakeStatus: String, CaseIterable, Codable, Identifiable {
    /// No status chosen yet (a freshly created take). Shows no badge.
    case unset
    case good
    case hold
    case ng
    case reset
    case wildTrack
    case rehearsal

    var id: String { rawValue }

    /// Statuses a user can pick, in on-set priority order (OK · KP · NG · …).
    /// Excludes `.unset`, which is only the implicit default.
    static let selectable: [TakeStatus] = [.good, .hold, .ng, .reset, .wildTrack, .rehearsal]

    var hasStatus: Bool { self != .unset }

    func label(language: AppLanguage) -> String {
        switch self {
        case .unset:
            return L10n.t("未标记", "Unmarked", language: language)
        case .good:
            return L10n.t("OK", "OK", language: language)
        case .ng:
            return L10n.t("NG", "NG", language: language)
        case .hold:
            return L10n.t("KP", "KP", language: language)
        case .reset:
            return L10n.t("重置", "Reset", language: language)
        case .wildTrack:
            return L10n.t("野声", "Wild Track", language: language)
        case .rehearsal:
            return L10n.t("排练", "Rehearsal", language: language)
        }
    }
}

struct ScriptLogDocument: Codable, Equatable {
    var projectID: UUID
    var shootingDays: [ShootingDay]
    var updatedAt: Date
}
