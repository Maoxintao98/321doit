import SwiftUI

struct ExportSheet: View {
    @EnvironmentObject private var store: ScripterStore
    @Environment(\.dismiss) private var dismiss
    let url: URL
    private var lang: AppLanguage { store.language }
    private var isCSV: Bool { url.pathExtension.lowercased() == "csv" }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: isCSV ? "tablecells.badge.ellipsis" : "doc.badge.arrow.up")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)
                    .padding(.top, 24)

                Text(L10n.t("场记已导出", "Script Log Exported", language: lang))
                    .font(.title2.bold())

                Text(url.lastPathComponent)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(isCSV
                     ? L10n.t("表格文件，可用 Excel / Numbers 打开；也可隔空投送到 Mac。",
                              "A table file you can open in Excel / Numbers, or AirDrop to your Mac.",
                              language: lang)
                     : L10n.t("用「隔空投送」发送到 Mac，或存到「文件」/ U 盘，再在 Mac 端的 321Doit 里导入。",
                              "AirDrop it to your Mac, or save to Files / a USB drive, then import it in 321Doit on the Mac.",
                              language: lang))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                ShareLink(item: url) {
                    Label(L10n.t("分享 / 隔空投送", "Share / AirDrop", language: lang),
                          systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .padding(.horizontal, 28)

                Spacer()
            }
            .navigationTitle(L10n.t("导出", "Export", language: lang))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.t("完成", "Done", language: lang)) { dismiss() }
                }
            }
        }
    }
}
