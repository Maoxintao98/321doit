import SwiftUI

struct StoryboardWorkflowSyncResult: Equatable {
    var shotCount: Int
    var takeCount: Int
    var mediaCount: Int
}

@MainActor
enum StoryboardWorkflowBridge {
    static func synchronize(
        scene: StoryboardScene,
        to shootingDayID: UUID,
        workflowStore: ScriptLogStore,
        storyboardStore: StoryboardStore,
        language: AppLanguage
    ) -> StoryboardWorkflowSyncResult {
        var links: [StoryboardWorkflowLink] = []
        workflowStore.mutateProject { project in
            guard let dayIndex = project.shootingDays.firstIndex(where: { $0.id == shootingDayID }) else { return }
            let existingScene = project.shootingDays[dayIndex].scenes.first {
                $0.id == scene.id || $0.sceneNumber == scene.sceneNumber
            }
            let synchronizedShots: [Shot] = scene.shots.map { storyboardShot in
                let old = existingScene?.shots.first {
                    $0.id == storyboardShot.id || $0.shotNumber == storyboardShot.shotNumber
                }
                let takes = old?.takes ?? []
                links.append(link(for: storyboardShot.id, shootingDayID: shootingDayID, takes: takes))
                return Shot(
                    id: storyboardShot.id,
                    shotNumber: storyboardShot.shotNumber,
                    cameraSetup: cameraSetup(storyboardShot),
                    takes: takes
                )
            }
            let synchronizedScene = ScriptScene(
                id: scene.id,
                sceneNumber: scene.sceneNumber,
                description: scene.synopsis.isEmpty ? scene.title : scene.synopsis,
                shots: synchronizedShots
            )
            if let index = project.shootingDays[dayIndex].scenes.firstIndex(where: {
                $0.id == scene.id || $0.sceneNumber == scene.sceneNumber
            }) {
                project.shootingDays[dayIndex].scenes[index] = synchronizedScene
            } else {
                project.shootingDays[dayIndex].scenes.append(synchronizedScene)
            }

            var plans = project.shootingDays[dayIndex].callSheet.scenePlans
            let oldPlans = plans.filter { $0.sceneID == scene.id || $0.sceneNumber == scene.sceneNumber }
            plans.removeAll { $0.sceneID == scene.id || $0.sceneNumber == scene.sceneNumber }
            for shot in scene.shots {
                let old = oldPlans.first { $0.shotNumber == shot.shotNumber }
                plans.append(DayScenePlan(
                    id: old?.id ?? UUID(),
                    sceneID: scene.id,
                    sceneNumber: scene.sceneNumber,
                    shotNumber: shot.shotNumber,
                    dayNight: scene.timeOfDay,
                    interiorExterior: scene.interiorExterior?.rawValue ?? "",
                    location: scene.location,
                    summary: StoryboardMarkdownRendering.plainText(from: shot.description),
                    cast: shot.characters.map(\.name),
                    cameraUnits: [cameraSetup(shot)],
                    estimatedPages: old?.estimatedPages ?? "",
                    isMustShoot: old?.isMustShoot ?? true,
                    isCompleted: old?.isCompleted ?? false,
                    note: productionNote(shot)
                ))
            }
            project.shootingDays[dayIndex].callSheet.scenePlans = plans
            project.shootingDays[dayIndex].callSheet.updatedAt = Date()
        }

        var production = storyboardStore.document.production ?? StoryboardProductionData()
        let shotIDs = Set(scene.shots.map(\.id))
        production.workflowLinks.removeAll { shotIDs.contains($0.shotID) }
        production.workflowLinks.append(contentsOf: links)
        _ = storyboardStore.perform(title: L10n.t("同步至拍摄日与场记", "Sync to Production Planning and Script Log", language: language), mutations: [.updateProduction(production)])
        return result(from: links)
    }

    static func refreshAssociations(
        scene: StoryboardScene,
        workflowStore: ScriptLogStore,
        storyboardStore: StoryboardStore,
        language: AppLanguage
    ) -> StoryboardWorkflowSyncResult {
        var refreshed: [StoryboardWorkflowLink] = []
        for day in workflowStore.project.shootingDays {
            guard let logScene = day.scenes.first(where: { $0.id == scene.id || $0.sceneNumber == scene.sceneNumber }) else { continue }
            for shot in scene.shots {
                if let logged = logScene.shots.first(where: { $0.id == shot.id || $0.shotNumber == shot.shotNumber }) {
                    refreshed.append(link(for: shot.id, shootingDayID: day.id, takes: logged.takes))
                }
            }
        }
        var production = storyboardStore.document.production ?? StoryboardProductionData()
        let shotIDs = Set(scene.shots.map(\.id))
        production.workflowLinks.removeAll { shotIDs.contains($0.shotID) }
        production.workflowLinks.append(contentsOf: refreshed)
        _ = storyboardStore.perform(title: L10n.t("刷新场记与素材关联", "Refresh Script Log and Media Links", language: language), mutations: [.updateProduction(production)])
        return result(from: refreshed)
    }

    private static func link(for shotID: UUID, shootingDayID: UUID, takes: [Take]) -> StoryboardWorkflowLink {
        let media = takes.flatMap { take in
            take.linkedClips.flatMap { clip in [clip.filePath, clip.proxyPath] }
        }.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let best = takes.first(where: { $0.isCircleTake })?.id
            ?? takes.first(where: { $0.status == .good })?.id
        return StoryboardWorkflowLink(
            shotID: shotID,
            scriptLogShotID: shotID,
            shootingDayID: shootingDayID,
            takeIDs: takes.map(\.id),
            mediaPaths: Array(Set(media)).sorted(),
            bestTakeID: best
        )
    }

    private static func result(from links: [StoryboardWorkflowLink]) -> StoryboardWorkflowSyncResult {
        StoryboardWorkflowSyncResult(
            shotCount: links.count,
            takeCount: links.reduce(0) { $0 + $1.takeIDs.count },
            mediaCount: links.reduce(0) { $0 + $1.mediaPaths.count }
        )
    }

    private static func cameraSetup(_ shot: StoryboardShot) -> String {
        let motion = shot.cameraMotions.first?.kind.rawValue ?? StoryboardCameraMotionKind.locked.rawValue
        let lens = shot.lens.trimmingCharacters(in: .whitespacesAndNewlines)
        return lens.isEmpty ? motion : "\(lens) · \(motion)"
    }

    private static func productionNote(_ shot: StoryboardShot) -> String {
        [shot.directorIntent, shot.specialEquipment?.joined(separator: " / "), shot.soundDescription]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "；")
    }
}

struct StoryboardWorkflowView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themeColors) private var colors
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var storyboardStore: StoryboardStore
    @ObservedObject var workflowStore: ScriptLogStore
    let scene: StoryboardScene

    @State private var selectedDayID: UUID?
    @State private var result: StoryboardWorkflowSyncResult?

    private var lang: AppLanguage { settings.settings.general.language.resolved }
    private func t(_ zh: String, _ en: String) -> String { L10n.t(zh, en, language: lang) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("片场工作流 · 场 \(scene.sceneNumber)", "Production Workflow · Scene \(scene.sceneNumber)")).font(.system(size: 16, weight: .semibold))
                    Text(t("分镜 → 拍摄统筹 → 迅捷场记 → 极速拷卡 → 反向关联素材", "Storyboard → Production Planning → Script Log → Turbo Offload → Linked Media"))
                        .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20).frame(height: 70)
            Divider()

            VStack(alignment: .leading, spacing: 18) {
                if storyboardStore.document.linkedProjectID == nil {
                    Label(t("当前是独立分镜；在工具箱选择“关联项目”后才能同步片场数据。", "This storyboard is independent. Select ‘Use a Project’ in the tool hub before syncing production data."), systemImage: "link.badge.plus")
                        .foregroundStyle(Color.orange)
                } else {
                    Picker(t("目标拍摄日", "Target Shooting Day"), selection: $selectedDayID) {
                        Text(t("请选择", "Select a day")).tag(UUID?.none)
                        ForEach(workflowStore.project.shootingDays) { day in
                            Text(day.label.isEmpty ? day.date.formatted(date: .abbreviated, time: .omitted) : day.label)
                                .tag(UUID?.some(day.id))
                        }
                    }
                    .frame(maxWidth: 420)

                    HStack(spacing: 12) {
                        Button {
                            guard let dayID = selectedDayID else { return }
                            result = StoryboardWorkflowBridge.synchronize(
                                scene: scene,
                                to: dayID,
                                workflowStore: workflowStore,
                                storyboardStore: storyboardStore,
                                language: lang
                            )
                        } label: {
                            Label(t("同步镜头到拍摄日与场记", "Sync Shots to Planning and Script Log"), systemImage: "arrowshape.right.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedDayID == nil)

                        Button {
                            result = StoryboardWorkflowBridge.refreshAssociations(
                                scene: scene,
                                workflowStore: workflowStore,
                                storyboardStore: storyboardStore,
                                language: lang
                            )
                        } label: {
                            Label(t("拉取 Take 与素材", "Refresh Takes and Media"), systemImage: "arrow.clockwise")
                        }
                    }

                    if let result {
                        HStack(spacing: 12) {
                            metric(t("关联镜头", "Linked Shots"), result.shotCount)
                            metric("Take", result.takeCount)
                            metric(t("素材文件", "Media Files"), result.mediaCount)
                        }
                    }

                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(scene.shots) { shot in
                                let link = storyboardStore.document.production?.workflowLinks.first { $0.shotID == shot.id }
                                HStack {
                                    Text(shot.shotNumber).font(.system(size: 11, weight: .bold, design: .monospaced)).frame(width: 70, alignment: .leading)
                                    Text(StoryboardMarkdownRendering.attributedString(from: shot.description)).font(.system(size: 10)).lineLimit(1)
                                    Spacer()
                                    Label("\(link?.takeIDs.count ?? 0) Take", systemImage: "record.circle")
                                    Label(t("\(link?.mediaPaths.count ?? 0) 素材", "\(link?.mediaPaths.count ?? 0) Media"), systemImage: "externaldrive")
                                    if link?.bestTakeID != nil { Image(systemName: "star.circle.fill").foregroundStyle(Color.green) }
                                }
                                .padding(11)
                                .background(colors.panelBg)
                                .clipShape(RoundedRectangle(cornerRadius: 9))
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(20)

            Divider()
            HStack {
                Text(t("同步保留既有 Take；以镜头 UUID 为主键，镜号仅作兼容匹配。", "Sync preserves existing takes and uses shot UUIDs as the primary key; shot numbers are used only for compatibility matching."))
                    .font(.system(size: 10)).foregroundStyle(colors.textSecondary)
                Spacer()
                Button(t("完成", "Done")) { dismiss() }.buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20).frame(height: 58)
        }
        .frame(width: 820, height: 610)
        .onAppear { selectedDayID = workflowStore.project.shootingDays.first?.id }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8)).foregroundStyle(colors.textSecondary)
            Text("\(value)").font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
        .padding(11).frame(minWidth: 100, alignment: .leading)
        .background(colors.inputBg).clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
