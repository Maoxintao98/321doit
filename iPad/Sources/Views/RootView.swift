import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case project, scriptLog
    var id: String { rawValue }
    func title(_ lang: AppLanguage) -> String {
        switch self {
        case .project:   return L10n.t("项目", "Project", language: lang)
        case .scriptLog: return L10n.t("场记", "Script Log", language: lang)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: ScripterStore
    @State private var tab: MainTab = .scriptLog
    private var lang: AppLanguage { store.language }

    var body: some View {
        ZStack {
            // Single app-wide background. Everything sits on top of this, so the
            // top strip can never show a different-colored system bar/band.
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom top switcher (replaces the system TabView bar that was
                // painting the white band under the status bar).
                Picker("", selection: $tab) {
                    ForEach(MainTab.allCases) { t in
                        Text(t.title(lang)).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 280)
                .padding(.top, 6)
                .padding(.bottom, 8)

                Group {
                    switch tab {
                    case .project:   ProjectPanel()
                    case .scriptLog: ScriptLogPage()
                    }
                }
            }
        }
        .alert(item: Binding(
            get: { store.alertMessage.map { AlertText(text: $0) } },
            set: { _ in store.alertMessage = nil }
        )) { a in
            Alert(title: Text(a.text))
        }
    }
}

/// The script-log page: the three-column day / scene-shot / take editor.
struct ScriptLogPage: View {
    @EnvironmentObject private var store: ScripterStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showExport = false
    @State private var exportURL: URL?

    private var lang: AppLanguage { store.language }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DaySidebar()
                .navigationTitle(L10n.t("拍摄日", "Shooting Days", language: lang))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { sidebarToolbar }
        } content: {
            Group {
                if store.currentDay != nil {
                    SceneShotColumn()
                } else {
                    ContentUnavailableView(
                        L10n.t("请选择拍摄日", "Select a Shooting Day", language: lang),
                        systemImage: "calendar")
                }
            }
        } detail: {
            Group {
                if store.currentTake != nil {
                    TakeEditorColumn()
                } else {
                    ContentUnavailableView(
                        L10n.t("选择或新建一条 Take", "Select or add a Take", language: lang),
                        systemImage: "film")
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(Color(uiColor: .systemGroupedBackground))
        .scrollContentBackground(.hidden)
        .sheet(isPresented: $showExport) {
            if let url = exportURL { ExportSheet(url: url) }
        }
    }

    @ToolbarContentBuilder
    private var sidebarToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.undo()
            } label: {
                Label(L10n.t("撤销", "Undo", language: lang), systemImage: "arrow.uturn.backward")
            }
            .disabled(!store.canUndo)

            Menu {
                Button {
                    export(.csv)
                } label: {
                    Label(L10n.t("导出表格 (CSV)", "Export Table (CSV)", language: lang),
                          systemImage: "tablecells")
                }
                Button {
                    export(.log)
                } label: {
                    Label(L10n.t("导出工程文件 (.321log)", "Export Project (.321log)", language: lang),
                          systemImage: "doc.badge.gearshape")
                }
            } label: {
                Label(L10n.t("导出", "Export", language: lang), systemImage: "square.and.arrow.up")
            }

            Button {
                store.addDay()
            } label: {
                Label(L10n.t("新建拍摄日", "Add Day", language: lang), systemImage: "calendar.badge.plus")
            }
        }
    }

    private enum ExportKind { case csv, log }

    private func export(_ kind: ExportKind) {
        do {
            switch kind {
            case .csv: exportURL = try store.writeCSVFile()
            case .log: exportURL = try store.writeExportFile()
            }
            showExport = true
        } catch {
            store.alertMessage = L10n.t("导出失败：\(error.localizedDescription)",
                                        "Export failed: \(error.localizedDescription)", language: lang)
        }
    }
}

struct AlertText: Identifiable {
    let id = UUID()
    let text: String
}
