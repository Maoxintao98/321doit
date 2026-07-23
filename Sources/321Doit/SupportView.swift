import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AboutPanelView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 14) {
                AppLogo(size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("321Doit")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Version \(UpdateSettings.appVersion) (\(UpdateSettings.buildNumber))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(colors.textSecondary)
                    Text(L10n.t(UpdateSettings.licenseBlurb.0, UpdateSettings.licenseBlurb.1, language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
            }

            Text(L10n.t("321Doit 是一款免费、开源、本地优先的 macOS 影视制作全能工作站，包含灵动分镜、拍摄统筹、迅捷场记、极速拷卡和媒体转换。欢迎通过反馈、测试、建议或赞助参与长期开发。",
                        "321Doit is a free, open-source, local-first filmmaking workstation for macOS, with Living Storyboard, Production Planning, Rapid Script Log, Turbo Offload, and Media Conversion. Feedback, testing, suggestions, and sponsorship all help its long-term development.",
                        language: lang))
                .font(.system(size: 12))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                NotificationCenter.default.post(name: AppMenuCommand.contactSupport.notificationName, object: nil)
            } label: {
                Label(L10n.t("支持 321Doit 继续开发", "Support 321Doit Development", language: lang), systemImage: "heart")
            }
            .controlSize(.regular)
            .buttonStyle(.borderless)
            .focusable(false)

            HStack(spacing: 8) {
                Button(L10n.t("项目主页", "Project Home", language: lang)) {
                    openURL(UpdateSettings.githubURL)
                }
                Button(L10n.t("开源许可", "License", language: lang)) {
                    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("LICENSE")
                    NSWorkspace.shared.open(url)
                }
                Button(L10n.t("开源鸣谢", "Acknowledgements", language: lang)) {
                    openURL("\(UpdateSettings.githubURL)/blob/main/THIRD_PARTY_NOTICES.md")
                }
                Button(L10n.t("报告问题", "Report Issue", language: lang)) {
                    openURL(UpdateSettings.issueURL)
                }
            }
            .buttonStyle(.borderless)
            .focusable(false)

            Spacer()

            Text("© 2024-2026 · MIT")
                .font(.system(size: 10))
                .foregroundStyle(colors.textTertiary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(26)
        .frame(width: 520, height: 430)
        .background(colors.surfaceBg)
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SupportView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss
    @State private var isPaymentQRCodePresented = false
    @State private var diagnosticMessage: String?

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                AppLogo(size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.t("联系与支持", "Contact & Support", language: lang))
                        .font(.system(size: 22, weight: .semibold))
                    Text(L10n.t("片场工作流交流、反馈与项目支持入口。",
                                "A focused place for workflow questions, feedback, and project support.",
                                language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .contentShape(Rectangle())
                    .help(L10n.t("关闭", "Close", language: lang))
                    .onTapGesture {
                        dismiss()
                    }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    supportSection(
                        title: L10n.t("联系作者", "Contact the Author", language: lang),
                        text: L10n.t("用于片场工作流交流、Bug 反馈、商业合作、定制需求。",
                                     "For set workflow discussion, bug reports, commercial collaboration, and custom needs.",
                                     language: lang)
                    ) {
                        supportButton(L10n.t("发送邮件", "Send Email", language: lang), systemImage: "envelope") {
                            openMail(subject: "321Doit")
                        }
                        supportButton(L10n.t("复制邮箱", "Copy Email", language: lang), systemImage: "doc.on.doc") {
                            copy(UpdateSettings.supportEmail)
                        }
                        supportButton(L10n.t("复制微信 / 电话", "Copy WeChat / Phone", language: lang), systemImage: "phone") {
                            copy(UpdateSettings.supportWeChat)
                        }
                    }

                    supportSection(
                        title: L10n.t("支持开发", "Support Development", language: lang),
                        text: L10n.t("321Doit 会保持免费和开源。赞助会用于开发时间、测试设备、存储介质、签名发布成本，以及 Final Cut Pro / DaVinci Resolve 工作流适配。",
                                     "321Doit will remain free and open source. Sponsorship helps cover development time, test hardware, storage media, signing and release costs, and Final Cut Pro / DaVinci Resolve workflow adaptation.",
                                     language: lang)
                    ) {
                        supportButton(L10n.t("一次性支持", "One-Time Support", language: lang), systemImage: "heart") {
                            isPaymentQRCodePresented = true
                        }
                        supportButton(L10n.t("长期赞助", "Long-Term Sponsorship", language: lang), systemImage: "heart.circle") {
                            isPaymentQRCodePresented = true
                        }
                    }

                    supportSection(
                        title: L10n.t("商业合作 / 定制工作流", "Commercial Collaboration / Custom Workflows", language: lang),
                        text: L10n.t("如果你是剧组、工作室、学校或影像机构，需要部署、培训、定制工作流或技术支持，可以联系作者。",
                                     "If you are a production, studio, school, or imaging organization that needs deployment, training, custom workflows, or technical support, contact the author.",
                                     language: lang)
                    ) {
                        supportButton(L10n.t("商业合作", "Business Inquiry", language: lang), systemImage: "briefcase") {
                            openMail(subject: "321Doit Business Inquiry")
                        }
                    }

                    supportSection(
                        title: L10n.t("参与项目", "Contribute to the Project", language: lang),
                        text: L10n.t("欢迎通过 GitHub 查看源码、报告问题或提交建议。",
                                     "You can review the source, report issues, or submit suggestions through GitHub.",
                                     language: lang)
                    ) {
                        supportButton(L10n.t("GitHub 项目", "GitHub Project", language: lang), systemImage: "link") {
                            openURL(UpdateSettings.githubURL)
                        }
                        supportButton(L10n.t("报告问题", "Report an Issue", language: lang), systemImage: "exclamationmark.bubble") {
                            openURL(UpdateSettings.issueURL)
                        }
                        supportButton(L10n.t("提交建议", "Submit a Suggestion", language: lang), systemImage: "lightbulb") {
                            openURL("\(UpdateSettings.issueURL)/new")
                        }
                        supportButton(L10n.t("复制诊断信息", "Copy Diagnostics", language: lang), systemImage: "stethoscope") {
                            copy(diagnostics)
                        }
                        if settings.settings.logs.allowDiagnosticsExport {
                            supportButton(L10n.t("导出诊断包", "Export Diagnostic Bundle", language: lang), systemImage: "archivebox") {
                                exportDiagnosticBundle()
                            }
                        }
                    }

                    if let diagnosticMessage {
                        Text(diagnosticMessage)
                            .font(.system(size: 10))
                            .foregroundStyle(colors.textSecondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 720, height: 680)
        .background(colors.surfaceBg)
        .sheet(isPresented: $isPaymentQRCodePresented) {
            PaymentQRCodeView()
                .environmentObject(settings)
                .environment(\.appTheme, settings.settings.general.theme)
                .tint(colors.accent)
        }
    }

    private func supportSection<Buttons: View>(title: String, text: String, @ViewBuilder buttons: () -> Buttons) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if title == L10n.t("联系作者", "Contact the Author", language: lang) {
                Text("\(UpdateSettings.supportEmail) · WeChat \(UpdateSettings.supportWeChat)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.textTertiary)
            }
            HStack(spacing: 8) {
                buttons()
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlassSurface(colors: colors, cornerRadius: 14)
    }

    private func supportButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .controlSize(.small)
        .buttonStyle(.borderless)
    }

    private func openMail(subject: String) {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = UpdateSettings.supportEmail
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func exportDiagnosticBundle() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.zip]
        panel.nameFieldStringValue = "321Doit-Diagnostics-\(UpdateSettings.appVersion)-build\(UpdateSettings.buildNumber).zip"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try DiagnosticBundleExporter.export(to: destination, settings: settings.settings)
            diagnosticMessage = L10n.t(
                "诊断包已导出：\(destination.path)",
                "Diagnostic bundle exported: \(destination.path)",
                language: lang
            )
            NSWorkspace.shared.activateFileViewerSelecting([destination])
        } catch {
            AppLogger.log(.error, category: "diagnostics", "Diagnostic export failed: \(error.localizedDescription)")
            diagnosticMessage = L10n.t(
                "诊断包导出失败：\(error.localizedDescription)",
                "Diagnostic export failed: \(error.localizedDescription)",
                language: lang
            )
        }
    }

    private var diagnostics: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return """
        321Doit Diagnostics
        App Version: \(UpdateSettings.appVersion) (\(UpdateSettings.buildNumber))
        macOS: \(os)
        Language: \(settings.settings.general.language.rawValue)
        Time: \(iso8601String(Date()))
        """
    }
}

private struct PaymentQRCodeView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.themeColors) private var colors
    @Environment(\.dismiss) private var dismiss

    private var lang: AppLanguage { settings.settings.general.language.resolved }

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.t("支持开发", "Support Development", language: lang))
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.t("微信扫码支持 321Doit 持续开发。",
                                "Scan with WeChat to support ongoing 321Doit development.",
                                language: lang))
                        .font(.system(size: 11))
                        .foregroundStyle(colors.textSecondary)
                }
                Spacer()
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(colors.textSecondary)
                    .contentShape(Rectangle())
                    .help(L10n.t("关闭", "Close", language: lang))
                    .onTapGesture {
                        dismiss()
                    }
            }

            if let image = paymentImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 340, height: 340)
                    .padding(18)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 10)
            } else {
                Text(L10n.t("未找到收款码资源。", "Payment QR code resource was not found.", language: lang))
                    .font(.system(size: 12))
                    .foregroundStyle(colors.textSecondary)
                    .frame(width: 340, height: 220)
            }

            HStack(spacing: 8) {
                Button {
                    copy(UpdateSettings.supportWeChat)
                } label: {
                    Label(L10n.t("复制微信 / 电话", "Copy WeChat / Phone", language: lang), systemImage: "doc.on.doc")
                }
                Button {
                    dismiss()
                } label: {
                    Text(L10n.t("完成", "Done", language: lang))
                }
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .focusable(false)
        }
        .padding(24)
        .frame(width: 460)
        .background(colors.surfaceBg)
    }

    private var paymentImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "WeChatSupportQR", withExtension: "jpg") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
