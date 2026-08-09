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
    static let moreIDPrefix = "__script_workshop_more_characters__"
    static let maximumVisibleCount = 9
    static let pagedChoiceCount = maximumVisibleCount - 1

    var id: String
    var name: String?
    var destinationPage: Int? = nil

    var isAdd: Bool { id == Self.addID }
    var isMore: Bool { destinationPage != nil }

    static func choices(from names: [String]) -> [Self] {
        names.map { Self(id: "character:\($0.uppercased())", name: $0) }
            + [Self(id: addID, name: nil)]
    }

    /// Every character ring is capped at nine sectors.  When more choices
    /// remain, the ninth sector becomes a stable breadcrumb into the next
    /// concentric ring instead of squeezing unreadable names into this one.
    static func pages(from choices: [Self]) -> [[Self]] {
        guard !choices.isEmpty else { return [[]] }
        var result: [[Self]] = []
        var start = 0
        while start < choices.count {
            let remaining = choices.count - start
            if remaining <= maximumVisibleCount {
                result.append(Array(choices[start...]))
                break
            }
            let nextPage = result.count + 1
            var page = Array(choices[start..<(start + pagedChoiceCount)])
            page.append(Self(
                id: "\(moreIDPrefix):\(nextPage)",
                name: nil,
                destinationPage: nextPage
            ))
            result.append(page)
            start += pagedChoiceCount
        }
        return result
    }
}

enum ScriptWorkshopWheelKeyboardInput: Equatable {
    case digit(Int)
    case up
    case right
    case down
    case left
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
    static let overlaySize: CGFloat = 500
    static let overlayPadding: CGFloat = 8
    static let renderedDiameterScale: CGFloat = 0.94
    static let characterRingStartRatio: CGFloat = 0.67
    static let characterRingSpanRatio: CGFloat = 0.31
    static let characterRingGapRatio: CGFloat = 0.012
    static let centerDeadZone: CGFloat = 60
    static let primaryOuterRadius: CGFloat = 154

    static var renderedRadius: CGFloat {
        (overlaySize - overlayPadding * 2) * renderedDiameterScale / 2
    }

    static func characterRingRatios(
        pageIndex: Int,
        visiblePageCount: Int
    ) -> (inner: CGFloat, outer: CGFloat) {
        let ringSpan = characterRingSpanRatio / CGFloat(max(visiblePageCount, 1))
        let inner = characterRingStartRatio + CGFloat(pageIndex) * ringSpan
        let outer = characterRingStartRatio + CGFloat(pageIndex + 1) * ringSpan
            - characterRingGapRatio
        return (inner, outer)
    }

    static func characterRingInnerRadius(
        pageIndex: Int,
        visiblePageCount: Int
    ) -> CGFloat {
        characterRingRatios(
            pageIndex: pageIndex,
            visiblePageCount: visiblePageCount
        ).inner * renderedRadius
    }

    /// Resolves an unbounded direction gesture. Radius only distinguishes the
    /// center cancellation zone and whether an already-armed submenu owns the
    /// gesture; it never invalidates a primary selection for being "too far".
    static func resolve(
        dx: CGFloat,
        dy: CGFloat,
        current: ScriptWorkshopWheelDirectionalState,
        secondaryCount: Int,
        secondaryInnerRadius: CGFloat = primaryOuterRadius
    ) -> ScriptWorkshopWheelDirectionalState {
        let distance = hypot(dx, dy)
        guard distance >= centerDeadZone else { return .empty }

        if current.submenu != nil,
           distance >= secondaryInnerRadius,
           let index = radialIndex(dx: dx, dy: dy, count: secondaryCount) {
            return .init(
                primaryKind: current.primaryKind,
                submenu: current.submenu,
                secondaryIndex: index
            )
        }

        if current.submenu != nil, distance > primaryOuterRadius {
            return .init(
                primaryKind: current.primaryKind,
                submenu: current.submenu,
                secondaryIndex: nil
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

    /// Keyboard choices use the same top-at-one, clockwise geometry as the
    /// rendered wheel. Number keys address sectors directly; arrow keys pick
    /// the sector nearest their cardinal direction.
    static func keyboardIndex(
        for input: ScriptWorkshopWheelKeyboardInput,
        count: Int
    ) -> Int? {
        guard count > 0 else { return nil }
        switch input {
        case .digit(let value):
            let index = value - 1
            return (0..<min(count, 9)).contains(index) ? index : nil
        case .up:
            return radialIndex(dx: 0, dy: -1, count: count)
        case .right:
            return radialIndex(dx: 1, dy: 0, count: count)
        case .down:
            return radialIndex(dx: 0, dy: 1, count: count)
        case .left:
            return radialIndex(dx: -1, dy: 0, count: count)
        }
    }
}
