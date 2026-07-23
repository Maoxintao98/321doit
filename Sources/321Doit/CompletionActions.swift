import AppKit
import Foundation
import UserNotifications

enum CompletionActions {
    static func handleSuccess(report: OffloadReport, appSettings: AppSettings) async {
        if appSettings.notification.soundOnFinish {
            await MainActor.run {
                _ = NSSound(named: "Glass")?.play()
            }
        }

        let lang = appSettings.general.language
        let count = report.successfulTargets.count

        if appSettings.notification.systemNotification {
            await postUserNotification(
                title: L10n.t("321Doit 完成", "321Doit Finished", language: lang),
                body: L10n.t(
                    "\(report.settings.projectName) \(report.settings.cardNumber): \(count) 个目标成功",
                    "\(report.settings.projectName) \(report.settings.cardNumber): \(count) destination\(count == 1 ? "" : "s") succeeded",
                    language: lang
                )
            )
        }

        await WebhookNotifier.sendCompletion(report: report, appSettings: appSettings)

        await MainActor.run {
            if appSettings.notification.autoOpenReportOnFinish || appSettings.report.autoOpenReportOnFinish {
                let urls = report.successfulTargets.flatMap {
                    [$0.pdfURL, $0.csvURL, $0.jsonURL, $0.txtURL, $0.mhlURL].compactMap { $0 }
                }
                if !urls.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            } else if appSettings.report.autoOpenReportFolderOnFinish {
                let urls = report.successfulTargets.compactMap(\.pdfURL)
                if !urls.isEmpty {
                    NSWorkspace.shared.activateFileViewerSelecting(urls)
                }
            }

            if appSettings.notification.autoOpenOutputFolderOnFinish,
               let outputURL = report.successfulTargets.first?.outputURL {
                NSWorkspace.shared.open(outputURL)
            }

            if appSettings.notification.popupOnFinish {
                let alert = NSAlert()
                alert.messageText = L10n.t("321Doit 任务完成", "321Doit Task Completed", language: lang)
                alert.informativeText = L10n.t(
                    "\(report.settings.projectName) \(report.settings.cardNumber)\n成功目标：\(count)",
                    "\(report.settings.projectName) \(report.settings.cardNumber)\nDestinations succeeded: \(count)",
                    language: lang
                )
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }

        if appSettings.handoff.autoOpenAfterHandoff,
           let handoff = report.successfulTargets.compactMap(\.handoff).first {
            await autoSendHandoff(handoff: handoff, target: appSettings.handoff.target)
        }
    }

    private static func autoSendHandoff(handoff: HandoffOutput, target: HandoffTarget) async {
        if target.includesResolve, let scriptURL = handoff.resolveScriptURL,
           HandoffAppDetector.isResolveInstalled() {
            do {
                let result = try await HandoffResolveLauncher.sendToResolve(scriptURL: scriptURL)
                if !result.ok {
                    NSLog("321Doit auto-send to Resolve failed: %@", result.errorMessage ?? result.rawOutput)
                    AppLogger.log(.error, category: "handoff", "Automatic Resolve handoff failed: \(result.errorMessage ?? result.rawOutput)")
                }
            } catch {
                NSLog("321Doit auto-send to Resolve threw: %@", error.localizedDescription)
                AppLogger.log(.error, category: "handoff", "Automatic Resolve handoff failed: \(error.localizedDescription)")
            }
        }
        if target.includesFinalCut, let fcpxmldURL = handoff.fcpxmldURL,
           HandoffAppDetector.isFinalCutInstalled() {
            do {
                try await HandoffFinalCutLauncher.sendToFinalCut(
                    fcpxmldURL: fcpxmldURL,
                    compatURL: handoff.fcpxmlCompatURL
                )
            } catch {
                NSLog("321Doit auto-send to Final Cut Pro threw: %@", error.localizedDescription)
                AppLogger.log(.error, category: "handoff", "Automatic Final Cut Pro handoff failed: \(error.localizedDescription)")
            }
        }
    }

    static func handleFailure(error: Error, appSettings: AppSettings) async {
        if appSettings.notification.warnSoundOnVerifyFailure {
            await MainActor.run {
                _ = NSSound(named: "Basso")?.play()
            }
        }

        let lang = appSettings.general.language
        let failureTitle = L10n.t("321Doit 任务失败", "321Doit Task Failed", language: lang)

        if appSettings.notification.systemNotification {
            await postUserNotification(
                title: failureTitle,
                body: error.localizedDescription
            )
        }

        await WebhookNotifier.sendFailure(error: error, appSettings: appSettings)

        if appSettings.notification.popupOnFailure {
            await MainActor.run {
                let alert = NSAlert()
                alert.messageText = failureTitle
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    private static func postUserNotification(title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "321doit-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try await center.add(request)
        } catch {
            NSLog("[321Doit] notification failed: \(error)")
            AppLogger.log(.warning, category: "notification", "System notification failed: \(error.localizedDescription)")
        }
    }
}

enum WebhookNotifier {
    enum WebhookSendError: LocalizedError {
        case missingCredential(WebhookKind)
        case invalidURL(WebhookKind)
        case invalidPayload
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingCredential(let kind):
                return "\(kind.displayName) webhook credential is missing."
            case .invalidURL(let kind):
                return "\(kind.displayName) webhook URL is invalid."
            case .invalidPayload:
                return "Webhook test payload is invalid."
            case .requestFailed(let message):
                return message
            }
        }
    }

    static func sendCompletion(report: OffloadReport, appSettings: AppSettings) async {
        let text = L10n.t(
            "321Doit 完成：\(report.settings.projectName) \(report.settings.cardNumber)，成功目标 \(report.successfulTargets.count)，文件 \(report.totalFiles)，容量 \(formatBytes(report.totalBytes))。",
            "321Doit finished: \(report.settings.projectName) \(report.settings.cardNumber). \(report.successfulTargets.count) destination\(report.successfulTargets.count == 1 ? "" : "s") succeeded, \(report.totalFiles) files, \(formatBytes(report.totalBytes)).",
            language: appSettings.general.language
        )
        let payload: [String: Any] = [
            "event": "completed",
            "app": appName,
            "project": report.settings.projectName,
            "card": report.settings.cardNumber,
            "totalFiles": report.totalFiles,
            "totalBytes": report.totalBytes,
            "checksum": report.settings.checksumAlgorithm.displayName,
            "successfulTargets": report.successfulTargets.count,
            "text": text
        ]
        await send(text: text, payload: payload, appSettings: appSettings)
    }

    static func sendFailure(error: Error, appSettings: AppSettings) async {
        let text = L10n.t(
            "321Doit 失败：\(error.localizedDescription)",
            "321Doit failed: \(error.localizedDescription)",
            language: appSettings.general.language
        )
        let payload: [String: Any] = [
            "event": "failed",
            "app": appName,
            "error": error.localizedDescription,
            "text": text
        ]
        await send(text: text, payload: payload, appSettings: appSettings)
    }

    static func sendTest(kind: WebhookKind) async throws {
        guard let urlString = try WebhookCredentialStore.read(kind: kind),
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw WebhookSendError.missingCredential(kind)
        }
        guard let url = URL(string: urlString) else {
            throw WebhookSendError.invalidURL(kind)
        }

        let text = "321Doit webhook test sent successfully."
        let body = body(for: kind, text: text, payload: [
            "event": "test",
            "app": appName,
            "appVersion": appVersionString,
            "text": text
        ])
        try await postJSONThrowing(body, to: url)
    }

    private static func send(text: String, payload: [String: Any], appSettings: AppSettings) async {
        for kind in WebhookKind.allCases {
            let endpoint = appSettings.notification.endpoint(for: kind)
            guard endpoint.enabled else { continue }
            do {
                guard let urlString = try WebhookCredentialStore.read(kind: kind),
                      let url = URL(string: urlString) else {
                    NSLog("[321Doit] webhook skipped: missing or invalid credential for \(kind.rawValue)")
                    AppLogger.log(.warning, category: "webhook", "Skipped \(kind.rawValue) webhook because its credential is missing or invalid")
                    continue
                }
                await postJSON(body(for: kind, text: text, payload: payload), to: url)
            } catch {
                NSLog("[321Doit] webhook credential read failed: \(kind.rawValue) \(error)")
                AppLogger.log(.warning, category: "webhook", "Could not read \(kind.rawValue) webhook credential: \(error.localizedDescription)")
            }
        }
    }

    private static func body(for kind: WebhookKind, text: String, payload: [String: Any]) -> [String: Any] {
        switch kind {
        case .slack:
            return ["text": text]
        case .feishu:
            return ["msg_type": "text", "content": ["text": text]]
        case .wecom:
            return ["msgtype": "text", "text": ["content": text]]
        case .custom:
            return payload
        }
    }

    private static func postJSON(_ body: Any, to url: URL) async {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            NSLog("[321Doit] webhook failed: \(WebhookCredentialStore.mask(url.absoluteString)) \(error)")
            AppLogger.log(.warning, category: "webhook", "Webhook request failed for \(WebhookCredentialStore.mask(url.absoluteString)): \(error.localizedDescription)")
        }
    }

    private static func postJSONThrowing(_ body: Any, to url: URL) async throws {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            throw WebhookSendError.invalidPayload
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                throw WebhookSendError.requestFailed("HTTP \(http.statusCode)")
            }
        } catch let error as WebhookSendError {
            throw error
        } catch {
            throw WebhookSendError.requestFailed(error.localizedDescription)
        }
    }
}
