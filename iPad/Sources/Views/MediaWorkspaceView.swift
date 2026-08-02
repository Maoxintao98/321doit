import SwiftUI
import UniformTypeIdentifiers

struct MediaWorkspaceView: View {
    @EnvironmentObject private var store: ScripterStore
    @State private var section: MediaSection = .offload

    var body: some View {
        VStack(spacing: 0) {
            MediaSectionBar(selection: $section)
            .frame(maxWidth: 560)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            switch section {
            case .offload: OffloadView()
            case .convert: ConversionView()
            case .handoff: HandoffView()
            }
        }
    }
}

private struct MediaSectionBar: View {
    @EnvironmentObject private var store: ScripterStore
    @Binding var selection: MediaSection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MediaSection.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { selection = item }
                } label: {
                    Text(item.title(store.language))
                        .font(.subheadline.weight(selection == item ? .semibold : .regular))
                        .foregroundStyle(selection == item ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                        .background {
                            if selection == item {
                                Capsule()
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                                    .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == item ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemFill), in: Capsule())
    }
}

private enum MediaSection: String, CaseIterable, Identifiable {
    case offload, convert, handoff
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .offload: return L10n.t("安全拷卡", "Safe Offload", language: language)
        case .convert: return L10n.t("媒体转换", "Media Convert", language: language)
        case .handoff: return L10n.t("后期交接", "Post Handoff", language: language)
        }
    }
}

private struct OffloadView: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var media: MediaWorkspaceStore
    @State private var pickSource = false
    @State private var pickPrimary = false
    @State private var pickSecondary = false
    @State private var shareURL: URL?

    private var lang: AppLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("安全拷卡", "Safe Offload", language: lang)).font(.title.bold())
                    Text(L10n.t("选卡、选盘、开始。目录结构保持不变，完成后逐文件 SHA-256 校验。",
                               "Choose the card and drives, then start. Folder structure is preserved and every file is verified with SHA-256.",
                               language: lang))
                        .foregroundStyle(.secondary)
                }

                PickerRow(
                    title: L10n.t("来源卡", "Source card", language: lang),
                    value: media.sourceDirectory?.lastPathComponent,
                    symbol: "sdcard") { pickSource = true }
                PickerRow(
                    title: L10n.t("主备份盘", "Primary drive", language: lang),
                    value: media.primaryDestination?.lastPathComponent,
                    symbol: "externaldrive") { pickPrimary = true }
                PickerRow(
                    title: L10n.t("第二备份盘（可选）", "Second drive (optional)", language: lang),
                    value: media.secondaryDestination?.lastPathComponent,
                    symbol: "externaldrive.badge.plus") { pickSecondary = true }

                if media.isOffloading || !media.offloadStatus.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: media.offloadProgress)
                        Text(media.offloadStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 14))
                }

                HStack {
                    Button {
                        media.startOffload(projectName: store.projectName, language: lang)
                    } label: {
                        Label(L10n.t("开始拷卡", "Start Offload", language: lang), systemImage: "arrow.right")
                            .frame(minWidth: 120)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(media.sourceDirectory == nil || media.primaryDestination == nil || media.isOffloading)

                    if let report = media.lastOffloadReport {
                        Button {
                            shareURL = report
                        } label: {
                            Label(L10n.t("分享报告", "Share Report", language: lang),
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $pickSource, allowedContentTypes: [.folder]) {
            if case .success(let url) = $0 { media.sourceDirectory = url }
        }
        .fileImporter(isPresented: $pickPrimary, allowedContentTypes: [.folder]) {
            if case .success(let url) = $0 { media.primaryDestination = url }
        }
        .fileImporter(isPresented: $pickSecondary, allowedContentTypes: [.folder]) {
            if case .success(let url) = $0 { media.secondaryDestination = url }
        }
        .sheet(item: $shareURL) { ExportSheet(url: $0) }
    }
}

private struct PickerRow: View {
    let title: String
    let value: String?
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    Text(value ?? "—").font(.body.weight(.semibold))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct ConversionView: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var media: MediaWorkspaceStore
    @State private var pickInput = false
    @State private var shareURL: URL?

    private var lang: AppLanguage { store.language }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("媒体转换", "Media Convert", language: lang)).font(.title.bold())
                    Text(L10n.t("iPad 版保留三个最常用动作，不暴露编码器参数。",
                               "The iPad version keeps the three common actions and hides encoder parameters.",
                               language: lang))
                        .foregroundStyle(.secondary)
                }

                PickerRow(
                    title: L10n.t("输入素材", "Input media", language: lang),
                    value: media.conversionInput?.lastPathComponent,
                    symbol: "film") { pickInput = true }

                Picker(L10n.t("输出", "Output", language: lang), selection: $media.conversionPreset) {
                    ForEach(iPadConversionPreset.allCases) { preset in
                        Text(preset.title(lang)).tag(preset)
                    }
                }
                .pickerStyle(.inline)
                .padding(10)
                .background(Color(uiColor: .secondarySystemGroupedBackground),
                            in: RoundedRectangle(cornerRadius: 14))

                if media.isConverting {
                    ProgressView()
                    Text(media.conversionStatus).foregroundStyle(.secondary)
                } else if !media.conversionStatus.isEmpty {
                    Text(media.conversionStatus).foregroundStyle(.secondary)
                }

                HStack {
                    Button {
                        media.startConversion(language: lang)
                    } label: {
                        Label(L10n.t("开始转换", "Convert", language: lang), systemImage: "wand.and.rays")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(media.conversionInput == nil || media.isConverting)

                    if let output = media.conversionOutput {
                        Button {
                            shareURL = output
                        } label: {
                            Label(L10n.t("分享文件", "Share File", language: lang),
                                  systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .fileImporter(isPresented: $pickInput, allowedContentTypes: [.movie, .audio]) {
            if case .success(let url) = $0 { media.conversionInput = url }
        }
        .sheet(item: $shareURL) { ExportSheet(url: $0) }
    }
}

private struct HandoffView: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var production: ProductionStore
    @State private var packageURL: URL?
    @State private var isBuilding = false

    private var lang: AppLanguage { store.language }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "shippingbox")
                .font(.system(size: 46))
                .foregroundStyle(.blue)
            Text(L10n.t("后期交接包", "Post Handoff Package", language: lang))
                .font(.title.bold())
            Text(L10n.t("一次打包场记工程、CSV、通告单与动态分镜。可保存到 Files、外接盘或 AirDrop 给 Mac。",
                       "Bundle the script log, CSV, call sheet and living storyboard. Save to Files, an external drive, or AirDrop to a Mac.",
                       language: lang))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 560)

            Button {
                isBuilding = true
                do {
                    packageURL = try HandoffBuilder.build(store: store, production: production)
                } catch {
                    store.alertMessage = L10n.t("无法生成交接包：\(error.localizedDescription)",
                                                "Could not build handoff package: \(error.localizedDescription)",
                                                language: lang)
                }
                isBuilding = false
            } label: {
                Label(L10n.t("生成并分享", "Build & Share", language: lang),
                      systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBuilding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $packageURL) { ExportSheet(url: $0) }
    }
}

private enum HandoffBuilder {
    @MainActor
    static func build(store: ScripterStore, production: ProductionStore) throws -> URL {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Handoff", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let safeName = store.projectName.replacingOccurrences(of: "/", with: "-")
        let stamp = Int(Date().timeIntervalSince1970)
        let folder = base.appendingPathComponent("\(safeName)-\(stamp)", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        let log = try store.writeExportFile()
        let csv = try store.writeCSVFile()
        try fileManager.copyItem(at: log, to: folder.appendingPathComponent(log.lastPathComponent))
        try fileManager.copyItem(at: csv, to: folder.appendingPathComponent(csv.lastPathComponent))

        let storyboardURL = folder.appendingPathComponent("\(safeName).321storyboard")
        try JSONEncoder.prettyISO.encode(production.storyboard).write(to: storyboardURL, options: .atomic)

        if let day = store.currentDay {
            let html = callSheetHTML(projectName: store.projectName, day: day)
            try Data(html.utf8).write(to: folder.appendingPathComponent("Call-Sheet.html"), options: .atomic)
        }
        return folder
    }

    private static func callSheetHTML(projectName: String, day: ShootingDay) -> String {
        let sheet = day.callSheet
        return """
        <!doctype html><meta charset="utf-8">
        <title>\(escape(projectName)) — \(escape(day.label))</title>
        <style>body{font:16px -apple-system;margin:40px;max-width:760px}h1{margin-bottom:4px}
        .meta{color:#666}table{border-collapse:collapse;width:100%;margin-top:24px}
        td,th{border-bottom:1px solid #ddd;padding:10px;text-align:left}</style>
        <h1>\(escape(projectName))</h1><div class="meta">\(escape(day.label)) · \(escape(sheet.status.rawValue))</div>
        <table>
        <tr><th>Call</th><td>\(escape(sheet.callTime))</td></tr>
        <tr><th>Start</th><td>\(escape(sheet.estimatedStartTime))</td></tr>
        <tr><th>Wrap</th><td>\(escape(sheet.estimatedWrapTime))</td></tr>
        <tr><th>Location</th><td>\(escape(sheet.mainLocation))</td></tr>
        <tr><th>Weather</th><td>\(escape(sheet.weatherNote))</td></tr>
        <tr><th>Notes</th><td>\(escape(sheet.generalNote))</td></tr>
        </table>
        """
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
