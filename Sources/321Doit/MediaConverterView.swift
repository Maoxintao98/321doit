import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MediaConverterView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @StateObject private var store = MediaConversionStore()
    @State private var expandedItemIDs: Set<UUID> = []
    @State private var dependenciesAvailable = false

    let associationMode: ToolAssociationMode
    let projectID: UUID?
    let projectName: String?
    let projectFolderURL: URL?
    let configuredFFmpegPath: String

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private var accent: Color { colors.toolAccent(.mediaConverter) }
    private var targetOptions: [MediaContainer] {
        switch store.mode {
        case .rewrap:
            return [.mp4, .mov, .mkv, .webm, .avi, .mpegts, .mxf]
        case .transcode:
            return store.transcodeSettings.videoCodec.supportedContainers
        case .losslessAudio:
            return [.wav, .aiff, .flac, .m4a]
        }
    }
    private var projectContext: ToolProjectContext? {
        guard associationMode == .linkedProject, let projectID, let projectName else { return nil }
        return ToolProjectContext(projectID: projectID, projectName: projectName, projectFolderURL: projectFolderURL)
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                commandBar
                Divider().overlay(colors.hairline)
                if proxy.size.width >= 1040 {
                    desktopWorkspace
                } else {
                    compactWorkspace
                }
                executionBar
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surfaceBg)
        .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: handleDrop)
        .suppressAutomaticFocusEffect()
        .onAppear {
            refreshDependencyStatus()
            normalizeTarget()
            store.reanalyze(language: lang, configuredFFmpegPath: configuredFFmpegPath)
        }
        .onChange(of: store.mode) { _ in refreshRecipe() }
        .onChange(of: store.target) { _ in refreshRecipe() }
        .onChange(of: store.transcodeSettings) { _ in refreshRecipe() }
        .onChange(of: lang) { _ in
            store.reanalyze(language: lang, configuredFFmpegPath: configuredFFmpegPath)
        }
    }

    // MARK: - Workspace shell

    private var commandBar: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(accent)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: accent.opacity(0.22), radius: 10, y: 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("媒体转换工作台", "Media Conversion Studio", language: lang))
                    .font(.system(size: 15, weight: .bold))
                Text(L10n.t("转封装 · 视频转码 · 无损音频", "Rewrap · Transcode · Lossless audio", language: lang))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(colors.textSecondary)
            }

            engineStatus
            Spacer(minLength: 12)
            associationBadge
            actionButton(L10n.t("添加文件夹", "Add Folder", language: lang), icon: "folder.badge.plus") {
                chooseInputs(directories: true)
            }
            .accessibilityIdentifier("mediaConverter.addFolder")
            actionButton(L10n.t("添加素材", "Add Media", language: lang), icon: "plus", prominent: true) {
                chooseInputs(directories: false)
            }
            .accessibilityIdentifier("mediaConverter.addMedia")
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
        .background(colors.panelBg)
    }

    private var desktopWorkspace: some View {
        HStack(spacing: 0) {
            sourceColumn
                .frame(minWidth: 330, idealWidth: 380, maxWidth: 430)
            Divider().overlay(colors.hairline)
            recipeColumn
                .frame(minWidth: 420, maxWidth: .infinity)
            Divider().overlay(colors.hairline)
            inspectorColumn
                .frame(minWidth: 280, idealWidth: 310, maxWidth: 350)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var compactWorkspace: some View {
        ScrollView {
            VStack(spacing: 14) {
                sourceColumn.frame(minHeight: 300)
                recipeColumn
                inspectorColumn
            }
            .padding(14)
        }
    }

    // MARK: - Source queue

    private var sourceColumn: some View {
        VStack(spacing: 0) {
            sectionHeader(
                title: L10n.t("输入素材", "Source Media", language: lang),
                detail: L10n.t("\(store.items.count) 个文件", "\(store.items.count) files", language: lang),
                icon: "film.stack"
            ) {
                if !store.items.isEmpty {
                    miniButton(icon: "line.3.horizontal.decrease", help: L10n.t("清理已结束", "Clear finished", language: lang)) {
                        store.clearFinished()
                    }
                }
            }

            if store.items.isEmpty {
                emptyDropZone
                    .padding(16)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(store.items) { item in
                            queueRow(item)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(colors.surfaceBg)
    }

    private var emptyDropZone: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(accent.opacity(0.12))
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(accent)
            }
            .frame(width: 58, height: 58)
            Text(L10n.t("把素材拖到这里", "Drop media here", language: lang))
                .font(.system(size: 13, weight: .semibold))
            Text(L10n.t("或从访达选择文件与文件夹", "or choose files and folders from Finder", language: lang))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
            actionButton(L10n.t("选择素材", "Choose Media", language: lang), icon: "plus", prominent: true) {
                chooseInputs(directories: false)
            }
            .accessibilityIdentifier("mediaConverter.chooseMedia")
        }
        .frame(maxWidth: .infinity, minHeight: 210)
        .background(colors.panelBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        }
    }

    private func queueRow(_ item: MediaConversionQueueItem) -> some View {
        let isExpanded = expandedItemIDs.contains(item.id)
        let canExpand = item.probed != nil
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(stateColor(item.state).opacity(0.12))
                    Image(systemName: stateIcon(item.state))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(stateColor(item.state))
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.sourceURL.lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        if canExpand {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(colors.textTertiary)
                        }
                    }
                    if let probed = item.probed {
                        Text(MediaInfoSummary(media: probed, lang: lang).compactLine)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(2)
                    }
                    Text(stateText(item.state))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(stateColor(item.state))
                    if item.state == .converting || item.state == .verifying {
                        ProgressView(value: item.progress.fraction)
                            .tint(accent)
                            .scaleEffect(x: 1, y: 0.75)
                    }
                }
                Spacer(minLength: 4)
                if let output = item.outputURL {
                    miniButton(icon: "magnifyingglass", help: L10n.t("在访达中显示", "Reveal in Finder", language: lang)) {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                }
                if item.state == .failed, item.probed == nil, !store.isRunning {
                    miniButton(icon: "arrow.clockwise", help: L10n.t("重新分析", "Retry analysis", language: lang)) {
                        store.retryAnalysis(item.id, language: lang, configuredFFmpegPath: configuredFFmpegPath)
                    }
                }
                if !store.isRunning {
                    miniButton(icon: "xmark", help: L10n.t("移除", "Remove", language: lang)) {
                        store.remove(item.id)
                    }
                }
            }
            if let compatibility = item.compatibility {
                compatibilityOutcome(compatibility)
            } else if let error = item.errorText {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(item.state == .failed ? colors.stateFail : colors.stateWarning)
            }
            if isExpanded, let probed = item.probed {
                MediaInfoExpandedCard(media: probed, lang: lang)
            }
        }
        .padding(12)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 13))
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .onTapGesture {
            guard canExpand else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                if isExpanded { expandedItemIDs.remove(item.id) }
                else { expandedItemIDs.insert(item.id) }
            }
        }
    }

    // MARK: - Recipe

    private var recipeColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.t("转换配方", "Conversion Recipe", language: lang))
                        .font(.system(size: 22, weight: .bold))
                    Text(L10n.t("先决定是否重编码，再选择容器与编码。", "Choose the operation first, then the container and codecs.", language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }

                modeSelector
                recipeCard(title: L10n.t("输出格式", "Output Format", language: lang), icon: "shippingbox") {
                    optionLabel(L10n.t("容器", "Container", language: lang), detail: L10n.t("决定文件扩展名与可承载的媒体流", "Defines the file extension and stream support", language: lang))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(targetOptions) { target in
                            choiceButton(
                                title: target.displayName(language: lang),
                                subtitle: ".\(target.fileExtension)",
                                selected: store.target == target
                            ) { store.target = target }
                        }
                    }
                }

                if store.mode == .transcode {
                    transcodeRecipe
                } else {
                    passiveRecipeSummary
                }

                destinationCard
            }
            .padding(22)
        }
        .background(colors.surfaceBg)
    }

    private var modeSelector: some View {
        HStack(spacing: 9) {
            ForEach(MediaConversionMode.allCases) { mode in
                Button { store.mode = mode } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Image(systemName: modeIcon(mode))
                                .font(.system(size: 13, weight: .semibold))
                            Spacer()
                            if store.mode == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        Text(mode.displayName(language: lang))
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Text(modeDescription(mode))
                            .font(.system(size: 9))
                            .foregroundStyle(store.mode == mode ? Color.white.opacity(0.78) : colors.textSecondary)
                            .lineLimit(2)
                    }
                    .foregroundStyle(store.mode == mode ? Color.white : colors.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
                    .background(store.mode == mode ? accent : colors.panelBg)
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(store.isRunning)
            }
        }
    }

    private var transcodeRecipe: some View {
        VStack(spacing: 14) {
            recipeCard(title: L10n.t("视频编码", "Video Codec", language: lang), icon: "film") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(MediaVideoCodec.allCases) { codec in
                        choiceButton(
                            title: codec.displayName,
                            subtitle: videoCodecDetail(codec),
                            selected: store.transcodeSettings.videoCodec == codec
                        ) {
                            store.transcodeSettings.videoCodec = codec
                        }
                    }
                }
            }

            recipeCard(title: L10n.t("编码参数", "Encoding Parameters", language: lang), icon: "slider.horizontal.3") {
                parameterRow(
                    title: L10n.t("画质", "Quality", language: lang),
                    detail: store.transcodeSettings.quality.displayName(language: lang)
                ) {
                    ForEach(MediaTranscodeQuality.allCases) { quality in
                        Button(quality.displayName(language: lang)) { store.transcodeSettings.quality = quality }
                    }
                }
                Divider().overlay(colors.hairline)
                parameterRow(
                    title: L10n.t("分辨率", "Resolution", language: lang),
                    detail: store.transcodeSettings.scale.displayName(language: lang)
                ) {
                    ForEach(MediaOutputScale.allCases) { scale in
                        Button(scale.displayName(language: lang)) { store.transcodeSettings.scale = scale }
                    }
                }
                Divider().overlay(colors.hairline)
                parameterRow(
                    title: L10n.t("帧率", "Frame Rate", language: lang),
                    detail: store.transcodeSettings.frameRate.displayName(language: lang)
                ) {
                    ForEach(MediaOutputFrameRate.allCases) { frameRate in
                        Button(frameRate.displayName(language: lang)) { store.transcodeSettings.frameRate = frameRate }
                    }
                }
                Divider().overlay(colors.hairline)
                parameterRow(
                    title: L10n.t("音频", "Audio", language: lang),
                    detail: store.transcodeSettings.audioCodec.displayName(language: lang)
                ) {
                    ForEach(MediaAudioCodec.allCases) { codec in
                        Button(codec.displayName(language: lang)) { store.transcodeSettings.audioCodec = codec }
                    }
                }
            }
        }
    }

    private var passiveRecipeSummary: some View {
        recipeCard(
            title: store.mode == .rewrap
                ? L10n.t("原流直通", "Stream Copy", language: lang)
                : L10n.t("无损音频", "Lossless Audio", language: lang),
            icon: store.mode == .rewrap ? "equal.circle" : "waveform"
        ) {
            HStack(spacing: 12) {
                summaryPill(
                    title: L10n.t("视频", "Video", language: lang),
                    value: store.mode == .rewrap ? L10n.t("不重编码", "Copied", language: lang) : L10n.t("不输出", "Omitted", language: lang),
                    icon: "film"
                )
                summaryPill(
                    title: L10n.t("音频", "Audio", language: lang),
                    value: store.mode == .rewrap ? L10n.t("不重编码", "Copied", language: lang) : L10n.t("可逆转换", "Lossless", language: lang),
                    icon: "waveform"
                )
            }
            Text(store.mode == .rewrap
                 ? L10n.t("速度最快，只改变容器；画面和声音的压缩数据保持不变。", "Fastest option. Only the container changes; compressed picture and sound stay untouched.", language: lang)
                 : L10n.t("提取第一条音频流并转换为 PCM、FLAC 或 ALAC，不进行重采样。", "Extracts the first audio stream to PCM, FLAC, or ALAC without resampling.", language: lang))
                .font(.system(size: 10))
                .foregroundStyle(colors.textSecondary)
        }
    }

    private var destinationCard: some View {
        recipeCard(title: L10n.t("保存位置", "Destination", language: lang), icon: "folder") {
            Button { chooseDestination() } label: {
                HStack(spacing: 11) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.destinationURL?.lastPathComponent ?? L10n.t("选择输出文件夹", "Choose output folder", language: lang))
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.destinationURL?.path ?? L10n.t("默认使用第一个素材所在目录", "Defaults to the first source folder", language: lang))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(colors.textTertiary)
                }
                .padding(12)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityIdentifier("mediaConverter.destination")
        }
    }

    // MARK: - Inspector

    private var inspectorColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: L10n.t("输出检查", "Output Inspector", language: lang),
                    detail: nil,
                    icon: "checkmark.shield"
                ) { EmptyView() }

                routeCard
                preflightCard
                safetyCard
            }
            .padding(14)
        }
        .background(colors.surfaceBg)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(L10n.t("转换路径", "Conversion Route", language: lang))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.sectionHeader)
            routeNode(
                icon: "film",
                title: sourceRouteTitle,
                detail: L10n.t("输入保持只读", "Source remains read-only", language: lang),
                emphasized: false
            )
            HStack {
                Rectangle().fill(colors.hairline).frame(width: 1, height: 18)
            }
            .padding(.leading, 17)
            routeNode(
                icon: modeIcon(store.mode),
                title: store.mode.displayName(language: lang),
                detail: operationSummary,
                emphasized: true
            )
            HStack {
                Rectangle().fill(colors.hairline).frame(width: 1, height: 18)
            }
            .padding(.leading, 17)
            routeNode(
                icon: "doc.fill",
                title: store.target.displayName(language: lang),
                detail: outputRouteDetail,
                emphasized: false
            )
        }
        .padding(14)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var preflightCard: some View {
        let blocked = store.items.filter { $0.compatibility?.verdict == .incompatible }.count
        let warned = store.items.filter { $0.compatibility?.verdict == .compatibleWithWarnings }.count
        let risks = store.items.compactMap(\.compatibility).flatMap(\.risks)
        return VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("转换前预检", "Preflight", language: lang))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.sectionHeader)
            HStack(spacing: 8) {
                metricTile(L10n.t("可执行", "Ready", language: lang), value: store.runnableCount, color: colors.stateSuccess)
                metricTile(L10n.t("提醒", "Warn", language: lang), value: warned, color: colors.stateWarning)
                metricTile(L10n.t("阻断", "Block", language: lang), value: blocked, color: colors.stateFail)
            }
            if risks.isEmpty {
                Label(
                    store.items.isEmpty
                        ? L10n.t("添加素材后自动分析", "Add media to analyze", language: lang)
                        : L10n.t("未发现兼容性风险", "No compatibility risks", language: lang),
                    systemImage: store.items.isEmpty ? "info.circle" : "checkmark.circle.fill"
                )
                .font(.system(size: 10))
                .foregroundStyle(store.items.isEmpty ? colors.textSecondary : colors.stateSuccess)
            } else {
                ForEach(Array(risks.prefix(5).enumerated()), id: \.offset) { _, risk in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: risk.severity == .blocking ? "xmark.octagon.fill" : (risk.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"))
                            .foregroundStyle(risk.severity == .blocking ? colors.stateFail : (risk.severity == .warning ? colors.stateWarning : colors.textTertiary))
                        Text(risk.message(language: lang))
                            .font(.system(size: 9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var safetyCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(L10n.t("安全输出", "Safe Output", language: lang), systemImage: "lock.shield.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(colors.stateSuccess)
            Text(L10n.t("先写入隐藏临时文件，验证通过后再落盘；不覆盖原素材，重名自动编号。", "Writes a hidden temporary file first, publishes only after verification, never overwrites the source, and auto-numbers conflicts.", language: lang))
                .font(.system(size: 9))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(colors.stateSuccess.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Execution

    private var executionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: dependenciesAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(dependenciesAvailable ? colors.stateSuccess : colors.stateWarning)
            VStack(alignment: .leading, spacing: 2) {
                Text(dependenciesAvailable
                     ? L10n.t("本机转换引擎已就绪", "Local conversion engine ready", language: lang)
                     : L10n.t("缺少 FFmpeg / FFprobe", "FFmpeg / FFprobe missing", language: lang))
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.t("素材不会上传", "Media never leaves this Mac", language: lang))
                    .font(.system(size: 9))
                    .foregroundStyle(colors.textSecondary)
            }
            Spacer()
            Text(L10n.t("\(store.runnableCount) 项可执行", "\(store.runnableCount) ready", language: lang))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(colors.textSecondary)
            if store.isRunning {
                actionButton(L10n.t("停止转换", "Stop", language: lang), icon: "stop.fill") { store.cancelCurrent() }
                    .accessibilityIdentifier("mediaConverter.stop")
            } else {
                actionButton(L10n.t("开始转换", "Start Conversion", language: lang), icon: "play.fill", prominent: true) {
                    store.run(language: lang, configuredFFmpegPath: configuredFFmpegPath, projectContext: projectContext)
                }
                .disabled(!dependenciesAvailable || store.destinationURL == nil || store.runnableCount == 0)
                .opacity((!dependenciesAvailable || store.destinationURL == nil || store.runnableCount == 0) ? 0.45 : 1)
                .accessibilityIdentifier("mediaConverter.start")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 64)
        .background(colors.panelBg)
        .overlay(alignment: .top) { Divider().overlay(colors.hairline) }
    }

    // MARK: - Reusable views

    private var engineStatus: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dependenciesAvailable ? colors.stateSuccess : colors.stateWarning)
                .frame(width: 6, height: 6)
            Text(dependenciesAvailable ? L10n.t("引擎就绪", "Engine Ready", language: lang) : L10n.t("需要配置", "Setup Required", language: lang))
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(colors.inputBg)
        .clipShape(Capsule())
    }

    private var associationBadge: some View {
        Label(
            associationMode == .linkedProject ? (projectName ?? L10n.t("关联项目", "Linked Project", language: lang)) : L10n.t("独立模式", "Independent", language: lang),
            systemImage: associationMode == .linkedProject ? "link" : "square.dashed"
        )
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(colors.textSecondary)
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        detail: String?,
        icon: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 9)).foregroundStyle(colors.textSecondary)
                }
            }
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func recipeCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(colors.sectionHeader)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.panelBg)
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private func optionLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10, weight: .semibold))
            Text(detail).font(.system(size: 9)).foregroundStyle(colors.textSecondary)
        }
    }

    private func choiceButton(title: String, subtitle: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    Text(subtitle).font(.system(size: 8, design: .monospaced)).opacity(0.72).lineLimit(1)
                }
                Spacer(minLength: 2)
                if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
            }
            .foregroundStyle(selected ? Color.white : colors.textPrimary)
            .padding(.horizontal, 11)
            .frame(minHeight: 48)
            .background(selected ? accent : colors.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(store.isRunning)
    }

    private func parameterRow<MenuContent: View>(
        title: String,
        detail: String,
        @ViewBuilder menuContent: () -> MenuContent
    ) -> some View {
        HStack {
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer()
            Menu {
                menuContent()
            } label: {
                HStack(spacing: 6) {
                    Text(detail).font(.system(size: 10, weight: .semibold))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(colors.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .focusable(false)
            .disabled(store.isRunning)
        }
    }

    private func summaryPill(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 8)).foregroundStyle(colors.textSecondary)
                Text(value).font(.system(size: 10, weight: .semibold))
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func routeNode(icon: String, title: String, detail: String, emphasized: Bool) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(emphasized ? accent : colors.inputBg)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(emphasized ? Color.white : colors.textSecondary)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 8)).foregroundStyle(colors.textSecondary).lineLimit(2)
            }
        }
    }

    private func metricTile(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.system(size: 17, weight: .bold, design: .monospaced)).foregroundStyle(color)
            Text(title).font(.system(size: 8)).foregroundStyle(colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }

    private func actionButton(_ title: String, icon: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(prominent ? accent : colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func miniButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 25, height: 25)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .foregroundStyle(colors.textSecondary)
        .help(help)
    }

    // MARK: - Labels and behavior

    private var sourceRouteTitle: String {
        guard let media = store.items.first?.probed else {
            return L10n.t("等待素材", "Waiting for source", language: lang)
        }
        return MediaInfoSummary(media: media, lang: lang).compactLine
    }

    private var operationSummary: String {
        switch store.mode {
        case .rewrap: return L10n.t("视频与音频原流直通", "Picture and sound stream copy", language: lang)
        case .transcode:
            return "\(store.transcodeSettings.videoCodec.shortName) · \(store.transcodeSettings.quality.displayName(language: lang))"
        case .losslessAudio: return L10n.t("可逆音频编码，不重采样", "Reversible audio coding, no resampling", language: lang)
        }
    }

    private var outputRouteDetail: String {
        switch store.mode {
        case .transcode:
            return "\(store.transcodeSettings.scale.displayName(language: lang)) · \(store.transcodeSettings.frameRate.displayName(language: lang))"
        case .rewrap: return L10n.t("只改变容器", "Container only", language: lang)
        case .losslessAudio: return L10n.t("仅输出音频", "Audio only", language: lang)
        }
    }

    private func modeIcon(_ mode: MediaConversionMode) -> String {
        switch mode {
        case .rewrap: return "shippingbox"
        case .transcode: return "dial.high"
        case .losslessAudio: return "waveform"
        }
    }

    private func modeDescription(_ mode: MediaConversionMode) -> String {
        switch mode {
        case .rewrap: return L10n.t("最快，不改变画质", "Fastest, no quality change", language: lang)
        case .transcode: return L10n.t("改变编码、画幅或帧率", "Change codec, size, or frame rate", language: lang)
        case .losslessAudio: return L10n.t("提取并无损转换声音", "Extract and lossless-convert audio", language: lang)
        }
    }

    private func videoCodecDetail(_ codec: MediaVideoCodec) -> String {
        switch codec {
        case .h264: return L10n.t("通用交付 · 兼容性最佳", "Universal delivery", language: lang)
        case .h265: return L10n.t("更小体积 · 10-bit", "Smaller files · 10-bit", language: lang)
        case .prores422: return L10n.t("剪辑中间码", "Editing intermediate", language: lang)
        case .prores422HQ: return L10n.t("高质量母版", "High-quality master", language: lang)
        case .av1: return L10n.t("新一代网络交付", "Next-gen delivery", language: lang)
        case .vp9: return L10n.t("WebM 网络交付", "WebM delivery", language: lang)
        case .mpeg2: return L10n.t("广播与传统交付", "Broadcast delivery", language: lang)
        case .dnxhrHQX: return L10n.t("Avid 高质量中间码", "Avid high-quality intermediate", language: lang)
        }
    }

    private func refreshRecipe(normalize: Bool = true) {
        if normalize { normalizeTarget() }
        store.reanalyze(language: lang, configuredFFmpegPath: configuredFFmpegPath)
    }

    private func refreshDependencyStatus() {
        let configuredPath = configuredFFmpegPath
        let language = lang
        Task {
            let available = await Task.detached(priority: .utility) {
                FFmpegLocator.executableURL(configuredPath: configuredPath) != nil
                    && MediaProbeService(language: language).isAvailable(configuredFFmpegPath: configuredPath)
            }.value
            dependenciesAvailable = available
        }
    }

    private func normalizeTarget() {
        if !targetOptions.contains(store.target), let first = targetOptions.first {
            store.target = first
        }
        if store.mode == .transcode {
            switch store.target {
            case .webm:
                store.transcodeSettings.audioCodec = .opus
            case .mxf:
                store.transcodeSettings.audioCodec = .pcm
            case .mp4, .mpegts:
                if store.transcodeSettings.audioCodec == .pcm || store.transcodeSettings.audioCodec == .opus {
                    store.transcodeSettings.audioCodec = .aac
                }
            default:
                if store.transcodeSettings.audioCodec == .opus, store.target != .mkv {
                    store.transcodeSettings.audioCodec = .aac
                }
            }
        }
    }

    private func stateText(_ state: MediaConversionTaskState) -> String {
        switch state {
        case .waiting: return L10n.t("等待分析", "Waiting", language: lang)
        case .analyzing: return L10n.t("正在读取媒体信息", "Reading media info", language: lang)
        case .ready: return L10n.t("可执行", "Ready", language: lang)
        case .converting: return L10n.t("转换中", "Converting", language: lang)
        case .verifying: return L10n.t("输出复核中", "Verifying output", language: lang)
        case .completed: return L10n.t("转换完成", "Completed", language: lang)
        case .warning: return L10n.t("可执行 · 有提醒", "Ready with warning", language: lang)
        case .failed: return L10n.t("当前配方不可执行", "Recipe blocked", language: lang)
        case .cancelled: return L10n.t("已取消", "Cancelled", language: lang)
        case .interrupted: return L10n.t("已中断", "Interrupted", language: lang)
        }
    }

    @ViewBuilder
    private func compatibilityOutcome(_ result: CompatibilityResult) -> some View {
        if let blocking = result.risks.first(where: { $0.severity == .blocking }) {
            Label(blocking.message(language: lang), systemImage: "xmark.octagon.fill")
                .font(.system(size: 9))
                .foregroundStyle(colors.stateFail)
                .fixedSize(horizontal: false, vertical: true)
        } else if let warning = result.risks.first(where: { $0.severity == .warning }) {
            Label(warning.message(language: lang), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 9))
                .foregroundStyle(colors.stateWarning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stateIcon(_ state: MediaConversionTaskState) -> String {
        switch state {
        case .completed: return "checkmark"
        case .failed: return "xmark"
        case .warning: return "exclamationmark"
        case .converting, .verifying, .analyzing: return "arrow.triangle.2.circlepath"
        case .cancelled, .interrupted: return "pause.fill"
        default: return "film"
        }
    }

    private func stateColor(_ state: MediaConversionTaskState) -> Color {
        switch state {
        case .completed, .ready: return colors.stateSuccess
        case .failed: return colors.stateFail
        case .warning: return colors.stateWarning
        case .converting, .verifying, .analyzing: return accent
        default: return colors.textTertiary
        }
    }

    private func chooseInputs(directories: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.canCreateDirectories = false
        if panel.runModal() == .OK {
            store.add(urls: panel.urls, language: lang, configuredFFmpegPath: configuredFFmpegPath)
        }
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { store.destinationURL = panel.url }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                guard let data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    store.add(urls: [url], language: lang, configuredFFmpegPath: configuredFFmpegPath)
                }
            }
        }
        return accepted
    }
}
