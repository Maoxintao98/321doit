import SwiftUI

struct WorkspaceSwitcher: View {
    @Binding var selection: Workspace
    let language: AppLanguage
    @Environment(\.themeColors) private var colors

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Workspace.allCases) { workspace in
                Button {
                    selection = workspace
                } label: {
                    Label(workspace.title(language: language), systemImage: workspace.systemImage)
                        .font(.system(size: 11, weight: selection == workspace ? .semibold : .medium))
                        .labelStyle(.titleAndIcon)
                        .frame(minWidth: 84)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selection == workspace ? colors.accent.opacity(0.18) : Color.clear)
                .foregroundStyle(selection == workspace ? colors.textPrimary : colors.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(selection == workspace ? colors.accent.opacity(0.55) : colors.hairline.opacity(0.8), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .fixedSize(horizontal: true, vertical: false)
                .help(workspace.subtitle(language: language))
            }
        }
        .padding(3)
        .background(colors.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
