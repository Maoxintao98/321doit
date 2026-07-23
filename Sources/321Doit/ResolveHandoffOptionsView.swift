import SwiftUI

struct ResolveHandoffOptionsView: View {
    @Binding var handoff: HandoffSettings
    var language: AppLanguage
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            Toggle(isOn: $handoff.resolveImportOriginals) {
                Text(L10n.t("导入原始素材", "Import original media", language: language))
                    .font(.system(size: compact ? 12 : 13))
            }
            Toggle(isOn: $handoff.importProxies) {
                Text(L10n.t("链接代理素材", "Link proxy media", language: language))
                    .font(.system(size: compact ? 12 : 13))
            }

            if !compact {
                metadataToggles
            }

            Toggle(isOn: $handoff.resolveApplyClipColors) {
                Text(L10n.t("写入 Resolve 素材颜色", "Apply Resolve clip colors", language: language))
                    .font(.system(size: compact ? 12 : 13))
            }
            Toggle(isOn: $handoff.resolveApplyFlags) {
                Text(L10n.t("写入 Resolve 旗标", "Apply Resolve flags", language: language))
                    .font(.system(size: compact ? 12 : 13))
            }

            mappingHeader
            mappingRow(title: L10n.t("OK 条", "OK takes", language: language), mapping: $handoff.resolveOKMapping)
            mappingRow(title: L10n.t("KP 条", "KP takes", language: language), mapping: $handoff.resolveKPMapping)
            mappingRow(title: L10n.t("NG 条", "NG takes", language: language), mapping: $handoff.resolveNGMapping)
            mappingRow(title: L10n.t("优选条", "Circle takes", language: language), mapping: $handoff.resolveCircleMapping)
        }
    }

    private var metadataToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $handoff.resolveWriteSceneMetadata) {
                Text(L10n.t("写入场号", "Write Scene", language: language))
            }
            Toggle(isOn: $handoff.resolveWriteShotMetadata) {
                Text(L10n.t("写入镜号", "Write Shot", language: language))
            }
            Toggle(isOn: $handoff.resolveWriteTakeMetadata) {
                Text(L10n.t("写入条次", "Write Take", language: language))
            }
            Toggle(isOn: $handoff.resolveWriteCameraMetadata) {
                Text(L10n.t("写入机位", "Write Camera/Angle", language: language))
            }
            Toggle(isOn: $handoff.resolveWriteComments) {
                Text(L10n.t("写入备注", "Write Comments", language: language))
            }
            Toggle(isOn: $handoff.resolveWriteKeywords) {
                Text(L10n.t("写入关键词", "Write Keywords", language: language))
            }
        }
        .font(.system(size: 13))
    }

    private var mappingHeader: some View {
        HStack(spacing: 8) {
            Text(L10n.t("状态", "Status", language: language))
                .frame(width: compact ? 58 : 76, alignment: .leading)
            Text(L10n.t("关键词", "Keyword", language: language))
                .frame(width: compact ? 84 : 120, alignment: .leading)
            Text(L10n.t("素材颜色", "Clip color", language: language))
                .frame(width: compact ? 120 : 150, alignment: .leading)
            Text(L10n.t("旗标", "Flag", language: language))
                .frame(width: compact ? 110 : 140, alignment: .leading)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
    }

    private func mappingRow(title: String, mapping: Binding<ResolveStatusMapping>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .frame(width: compact ? 58 : 76, alignment: .leading)
            TextField(L10n.t("关键词", "Keyword", language: language), text: mapping.keyword)
                .textFieldStyle(.roundedBorder)
                .frame(width: compact ? 84 : 120)
            colorPicker(selection: mapping.clipColor)
                .frame(width: compact ? 120 : 150)
            colorPicker(selection: mapping.flagColor)
                .frame(width: compact ? 110 : 140)
        }
    }

    private func colorPicker(selection: Binding<ResolveClipColor>) -> some View {
        Picker("", selection: selection) {
            ForEach(ResolveClipColor.allCases) { color in
                Text(L10n.t(color.label.0, color.label.1, language: language)).tag(color)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
    }
}
