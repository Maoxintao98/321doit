import Foundation

struct RegisteredCamera: Identifiable, Codable, Equatable {
    var id: UUID
    var label: String
    var currentCard: String
    var cardNames: [String]
    var nextExpectedClipID: String

    init(
        id: UUID = UUID(),
        label: String,
        currentCard: String = "",
        cardNames: [String] = [],
        nextExpectedClipID: String = ""
    ) {
        self.id = id
        self.label = label
        self.currentCard = currentCard
        self.cardNames = Self.normalizedCards(cardNames.isEmpty ? [currentCard] : cardNames)
        self.currentCard = self.cardNames.first ?? currentCard
        self.nextExpectedClipID = nextExpectedClipID
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, currentCard, cardNames, nextExpectedClipID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "Cam A"
        let decodedCurrent = try c.decodeIfPresent(String.self, forKey: .currentCard) ?? ""
        let decodedCards = try c.decodeIfPresent([String].self, forKey: .cardNames) ?? []
        cardNames = Self.normalizedCards(decodedCards.isEmpty ? [decodedCurrent] : decodedCards)
        currentCard = cardNames.first ?? decodedCurrent
        nextExpectedClipID = try c.decodeIfPresent(String.self, forKey: .nextExpectedClipID) ?? ""
    }

    mutating func normalizeCards() {
        cardNames = Self.normalizedCards(cardNames)
        currentCard = cardNames.first ?? ""
    }

    private static func normalizedCards(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            output.append(trimmed)
        }
        return output
    }
}

struct PrincipalCastMember: Identifiable, Codable, Equatable {
    var id: UUID
    var performerName: String
    var characterName: String
    var phone: String
    var note: String

    init(
        id: UUID = UUID(),
        performerName: String = "",
        characterName: String = "",
        phone: String = "",
        note: String = ""
    ) {
        self.id = id
        self.performerName = performerName
        self.characterName = characterName
        self.phone = phone
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, performerName, characterName, phone, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        performerName = try c.decodeIfPresent(String.self, forKey: .performerName) ?? ""
        characterName = try c.decodeIfPresent(String.self, forKey: .characterName) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct DepartmentContact: Identifiable, Codable, Equatable {
    var id: UUID
    var departmentName: String
    var leadName: String
    var phone: String
    var note: String

    init(
        id: UUID = UUID(),
        departmentName: String = "",
        leadName: String = "",
        phone: String = "",
        note: String = ""
    ) {
        self.id = id
        self.departmentName = departmentName
        self.leadName = leadName
        self.phone = phone
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case id, departmentName, leadName, phone, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        departmentName = try c.decodeIfPresent(String.self, forKey: .departmentName) ?? ""
        leadName = try c.decodeIfPresent(String.self, forKey: .leadName) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct Project: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var productionName: String
    var director: String
    var dp: String
    var ditName: String
    var scriptSupervisor: String
    var createdAt: Date
    var shootingDays: [ShootingDay]
    var cameraRegistry: [RegisteredCamera]
    var principalCast: [PrincipalCastMember]
    var departmentContacts: [DepartmentContact]
    var locationMemory: [String]

    static var defaultCameraRegistry: [RegisteredCamera] {
        defaultCameraRegistry(language: .system)
    }

    static func defaultCameraRegistry(language: AppLanguage) -> [RegisteredCamera] {
        let a = L10n.t("A机", "Cam A", language: language)
        let b = L10n.t("B机", "Cam B", language: language)
        return [
            RegisteredCamera(label: a, currentCard: "A01", cardNames: ["A01"], nextExpectedClipID: "A01C001"),
            RegisteredCamera(label: b, currentCard: "B01", cardNames: ["B01"], nextExpectedClipID: "B01C001")
        ]
    }

    init(
        id: UUID = UUID(),
        name: String = "Untitled",
        productionName: String = "",
        director: String = "",
        dp: String = "",
        ditName: String = "",
        scriptSupervisor: String = "",
        createdAt: Date = Date(),
        shootingDays: [ShootingDay] = [],
        cameraRegistry: [RegisteredCamera] = Project.defaultCameraRegistry,
        principalCast: [PrincipalCastMember] = [],
        departmentContacts: [DepartmentContact] = [],
        locationMemory: [String] = []
    ) {
        self.id = id
        self.name = name
        self.productionName = productionName
        self.director = director
        self.dp = dp
        self.ditName = ditName
        self.scriptSupervisor = scriptSupervisor
        self.createdAt = createdAt
        self.shootingDays = shootingDays
        self.cameraRegistry = cameraRegistry
        self.principalCast = principalCast
        self.departmentContacts = departmentContacts
        self.locationMemory = Self.normalizedMemory(locationMemory)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, productionName, director, dp, ditName, scriptSupervisor, createdAt, shootingDays, cameraRegistry, principalCast, departmentContacts, locationMemory
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        productionName = try c.decodeIfPresent(String.self, forKey: .productionName) ?? ""
        director = try c.decodeIfPresent(String.self, forKey: .director) ?? ""
        dp = try c.decodeIfPresent(String.self, forKey: .dp) ?? ""
        ditName = try c.decodeIfPresent(String.self, forKey: .ditName) ?? ""
        scriptSupervisor = try c.decodeIfPresent(String.self, forKey: .scriptSupervisor) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        shootingDays = try c.decodeIfPresent([ShootingDay].self, forKey: .shootingDays) ?? []
        cameraRegistry = try c.decodeIfPresent([RegisteredCamera].self, forKey: .cameraRegistry) ?? Project.defaultCameraRegistry
        principalCast = try c.decodeIfPresent([PrincipalCastMember].self, forKey: .principalCast) ?? []
        departmentContacts = try c.decodeIfPresent([DepartmentContact].self, forKey: .departmentContacts) ?? []
        locationMemory = Self.normalizedMemory(try c.decodeIfPresent([String].self, forKey: .locationMemory) ?? [])
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "Untitled Project" {
            return "Untitled"
        }
        return trimmed
    }

    var metadataOnly: ProjectMetadata {
        ProjectMetadata(
            id: id,
            name: name,
            productionName: productionName,
            director: director,
            dp: dp,
            ditName: ditName,
            scriptSupervisor: scriptSupervisor,
            createdAt: createdAt,
            cameraRegistry: cameraRegistry,
            principalCast: principalCast,
            departmentContacts: departmentContacts,
            locationMemory: locationMemory
        )
    }

    static func normalizedMemory(_ values: [String], limit: Int = 40) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            output.append(trimmed)
            if output.count >= limit { break }
        }
        return output
    }
}

struct ProjectMetadata: Codable, Equatable {
    var id: UUID
    var name: String
    var productionName: String
    var director: String
    var dp: String
    var ditName: String
    var scriptSupervisor: String
    var createdAt: Date
    var cameraRegistry: [RegisteredCamera]
    var principalCast: [PrincipalCastMember]
    var departmentContacts: [DepartmentContact]
    var locationMemory: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, productionName, director, dp, ditName, scriptSupervisor, createdAt, cameraRegistry, principalCast, departmentContacts, locationMemory
    }

    init(
        id: UUID,
        name: String,
        productionName: String,
        director: String,
        dp: String,
        ditName: String = "",
        scriptSupervisor: String = "",
        createdAt: Date,
        cameraRegistry: [RegisteredCamera] = Project.defaultCameraRegistry,
        principalCast: [PrincipalCastMember] = [],
        departmentContacts: [DepartmentContact] = [],
        locationMemory: [String] = []
    ) {
        self.id = id
        self.name = name
        self.productionName = productionName
        self.director = director
        self.dp = dp
        self.ditName = ditName
        self.scriptSupervisor = scriptSupervisor
        self.createdAt = createdAt
        self.cameraRegistry = cameraRegistry
        self.principalCast = principalCast
        self.departmentContacts = departmentContacts
        self.locationMemory = Project.normalizedMemory(locationMemory)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        productionName = try c.decodeIfPresent(String.self, forKey: .productionName) ?? ""
        director = try c.decodeIfPresent(String.self, forKey: .director) ?? ""
        dp = try c.decodeIfPresent(String.self, forKey: .dp) ?? ""
        ditName = try c.decodeIfPresent(String.self, forKey: .ditName) ?? ""
        scriptSupervisor = try c.decodeIfPresent(String.self, forKey: .scriptSupervisor) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        cameraRegistry = try c.decodeIfPresent([RegisteredCamera].self, forKey: .cameraRegistry) ?? Project.defaultCameraRegistry
        principalCast = try c.decodeIfPresent([PrincipalCastMember].self, forKey: .principalCast) ?? []
        departmentContacts = try c.decodeIfPresent([DepartmentContact].self, forKey: .departmentContacts) ?? []
        locationMemory = Project.normalizedMemory(try c.decodeIfPresent([String].self, forKey: .locationMemory) ?? [])
    }

    func project(shootingDays: [ShootingDay]) -> Project {
        Project(
            id: id,
            name: name,
            productionName: productionName,
            director: director,
            dp: dp,
            ditName: ditName,
            scriptSupervisor: scriptSupervisor,
            createdAt: createdAt,
            shootingDays: shootingDays,
            cameraRegistry: cameraRegistry,
            principalCast: principalCast,
            departmentContacts: departmentContacts,
            locationMemory: locationMemory
        )
    }
}
