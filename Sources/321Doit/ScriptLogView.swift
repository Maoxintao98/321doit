import SwiftUI

struct ScriptLogView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    @State private var inspectorTab: ScriptInspectorTab = .notes

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                ScriptLogSidebar(store: store)
                    .frame(minWidth: 250, idealWidth: 285, maxWidth: 340)
                TakeEditorView(store: store)
                    .frame(minWidth: 620)
                if store.isInspectorVisible {
                    ScriptLogInspector(store: store, tab: $inspectorTab)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                }
            }
        }
        .background(colors.surfaceBg)
    }
}

private enum ScriptInspectorTab: String, CaseIterable, Identifiable {
    case notes
    case clips
    case export

    var id: String { rawValue }

    func title(lang: AppLanguage) -> String {
        switch self {
        case .notes: return L10n.t("备注", "Notes", language: lang)
        case .clips: return L10n.t("素材", "Clips", language: lang)
        case .export: return L10n.t("导出", "Export", language: lang)
        }
    }
}

private struct ScriptLogInspector: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @ObservedObject var store: ScriptLogStore
    @Binding var tab: ScriptInspectorTab

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.t("检查器", "Inspector", language: lang))
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            Picker("", selection: $tab) {
                ForEach(ScriptInspectorTab.allCases) { item in
                    Text(item.title(lang: lang)).tag(item)
                }
            }
            .pickerStyle(.segmented)

            Divider()

            switch tab {
            case .notes:
                notesTab
            case .clips:
                LinkedClipsView(store: store)
            case .export:
                exportTab
            }
        }
        .padding(14)
        .background(colors.panelBg)
    }

    private var notesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inspectorNote(L10n.t("通用备注", "General Note", language: lang), text: Binding(
                    get: { store.currentTake?.generalNote ?? "" },
                    set: { value in store.updateCurrentTake { $0.generalNote = value } }
                ), height: 120)
                inspectorNote(L10n.t("表演备注", "Performance Note", language: lang), text: Binding(
                    get: { store.currentTake?.performanceNote ?? "" },
                    set: { value in store.updateCurrentTake { $0.performanceNote = value } }
                ))
                inspectorNote(L10n.t("技术备注", "Technical Note", language: lang), text: Binding(
                    get: { store.currentTake?.technicalNote ?? "" },
                    set: { value in store.updateCurrentTake { $0.technicalNote = value } }
                ))
            }
        }
    }

    @State private var exportFormat: ExportFormat = .csv

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case json = "JSON"
        case pdf = "PDF"
        var id: String { rawValue }
    }

    private var exportTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.t("场记导出", "Export Script Log", language: lang))
                .font(.system(size: 12, weight: .semibold))
            Text(L10n.t("CSV / JSON 为完整导出；PDF 当前为 MVP 摘要版。", "CSV / JSON export all data; PDF is an MVP summary.", language: lang))
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker(L10n.t("导出格式", "Format", language: lang), selection: $exportFormat) {
                ForEach(ExportFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .pickerStyle(.radioGroup)

            Button {
                switch exportFormat {
                case .csv: store.exportCSV()
                case .json: store.exportJSON()
                case .pdf: store.exportPDFPlaceholder()
                }
            } label: {
                Label(L10n.t("导出", "Export", language: lang), systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            if let url = store.lastExportURL {
                Divider()
                Text(L10n.t("最近导出", "Last Export", language: lang))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                Text(url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textSecondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            Spacer()
        }
    }

    private func inspectorNote(_ title: String, text: Binding<String>, height: CGFloat = 88) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colors.textSecondary)
            TextEditor(text: text)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(minHeight: height)
                .background(colors.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}
