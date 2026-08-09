import AppKit
import SwiftUI

enum ToolIdentifier: String, Hashable, Identifiable {
    case scriptWorkshop
    case storyboard
    case offload
    case scriptLog
    case shootingDay
    case mediaConverter

    var id: String { rawValue }
}

enum ToolAssociationMode: String, Hashable {
    case independent
    case linkedProject
}

struct ToolDescriptor: Identifiable {
    let id: ToolIdentifier
    let title: (String, String)
    let subtitle: (String, String)
    let detail: (String, String)
    let systemImage: String
    let accent: ToolAccent
}

enum ToolRegistry {
    static let builtIn: [ToolDescriptor] = [
        ToolDescriptor(
            id: .scriptWorkshop,
            title: ("剧本工坊", "Script Workshop"),
            subtitle: ("落笔成戏，场场可拍", "From page to production"),
            detail: ("从故事结构到专业剧本，让人物、场景与制作数据自然流向分镜和片场", "Develop structured screenplays whose characters, scenes, and production data flow directly into storyboards and the set."),
            systemImage: "text.document",
            accent: .scriptWorkshop
        ),
        ToolDescriptor(
            id: .storyboard,
            title: ("灵动分镜", "Living Storyboard"),
            subtitle: ("所想即所见，所画即所拍", "From intent to frame"),
            detail: ("把脑海里的画面，变成现场真正拍得出来的镜头方案", "Turn the film in your head into shots the crew can actually make."),
            systemImage: "rectangle.on.rectangle.angled",
            accent: .storyboard
        ),
        ToolDescriptor(
            id: .offload,
            title: ("极速拷卡", "Turbo Offload"),
            subtitle: ("迅如闪电，坚如磐石", "Lightning fast. Rock solid."),
            detail: ("一次下盘，多重校验，让每份素材安全抵达后期", "Offload once, verify every copy, and send footage safely into post."),
            systemImage: "externaldrive.badge.checkmark",
            accent: .offload
        ),
        ToolDescriptor(
            id: .scriptLog,
            title: ("迅捷场记", "Rapid Script Log"),
            subtitle: ("指尖速记，一键导入", "Fast at your fingertips. One-click import."),
            detail: ("现场少打字、少漏记，收工后直接把清楚的记录交给后期", "Log faster on set and hand post a clean, complete record at wrap."),
            systemImage: "list.clipboard",
            accent: .scriptLog
        ),
        ToolDescriptor(
            id: .shootingDay,
            title: ("拍摄统筹", "Production Planning"),
            subtitle: ("计划周全，现场从容", "Plan thoroughly. Work calmly."),
            detail: ("把人、景、日程和通告排到一起，让现场按计划开拍", "Bring crew, locations, schedules, and call sheets into one shoot-ready plan."),
            systemImage: "calendar.badge.clock",
            accent: .shootingDay
        ),
        ToolDescriptor(
            id: .mediaConverter,
            title: ("媒体转换", "Media Conversion"),
            subtitle: ("瞬息转换，不损品质", "Instant conversion. Quality preserved."),
            detail: ("换封装、转码、核验一次完成，交付不再被格式卡住", "Rewrap, transcode, and verify in one pass—without format headaches at delivery."),
            systemImage: "arrow.triangle.2.circlepath",
            accent: .mediaConverter
        )
    ]

    static func descriptor(for id: ToolIdentifier) -> ToolDescriptor {
        builtIn.first { $0.id == id }!
    }
}

