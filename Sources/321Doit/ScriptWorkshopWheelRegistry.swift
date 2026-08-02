import Foundation

enum ScriptWorkshopWheelSubmenu: Equatable {
    case projectCharacters
}

/// The shipping 0.8 primary-ring mapping. Rendering, hit-testing, and agent
/// metadata consume this registry so visible sectors and command targets cannot
/// drift apart as more hierarchical menus are added.
struct ScriptWorkshopWheelDescriptor: Identifiable, Equatable {
    var id: String { kind.rawValue }
    let kind: ScriptWorkshopBlockKind
    let systemImage: String
    let submenu: ScriptWorkshopWheelSubmenu?

    init(
        kind: ScriptWorkshopBlockKind,
        systemImage: String,
        submenu: ScriptWorkshopWheelSubmenu? = nil
    ) {
        self.kind = kind
        self.systemImage = systemImage
        self.submenu = submenu
    }
}

struct ScriptWorkshopWheelCharacterChoice: Identifiable, Equatable {
    static let addID = "__script_workshop_add_character__"

    var id: String
    var name: String?

    var isAdd: Bool { id == Self.addID }

    static func choices(from names: [String]) -> [Self] {
        names.map { Self(id: "character:\($0.uppercased())", name: $0) }
            + [Self(id: addID, name: nil)]
    }
}

enum ScriptWorkshopWheelRegistry {
    static let primary: [ScriptWorkshopWheelDescriptor] = [
        .init(kind: .action, systemImage: "figure.run"),
        .init(
            kind: .character,
            systemImage: "person.fill",
            submenu: .projectCharacters
        ),
        .init(kind: .dialogue, systemImage: "quote.bubble.fill"),
        .init(kind: .parenthetical, systemImage: "text.bubble"),
        .init(kind: .transition, systemImage: "arrow.right.to.line"),
        .init(kind: .shot, systemImage: "camera.fill"),
        .init(kind: .note, systemImage: "note.text")
    ]
}

struct ScriptWorkshopWheelDirectionalState: Equatable {
    var primaryKind: ScriptWorkshopBlockKind?
    var submenu: ScriptWorkshopWheelSubmenu?
    var secondaryIndex: Int?

    static let empty = Self(primaryKind: nil, submenu: nil, secondaryIndex: nil)
}

enum ScriptWorkshopWheelInteraction {
    static let centerDeadZone: CGFloat = 60
    static let primaryOuterRadius: CGFloat = 154

    /// Resolves an unbounded direction gesture. Radius only distinguishes the
    /// center cancellation zone and whether an already-armed submenu owns the
    /// gesture; it never invalidates a primary selection for being "too far".
    static func resolve(
        dx: CGFloat,
        dy: CGFloat,
        current: ScriptWorkshopWheelDirectionalState,
        secondaryCount: Int
    ) -> ScriptWorkshopWheelDirectionalState {
        let distance = hypot(dx, dy)
        guard distance >= centerDeadZone else { return .empty }

        if current.submenu != nil,
           distance > primaryOuterRadius,
           let index = radialIndex(dx: dx, dy: dy, count: secondaryCount) {
            return .init(
                primaryKind: current.primaryKind,
                submenu: current.submenu,
                secondaryIndex: index
            )
        }

        guard let index = radialIndex(
            dx: dx,
            dy: dy,
            count: ScriptWorkshopWheelRegistry.primary.count
        ) else { return .empty }
        let descriptor = ScriptWorkshopWheelRegistry.primary[index]
        return .init(
            primaryKind: descriptor.kind,
            submenu: descriptor.submenu,
            secondaryIndex: nil
        )
    }

    static func radialIndex(dx: CGFloat, dy: CGFloat, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let step = 2 * Double.pi / Double(count)
        var radians = atan2(Double(dx), Double(-dy))
        if radians < 0 { radians += 2 * .pi }
        return Int(floor((radians + step / 2) / step)) % count
    }
}
