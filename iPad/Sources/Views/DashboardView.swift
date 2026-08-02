import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: ScripterStore
    @EnvironmentObject private var production: ProductionStore
    let navigate: (MainTab) -> Void

    private var lang: AppLanguage { store.language }
    private var day: ShootingDay? { store.currentDay ?? store.days.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.t("今天要做什么？", "What are we doing today?", language: lang))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(day?.label ?? L10n.t("尚未建立拍摄日", "No shooting day yet", language: lang))
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                    DashboardCard(
                        title: L10n.t("拍摄计划", "Shooting Plan", language: lang),
                        value: day?.callSheet.callTime.isEmpty == false
                            ? day!.callSheet.callTime
                            : L10n.t("补充集合时间", "Add call time", language: lang),
                        detail: day?.callSheet.mainLocation.isEmpty == false
                            ? day!.callSheet.mainLocation
                            : L10n.t("地点尚未填写", "Location not set", language: lang),
                        symbol: "calendar",
                        tint: .blue) { navigate(.schedule) }

                    DashboardCard(
                        title: L10n.t("现场场记", "Script Log", language: lang),
                        value: "\(store.totalTakeCount) Takes",
                        detail: L10n.t("\(store.completedTakeCount) 条可用 / 圈选",
                                       "\(store.completedTakeCount) usable / circled",
                                       language: lang),
                        symbol: "list.bullet.clipboard",
                        tint: .orange) { navigate(.scriptLog) }

                    DashboardCard(
                        title: L10n.t("动态分镜", "Living Storyboard", language: lang),
                        value: L10n.t("\(production.shotCount) 个镜头",
                                       "\(production.shotCount) shots",
                                       language: lang),
                        detail: L10n.t("查看、创作与现场批注", "Review, create and annotate", language: lang),
                        symbol: "rectangle.3.group",
                        tint: .purple) { navigate(.storyboard) }

                    DashboardCard(
                        title: L10n.t("媒体工作台", "Media Workspace", language: lang),
                        value: L10n.t("拷卡与转换", "Offload & Convert", language: lang),
                        detail: L10n.t("外接盘、校验、代理与交接", "Drives, verify, proxy and handoff", language: lang),
                        symbol: "externaldrive",
                        tint: .green) { navigate(.media) }
                }

                if let day {
                    TodayStrip(day: day)
                }
            }
            .padding(24)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
    }
}

private struct DashboardCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    Text(value).font(.title3.bold()).lineLimit(1)
                    Text(detail).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            .padding(18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

private struct TodayStrip: View {
    @EnvironmentObject private var store: ScripterStore
    let day: ShootingDay

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("今日概览", "Today at a glance", language: store.language))
                .font(.headline)
            HStack(spacing: 30) {
                metric(L10n.t("场次", "Scenes", language: store.language), "\(day.scenes.count)")
                metric(L10n.t("地点", "Location", language: store.language),
                       day.callSheet.mainLocation.isEmpty ? "—" : day.callSheet.mainLocation)
                metric(L10n.t("预计开机", "Start", language: store.language),
                       day.callSheet.estimatedStartTime.isEmpty ? "—" : day.callSheet.estimatedStartTime)
                metric(L10n.t("预计收工", "Wrap", language: store.language),
                       day.callSheet.estimatedWrapTime.isEmpty ? "—" : day.callSheet.estimatedWrapTime)
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
