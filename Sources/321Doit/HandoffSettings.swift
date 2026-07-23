import Foundation

// MARK: - Handoff (Post-handoff package for DaVinci Resolve / Final Cut Pro)

enum HandoffTarget: String, Codable, CaseIterable, Identifiable {
    case none
    case resolve
    case finalCut
    case both

    var id: String { rawValue }

    var label: (String, String) {
        switch self {
        case .none:     return ("不生成", "Disabled")
        case .resolve:  return ("DaVinci Resolve", "DaVinci Resolve")
        case .finalCut: return ("Final Cut Pro", "Final Cut Pro")
        case .both:     return ("DaVinci Resolve + Final Cut Pro", "DaVinci Resolve + Final Cut Pro")
        }
    }

    var includesResolve: Bool { self == .resolve || self == .both }
    var includesFinalCut: Bool { self == .finalCut || self == .both }
}

enum HandoffFrameRate: String, Codable, CaseIterable, Identifiable {
    case fps23_976
    case fps24
    case fps25
    case fps29_97
    case fps30
    case fps50
    case fps59_94
    case fps60

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fps23_976: return "23.976"
        case .fps24:     return "24"
        case .fps25:     return "25"
        case .fps29_97:  return "29.97"
        case .fps30:     return "30"
        case .fps50:     return "50"
        case .fps59_94:  return "59.94"
        case .fps60:     return "60"
        }
    }

    /// fps = numerator / denominator. FCPXML frameDuration is denominator/numerator seconds.
    var rational: (numerator: Int64, denominator: Int64) {
        switch self {
        case .fps23_976: return (24000, 1001)
        case .fps24:     return (24, 1)
        case .fps25:     return (25, 1)
        case .fps29_97:  return (30000, 1001)
        case .fps30:     return (30, 1)
        case .fps50:     return (50, 1)
        case .fps59_94:  return (60000, 1001)
        case .fps60:     return (60, 1)
        }
    }

    var isDropFrame: Bool {
        false
    }
}

enum HandoffResolution: String, Codable, CaseIterable, Identifiable {
    case hd720
    case hd1080
    case uhd2160
    case dci4k

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hd720:    return "1280×720"
        case .hd1080:   return "1920×1080"
        case .uhd2160:  return "3840×2160"
        case .dci4k:    return "4096×2160 (DCI 4K)"
        }
    }

    var size: (width: Int, height: Int) {
        switch self {
        case .hd720:    return (1280, 720)
        case .hd1080:   return (1920, 1080)
        case .uhd2160:  return (3840, 2160)
        case .dci4k:    return (4096, 2160)
        }
    }
}

enum HandoffColorMode: String, Codable, CaseIterable, Identifiable {
    case rec709
    case rec2020
    case davinciWideGamutIntermediate
    case acescct

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rec709:                       return "Rec.709 / sRGB"
        case .rec2020:                      return "Rec.2020"
        case .davinciWideGamutIntermediate: return "DaVinci Wide Gamut Intermediate"
        case .acescct:                      return "ACEScct"
        }
    }
}

enum ResolveClipColor: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case orange = "Orange"
    case apricot = "Apricot"
    case yellow = "Yellow"
    case lime = "Lime"
    case green = "Green"
    case teal = "Teal"
    case navy = "Navy"
    case blue = "Blue"
    case purple = "Purple"
    case violet = "Violet"
    case pink = "Pink"
    case tan = "Tan"
    case beige = "Beige"
    case brown = "Brown"
    case chocolate = "Chocolate"
    case red = "Red"

    var id: String { rawValue }

    var resolveValue: String? {
        self == .none ? nil : rawValue
    }

    var label: (String, String) {
        switch self {
        case .none: return ("不设置", "None")
        case .orange: return ("橙色", "Orange")
        case .apricot: return ("杏色", "Apricot")
        case .yellow: return ("黄色", "Yellow")
        case .lime: return ("青柠", "Lime")
        case .green: return ("绿色", "Green")
        case .teal: return ("蓝绿", "Teal")
        case .navy: return ("藏蓝", "Navy")
        case .blue: return ("蓝色", "Blue")
        case .purple: return ("紫色", "Purple")
        case .violet: return ("紫罗兰", "Violet")
        case .pink: return ("粉色", "Pink")
        case .tan: return ("棕褐", "Tan")
        case .beige: return ("米色", "Beige")
        case .brown: return ("棕色", "Brown")
        case .chocolate: return ("巧克力", "Chocolate")
        case .red: return ("红色", "Red")
        }
    }
}

struct ResolveStatusMapping: Codable, Equatable {
    var keyword: String
    var clipColor: ResolveClipColor
    var flagColor: ResolveClipColor

    init(keyword: String, clipColor: ResolveClipColor, flagColor: ResolveClipColor = .none) {
        self.keyword = keyword
        self.clipColor = clipColor
        self.flagColor = flagColor
    }
}

struct HandoffSettings: Codable, Equatable {
    var target: HandoffTarget = .none
    var projectName: String = ""
    var shootDay: String = ""
    var shootDate: String = ""
    var frameRate: HandoffFrameRate = .fps25
    var resolution: HandoffResolution = .hd1080
    var startTimecode: String = "01:00:00:00"
    var colorMode: HandoffColorMode = .rec709
    var generateStarterTimeline: Bool = false
    var importProxies: Bool = true
    var importLUT: Bool = false
    var generateImportScripts: Bool = true
    var autoOpenAfterHandoff: Bool = false
    var injectScriptLogMetadata: Bool = true
    var resolveImportOriginals: Bool = true
    var resolveWriteSceneMetadata: Bool = true
    var resolveWriteShotMetadata: Bool = true
    var resolveWriteTakeMetadata: Bool = true
    var resolveWriteCameraMetadata: Bool = true
    var resolveWriteComments: Bool = true
    var resolveWriteKeywords: Bool = true
    var resolveApplyClipColors: Bool = true
    var resolveApplyFlags: Bool = false
    var resolveOKMapping: ResolveStatusMapping = .init(keyword: "OK", clipColor: .green, flagColor: .green)
    var resolveKPMapping: ResolveStatusMapping = .init(keyword: "KP", clipColor: .yellow, flagColor: .yellow)
    var resolveNGMapping: ResolveStatusMapping = .init(keyword: "NG", clipColor: .red, flagColor: .red)
    var resolveCircleMapping: ResolveStatusMapping = .init(keyword: "Circle Take", clipColor: .green, flagColor: .green)

    init() {}

    private enum CodingKeys: String, CodingKey {
        case target, projectName, shootDay, shootDate
        case frameRate, resolution, startTimecode, colorMode
        case generateStarterTimeline, importProxies, importLUT
        case generateImportScripts, autoOpenAfterHandoff, injectScriptLogMetadata
        case resolveImportOriginals
        case resolveWriteSceneMetadata, resolveWriteShotMetadata, resolveWriteTakeMetadata
        case resolveWriteCameraMetadata, resolveWriteComments, resolveWriteKeywords
        case resolveApplyClipColors, resolveApplyFlags
        case resolveOKMapping, resolveKPMapping, resolveNGMapping, resolveCircleMapping
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(HandoffTarget.self, forKey: .target) ?? .none
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName) ?? ""
        shootDay = try c.decodeIfPresent(String.self, forKey: .shootDay) ?? ""
        shootDate = try c.decodeIfPresent(String.self, forKey: .shootDate) ?? ""
        frameRate = try c.decodeIfPresent(HandoffFrameRate.self, forKey: .frameRate) ?? .fps25
        resolution = try c.decodeIfPresent(HandoffResolution.self, forKey: .resolution) ?? .hd1080
        startTimecode = try c.decodeIfPresent(String.self, forKey: .startTimecode) ?? "01:00:00:00"
        colorMode = try c.decodeIfPresent(HandoffColorMode.self, forKey: .colorMode) ?? .rec709
        generateStarterTimeline = try c.decodeIfPresent(Bool.self, forKey: .generateStarterTimeline) ?? false
        importProxies = try c.decodeIfPresent(Bool.self, forKey: .importProxies) ?? true
        importLUT = try c.decodeIfPresent(Bool.self, forKey: .importLUT) ?? false
        generateImportScripts = try c.decodeIfPresent(Bool.self, forKey: .generateImportScripts) ?? true
        autoOpenAfterHandoff = try c.decodeIfPresent(Bool.self, forKey: .autoOpenAfterHandoff) ?? false
        injectScriptLogMetadata = try c.decodeIfPresent(Bool.self, forKey: .injectScriptLogMetadata) ?? true
        resolveImportOriginals = try c.decodeIfPresent(Bool.self, forKey: .resolveImportOriginals) ?? true
        resolveWriteSceneMetadata = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteSceneMetadata) ?? true
        resolveWriteShotMetadata = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteShotMetadata) ?? true
        resolveWriteTakeMetadata = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteTakeMetadata) ?? true
        resolveWriteCameraMetadata = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteCameraMetadata) ?? true
        resolveWriteComments = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteComments) ?? true
        resolveWriteKeywords = try c.decodeIfPresent(Bool.self, forKey: .resolveWriteKeywords) ?? true
        resolveApplyClipColors = try c.decodeIfPresent(Bool.self, forKey: .resolveApplyClipColors) ?? true
        resolveApplyFlags = try c.decodeIfPresent(Bool.self, forKey: .resolveApplyFlags) ?? false
        resolveOKMapping = try c.decodeIfPresent(ResolveStatusMapping.self, forKey: .resolveOKMapping) ?? .init(keyword: "OK", clipColor: .green, flagColor: .green)
        resolveKPMapping = try c.decodeIfPresent(ResolveStatusMapping.self, forKey: .resolveKPMapping) ?? .init(keyword: "KP", clipColor: .yellow, flagColor: .yellow)
        resolveNGMapping = try c.decodeIfPresent(ResolveStatusMapping.self, forKey: .resolveNGMapping) ?? .init(keyword: "NG", clipColor: .red, flagColor: .red)
        resolveCircleMapping = try c.decodeIfPresent(ResolveStatusMapping.self, forKey: .resolveCircleMapping) ?? .init(keyword: "Circle Take", clipColor: .green, flagColor: .green)
    }
}
