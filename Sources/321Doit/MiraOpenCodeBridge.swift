import Darwin
import Foundation
import Combine
import Security

extension Notification.Name {
    static let miraProjectDataDidChange = Notification.Name("321doit.mira.project-data-did-change")
    static let miraProviderCredentialsDidChange = Notification.Name("321doit.mira.provider-credentials-did-change")
    static let miraModelServicesDidChange = Notification.Name("321doit.mira.model-services-did-change")
}

struct MiraProjectContext: Equatable {
    let id: UUID
    let name: String
    let folderURL: URL
}

/// A committed project change reported by Mira's 321Doit tool bridge. The
/// main workspace uses the path rather than a previously bound project so a
/// global Mira session can update any authorized project and refresh an open
/// matching workspace immediately.
struct MiraProjectDataChange: Equatable {
    let projectPath: String
    let projectID: UUID?
    let toolName: String
    let action: String
}

struct MiraSession: Identifiable, Equatable {
    let id: String
    var title: String
    var projectID: UUID?
}

struct MiraMessage: Identifiable, Equatable {
    enum Role: String {
        case user
        case assistant
        case tool
        case system
        case thinking
    }

    let id: String
    let role: Role
    let text: String
    let toolName: String?
    let toolStatus: String?
    let toolInput: String?
    let toolOutput: String?
}

struct MiraPermissionRequest: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let title: String
    let detail: String
    let reversible: Bool
}

/// A regular conversational question raised by OpenCode's `question` tool.
/// This is distinct from a permission request: answering it gives the agent
/// information it needs to continue, but does not authorize a write itself.
struct MiraQuestionRequest: Identifiable, Equatable {
    let id: String
    let sessionID: String
    let questions: [MiraQuestion]
}

struct MiraQuestion: Identifiable, Equatable {
    struct Option: Identifiable, Equatable {
        let label: String
        let detail: String

        var id: String { label }
    }

    let id: String
    let header: String
    let prompt: String
    let options: [Option]
    let allowsMultipleSelection: Bool
    let allowsCustomAnswer: Bool
}

enum MiraExecutionPermissionMode: String, CaseIterable, Identifiable {
    case automatic
    case confirmEveryWrite

    var id: String { rawValue }

    private static let defaultsKey = "321doit.mira.execution-permission-mode"

    static func load() -> MiraExecutionPermissionMode {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = MiraExecutionPermissionMode(rawValue: raw) else {
            return .confirmEveryWrite
        }
        return mode
    }

    static func save(_ mode: MiraExecutionPermissionMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    }
}

struct MiraModelVariant: Identifiable, Equatable {
    let id: String
}

struct MiraModelOption: Identifiable, Equatable {
    let id: String
    let name: String
    let isFree: Bool
    let providerID: String
    let providerName: String
    let variants: [MiraModelVariant]

    init(
        id: String,
        name: String,
        isFree: Bool,
        providerID: String? = nil,
        providerName: String? = nil,
        variants: [MiraModelVariant] = []
    ) {
        let inferredProviderID = id.split(separator: "/", maxSplits: 1).first.map(String.init) ?? "opencode"
        self.id = id
        self.name = name
        self.isFree = isFree
        self.providerID = providerID ?? inferredProviderID
        self.providerName = providerName ?? self.providerID
        self.variants = variants
    }
}

struct MiraModelProvider: Identifiable, Equatable {
    let id: String
    let name: String
    let models: [MiraModelOption]
}

/// One user-configured OpenAI-compatible service. The API key never enters
/// UserDefaults; it is stored separately in the macOS Keychain.
struct MiraCustomModelService: Codable, Equatable {
    var isEnabled = false
    var providerID = "my-model"
    var displayName = "我的模型"
    var baseURL = ""
    var modelID = ""
    var modelName = ""
    var usesResponsesAPI = false

    var hasValidProviderID: Bool {
        let value = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return !value.isEmpty && value.unicodeScalars.allSatisfy(allowed.contains)
    }

    var hasAllowedBaseURL: Bool {
        let value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value),
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }
        if scheme == "https" { return true }
        guard scheme == "http" else { return false }
        if host == "localhost" || host == "::1" { return true }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        return octets.count == 4
            && octets.first == "127"
            && octets.allSatisfy { octet in
                guard let value = Int(octet) else { return false }
                return (0...255).contains(value)
            }
    }

    var isConfigured: Bool {
        isEnabled
            && hasValidProviderID
            && hasAllowedBaseURL
            && !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum MiraCustomModelServiceStore {
    private static let defaultsKey = "321doit.mira.custom-model-service"

    static func load() -> MiraCustomModelService {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let service = try? JSONDecoder().decode(MiraCustomModelService.self, from: data) else {
            return .init()
        }
        return service
    }

    static func save(_ service: MiraCustomModelService) throws {
        let data = try JSONEncoder().encode(service)
        UserDefaults.standard.set(data, forKey: defaultsKey)
        NotificationCenter.default.post(name: .miraModelServicesDidChange, object: nil)
    }
}

enum MiraCustomModelAPIKeyStore {
    private static let service = "com.321doit.mira.custom-model"
    private static let account = "api-key"

    static func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status) }
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ apiKey: String) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
            return
        }
        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw error(status) }
        var create = baseQuery
        create[kSecValueData as String] = data
        create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw error(addStatus) }
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Could not store the model-service API key (Keychain error \(status))."
        ])
    }
}

/// The OpenCode Go key is kept in Keychain and is materialized only into
/// Mira's private OpenCode credential directory when the backend starts.
enum MiraOpenCodeGoAPIKeyStore {
    private static let service = "com.321doit.mira.opencode-go"
    private static let account = "api-key"

    static func read() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status) }
        return (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func save(_ apiKey: String) throws {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            let status = SecItemDelete(baseQuery as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
            NotificationCenter.default.post(name: .miraProviderCredentialsDidChange, object: nil)
            return
        }

        let data = Data(value.utf8)
        let status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess {
            NotificationCenter.default.post(name: .miraProviderCredentialsDidChange, object: nil)
            return
        }
        guard status == errSecItemNotFound else { throw error(status) }
        var create = baseQuery
        create[kSecValueData as String] = data
        create[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(create as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw error(addStatus) }
        NotificationCenter.default.post(name: .miraProviderCredentialsDidChange, object: nil)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
            NSLocalizedDescriptionKey: "Could not store the OpenCode Go API key (Keychain error \(status))."
        ])
    }
}

enum MiraServiceState: Equatable {
    case stopped
    case needsConfiguration
    case starting
    case connected(version: String)
    case failed(String)
}

enum MiraBridgeError: LocalizedError {
    case executableMissing
    case personaUnavailable
    case invalidResponse
    case serviceUnavailable
    case notFound
    case server(String)

    var errorDescription: String? {
        localizedDescription(language: .en)
    }

    func localizedDescription(language: AppLanguage) -> String {
        switch self {
        case .executableMissing:
            return L10n.t("未找到兼容的 OpenCode。请安装 OpenCode，或将兼容版本随 321Doit 一起打包。", "No compatible OpenCode installation was found. Install OpenCode or bundle a compatible version with 321Doit.", language: language)
        case .personaUnavailable:
            return L10n.t("Mira 人设资源缺失或格式无效。请重新安装 321Doit。", "Mira's persona resource is missing or invalid. Reinstall 321Doit.", language: language)
        case .invalidResponse:
            return L10n.t("Mira 收到了无法识别的服务响应。", "Mira received an unrecognized service response.", language: language)
        case .serviceUnavailable:
            return L10n.t("Mira 服务当前不可用。", "Mira's service is currently unavailable.", language: language)
        case .notFound:
            return L10n.t("该会话已不存在。", "This session no longer exists.", language: language)
        case .server(let message):
            return message
        }
    }
}

@MainActor
final class OpenCodeBridge: ObservableObject {
    struct MiraPersona: Equatable {
        let description: String
        let mode: String
        let temperature: Double
        let permissions: [String: String]
        let instructions: String
    }

    @Published private(set) var state: MiraServiceState = .stopped
    @Published private(set) var sessions: [MiraSession] = []
    @Published private(set) var messages: [MiraMessage] = []
    @Published private(set) var pendingPermission: MiraPermissionRequest?
    @Published private(set) var pendingQuestion: MiraQuestionRequest?
    @Published private(set) var isRunning = false
    @Published private(set) var currentSessionID: String?
    @Published private(set) var selectedModelID: String
    @Published private(set) var selectedReasoningVariantID: String?
    @Published private(set) var availableModels: [MiraModelOption]
    @Published private(set) var authorizedRoots: [URL] = []
    @Published private(set) var executionPermissionMode: MiraExecutionPermissionMode

    private var process: Process?
    private var baseURL: URL?
    private var password = ""
    private var pollingTask: Task<Void, Never>?
    private var projectContext: MiraProjectContext?
    private var runtimeDirectory: URL?
    /// Changes whenever the visible conversation changes. Async responses from
    /// an older conversation must never update the newly selected one.
    private var conversationRevision = 0
    private var activeSessionID: String?
    private var authorizedRootTokens: [SecurityScopedAccessToken] = []
    private var language: AppLanguage = .system

    @Published private(set) var userFacingError: String?

    init() {
        let initialModelID = Self.initialModelID()
        selectedModelID = initialModelID
        selectedReasoningVariantID = UserDefaults.standard.string(
            forKey: Self.reasoningVariantDefaultsKey(for: initialModelID)
        )
        availableModels = []
        executionPermissionMode = MiraExecutionPermissionMode.load()
    }

    /// Mira never ships a shared or sponsored model balance. A user must
    /// configure either their own OpenAI-compatible service or their own
    /// OpenCode Go subscription key before the local backend is started.
    static func hasUserConfiguredService() -> Bool {
        if MiraCustomModelServiceStore.load().isConfigured {
            return true
        }
        let key = try? MiraOpenCodeGoAPIKeyStore.read()
        return !(key ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func initialModelID() -> String {
        let service = MiraCustomModelServiceStore.load()
        guard service.isConfigured else { return "" }
        return "\(service.providerID.trimmingCharacters(in: .whitespacesAndNewlines))/\(service.modelID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    func setLanguage(_ language: AppLanguage) {
        self.language = language.resolved
    }

    private func t(_ zh: String, _ en: String) -> String {
        L10n.t(zh, en, language: language)
    }

    private func userFacingMessage(_ error: Error) -> String {
        if let bridgeError = error as? MiraBridgeError {
            return bridgeError.localizedDescription(language: language)
        }
        return error.localizedDescription
    }

    deinit {
        pollingTask?.cancel()
        process?.terminate()
    }

    func start(projectContext: MiraProjectContext?, forceRestart: Bool = false) async {
        guard Self.supportsMira else {
            state = .failed(t("Mira 首版仅支持 Apple Silicon（ARM64）Mac，Intel 芯片暂不启用 AI 模式。", "Mira currently supports Apple Silicon (ARM64) Macs only; AI mode is unavailable on Intel Macs."))
            return
        }
        if !forceRestart,
           self.projectContext == projectContext,
           case .connected = state,
           process?.isRunning == true {
            return
        }

        guard Self.hasUserConfiguredService() else {
            shutdown()
            availableModels = []
            selectedModelID = ""
            selectedReasoningVariantID = nil
            state = .needsConfiguration
            return
        }

        resetConversation(clearSessions: true)
        shutdown()
        self.projectContext = projectContext
        authorizedRoots = MiraAuthorizedRoots.all()
        authorizedRootTokens = SecurityScopedBookmarks.startAccessing(
            urls: authorizedRoots.map { ($0, "mira-authorized-root") }
        )
        state = .starting

        do {
            let executable = try Self.locateExecutable()
            let runtime = try Self.prepareRuntime(
                projectContext: projectContext,
                modelID: selectedModelID,
                authorizedRoots: authorizedRoots,
                executionPermissionMode: executionPermissionMode
            )
            let port = try Self.availableLoopbackPort()
            let secret = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let url = URL(string: "http://127.0.0.1:\(port)")!

            let task = Process()
            task.executableURL = executable
            task.arguments = [
                "serve",
                "--hostname", "127.0.0.1",
                "--port", String(port)
            ]
            // Keep OpenCode itself inside Mira's isolated workspace. Project
            // access is granted only to the 321Doit MCP helper below.
            task.currentDirectoryURL = runtime.workspace

            var environment = ProcessInfo.processInfo.environment
            environment["OPENCODE_CONFIG"] = runtime.config.path
            environment["OPENCODE_SERVER_USERNAME"] = "mira"
            environment["OPENCODE_SERVER_PASSWORD"] = secret
            environment["XDG_DATA_HOME"] = runtime.data.path
            environment["XDG_CACHE_HOME"] = runtime.cache.path
            environment["XDG_CONFIG_HOME"] = runtime.configuration.path
            runtime.providerEnvironment.forEach { key, value in
                environment[key] = value
            }
            task.environment = environment

            let output = Pipe()
            task.standardOutput = output
            task.standardError = output
            output.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                let safe = text.replacingOccurrences(of: secret, with: "<redacted>")
                AppLogger.log(.debug, category: "mira-service", String(safe.prefix(2_000)))
            }
            task.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self, self.process === process else { return }
                    self.pollingTask?.cancel()
                    self.isRunning = false
                    if case .stopped = self.state { return }
                    self.state = .failed(self.t("Mira 后台服务已停止（代码 \(process.terminationStatus)）。", "The Mira background service stopped (code \(process.terminationStatus))."))
                }
            }

            try task.run()
            process = task
            baseURL = url
            password = secret
            runtimeDirectory = runtime.root

            let version = try await waitUntilHealthy()
            state = .connected(version: version)
            await refreshModels()
            await refreshSessions()
        } catch {
            shutdown()
            state = .failed(userFacingMessage(error))
            AppLogger.log(.error, category: "mira-service", "Could not start Mira: \(userFacingMessage(error))")
        }
    }

    func updateProjectContext(_ context: MiraProjectContext?) async {
        guard context != projectContext else { return }
        await start(projectContext: context)
    }

    func retry() async {
        await start(projectContext: projectContext)
    }

    func addAuthorizedRoot(_ url: URL) async {
        MiraAuthorizedRoots.add(url)
        await start(projectContext: projectContext, forceRestart: true)
    }

    func removeAuthorizedRoot(_ url: URL) async {
        MiraAuthorizedRoots.remove(url)
        await start(projectContext: projectContext, forceRestart: true)
    }

    func selectModel(_ id: String) async {
        guard availableModels.contains(where: { $0.id == id }),
              id != selectedModelID else { return }
        selectedModelID = id
        UserDefaults.standard.set(id, forKey: "321doit.mira.model")
        selectedReasoningVariantID = Self.savedReasoningVariant(for: id, in: availableModels)
    }

    func selectReasoningVariant(_ id: String?) async {
        guard id != selectedReasoningVariantID else { return }
        selectedReasoningVariantID = id
        let key = Self.reasoningVariantDefaultsKey(for: selectedModelID)
        if let id {
            UserDefaults.standard.set(id, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    var currentModelName: String {
        availableModels.first(where: { $0.id == selectedModelID })?.name ?? selectedModelID
    }

    var currentModelVariants: [MiraModelVariant] {
        availableModels.first(where: { $0.id == selectedModelID })?.variants ?? []
    }

    var modelProviders: [MiraModelProvider] {
        Dictionary(grouping: availableModels, by: \.providerID)
            .compactMap { providerID, models in
                guard let first = models.first else { return nil }
                return MiraModelProvider(
                    id: providerID,
                    name: first.providerName,
                    models: models.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func reloadProviderCredentials() async {
        await start(projectContext: projectContext, forceRestart: true)
    }

    func selectExecutionPermissionMode(_ mode: MiraExecutionPermissionMode) async {
        guard mode != executionPermissionMode else { return }
        executionPermissionMode = mode
        MiraExecutionPermissionMode.save(mode)
        await start(projectContext: projectContext, forceRestart: true)
    }

    func clearSession() async {
        let runningSessionID = activeSessionID
        resetConversation()
        await abort(sessionID: runningSessionID)
    }

    func selectSession(_ id: String) async {
        let runningSessionID = activeSessionID
        resetConversation(selecting: id)
        await abort(sessionID: runningSessionID)

        let revision = conversationRevision
        await refreshMessages(sessionID: id, revision: revision)
    }

    func deleteSession(_ id: String) async {
        let wasRunning = activeSessionID == id
        if wasRunning {
            cancelPolling()
            await abort(sessionID: id)
        }

        do {
            // OpenCode may reply to a successful DELETE with plain text rather
            // than JSON. The response body is not part of this operation.
            _ = try await request(path: "/session/\(id)", method: "DELETE", expectsJSON: false)
            removeSessionLocally(id)
            await refreshSessions()
        } catch {
            if case MiraBridgeError.notFound = error {
                // A stale entry is already gone on the server, which is the
                // intended end state for a delete action.
                removeSessionLocally(id)
                await refreshSessions()
                return
            }
            userFacingError = t("无法删除会话：\(userFacingMessage(error))", "Could not delete the session: \(userFacingMessage(error))")
            if wasRunning, currentSessionID == id {
                isRunning = false
                activeSessionID = nil
            }
        }
    }

    func dismissUserFacingError() {
        userFacingError = nil
    }

    func presentUserFacingError(_ message: String) {
        userFacingError = message
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let revision = conversationRevision
        let sessionID: String
        if let currentSessionID {
            sessionID = currentSessionID
        } else {
            do {
                sessionID = try await createRemoteSession(title: Self.sessionTitle(for: trimmed))
            } catch {
                userFacingError = t("无法创建会话：\(userFacingMessage(error))", "Could not create a session: \(userFacingMessage(error))")
                return
            }
            guard revision == conversationRevision else { return }
            currentSessionID = sessionID
            messages = []
            await refreshSessions()
        }

        let contextLine: String
        if let projectContext {
            contextLine = t("当前 321doit 项目：\(projectContext.name)，项目 ID：\(projectContext.id.uuidString.lowercased())。只能操作这个项目。", "Current 321doit project: \(projectContext.name), project ID: \(projectContext.id.uuidString.lowercased()). You may operate only on this project.")
        } else {
            contextLine = t("当前是 321doit 全局 AI 模式，不绑定固定项目。先从用户明确授权的位置列出或读取真实项目；每次项目操作都使用明确的 project_path 或 root_path。可以新建、修改项目，也可在获得用户确认后将项目移到废纸篓。不得访问未授权位置。", "This is 321doit's global AI mode, with no project bound. First list or read real projects only from locations the user explicitly authorized; every project operation must use an explicit project_path or root_path. You may create or update projects and, after user confirmation, move a project to the Trash. Do not access unauthorized locations.")
        }

        messages.append(MiraMessage(
            id: "local-\(UUID().uuidString)",
            role: .user,
            text: trimmed,
            toolName: nil,
            toolStatus: nil,
            toolInput: nil,
            toolOutput: nil
        ))
        isRunning = true
        activeSessionID = sessionID

        do {
            var body: [String: Any] = [
                "agent": "mira",
                "system": contextLine,
                "parts": [["type": "text", "text": trimmed]]
            ]
            if let model = Self.splitModelID(selectedModelID) {
                body["model"] = [
                    "providerID": model.providerID,
                    "modelID": model.modelID
                ]
            }
            if let selectedReasoningVariantID {
                body["variant"] = selectedReasoningVariantID
            }
            _ = try await request(
                path: "/session/\(sessionID)/prompt_async",
                method: "POST",
                body: body,
                expectsJSON: false
            )
            guard revision == conversationRevision, currentSessionID == sessionID else { return }
            beginPolling(sessionID: sessionID, revision: revision)
        } catch {
            guard revision == conversationRevision, currentSessionID == sessionID else { return }
            isRunning = false
            activeSessionID = nil
            messages.append(MiraMessage(
                id: "error-\(UUID().uuidString)",
                role: .system,
                text: userFacingMessage(error),
                toolName: nil,
                toolStatus: "failed",
                toolInput: nil,
                toolOutput: nil
            ))
        }
    }

    func stop() async {
        guard let sessionID = activeSessionID else { return }
        let revision = conversationRevision
        cancelPolling()
        await abort(sessionID: sessionID)
        guard revision == conversationRevision, currentSessionID == sessionID else { return }
        await refreshMessages(sessionID: sessionID, revision: revision)
    }

    func answerPermission(allow: Bool) async {
        guard let permission = pendingPermission else { return }
        do {
            _ = try await request(
                path: "/session/\(permission.sessionID)/permissions/\(permission.id)",
                method: "POST",
                body: ["response": allow ? "once" : "reject"]
            )
            pendingPermission = nil
            guard permission.sessionID == currentSessionID else { return }
            beginPolling(sessionID: permission.sessionID, revision: conversationRevision)
        } catch {
            messages.append(MiraMessage(
                id: "permission-error-\(UUID().uuidString)",
                role: .system,
                text: userFacingMessage(error),
                toolName: nil,
                toolStatus: "failed",
                toolInput: nil,
                toolOutput: nil
            ))
        }
    }

    func answerQuestion(answers: [[String]]) async {
        guard let question = pendingQuestion,
              answers.count == question.questions.count else { return }
        do {
            _ = try await request(
                path: "/question/\(question.id)/reply",
                method: "POST",
                body: ["answers": answers]
            )
            pendingQuestion = nil
            guard question.sessionID == currentSessionID else { return }
            beginPolling(sessionID: question.sessionID, revision: conversationRevision)
        } catch {
            messages.append(MiraMessage(
                id: "question-error-\(UUID().uuidString)",
                role: .system,
                text: t("无法提交你的选择：\(userFacingMessage(error))", "Could not submit your selection: \(userFacingMessage(error))"),
                toolName: nil,
                toolStatus: "failed",
                toolInput: nil,
                toolOutput: nil
            ))
        }
    }

    func rejectQuestion() async {
        guard let question = pendingQuestion else { return }
        do {
            _ = try await request(
                path: "/question/\(question.id)/reject",
                method: "POST"
            )
            pendingQuestion = nil
            guard question.sessionID == currentSessionID else { return }
            beginPolling(sessionID: question.sessionID, revision: conversationRevision)
        } catch {
            messages.append(MiraMessage(
                id: "question-reject-error-\(UUID().uuidString)",
                role: .system,
                text: t("无法取消这个问题：\(userFacingMessage(error))", "Could not dismiss this question: \(userFacingMessage(error))"),
                toolName: nil,
                toolStatus: "failed",
                toolInput: nil,
                toolOutput: nil
            ))
        }
    }

    func shutdown() {
        cancelPolling()
        authorizedRootTokens.forEach { $0.stop() }
        authorizedRootTokens = []
        authorizedRoots = []
        if let process, process.isRunning {
            process.terminate()
        }
        process = nil
        baseURL = nil
        password = ""
        state = .stopped
    }

    private func beginPolling(sessionID: String, revision: Int) {
        cancelPolling()
        isRunning = true
        activeSessionID = sessionID
        pollingTask = Task { [weak self] in
            guard let self else { return }
            var observedBusy = false
            for attempt in 0..<1_800 {
                guard !Task.isCancelled else { return }
                guard revision == self.conversationRevision,
                      self.currentSessionID == sessionID,
                      self.activeSessionID == sessionID else { return }
                await self.refreshMessages(sessionID: sessionID, revision: revision)
                let busy = await self.refreshStatus(sessionID: sessionID)
                observedBusy = observedBusy || busy
                await self.refreshPermission(sessionID: sessionID, revision: revision)
                await self.refreshQuestion(sessionID: sessionID, revision: revision)
                let hasTerminalAssistantPart = self.messages.contains {
                    $0.role == .assistant || ($0.role == .system && $0.toolStatus == "failed")
                }
                if !busy && (observedBusy || hasTerminalAssistantPart)
                    && self.pendingPermission == nil && self.pendingQuestion == nil {
                    self.isRunning = false
                    self.activeSessionID = nil
                    await self.refreshSessions()
                    return
                }
                if !busy && attempt == 85 && self.pendingPermission == nil && self.pendingQuestion == nil {
                    self.isRunning = false
                    self.activeSessionID = nil
                    self.messages.append(MiraMessage(
                        id: "timeout-\(UUID().uuidString)",
                        role: .system,
                        text: self.t("模型没有返回结果。请检查网络或模型服务后重试。", "The model returned no result. Check the network or model service and try again."),
                        toolName: nil,
                        toolStatus: "failed",
                        toolInput: nil,
                        toolOutput: nil
                    ))
                    return
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
            guard revision == self.conversationRevision, self.currentSessionID == sessionID else { return }
            self.isRunning = false
            self.activeSessionID = nil
        }
    }

    private func refreshSessions() async {
        do {
            let json = try await request(path: "/session")
            guard let list = json as? [[String: Any]] else { return }
            sessions = list.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return MiraSession(
                    id: id,
                    title: (item["title"] as? String) ?? t("Mira 会话", "Mira Session"),
                    projectID: projectContext?.id
                )
            }
        } catch {
            AppLogger.log(.warning, category: "mira-service", "Could not refresh sessions: \(error.localizedDescription)")
        }
    }

    private func refreshModels() async {
        do {
            let json = try await request(path: "/provider")
            let customService = MiraCustomModelServiceStore.load()
            let explicitlyConfiguredProviders: Set<String> = customService.isConfigured
                ? [customService.providerID.trimmingCharacters(in: .whitespacesAndNewlines)]
                : []
            let models = Self.modelOptions(
                from: json,
                explicitlyConfiguredProviders: explicitlyConfiguredProviders
            )
            availableModels = models
            if !availableModels.contains(where: { $0.id == selectedModelID }),
               let fallback = availableModels.first {
                selectedModelID = fallback.id
                UserDefaults.standard.set(fallback.id, forKey: "321doit.mira.model")
            } else if availableModels.isEmpty {
                selectedModelID = ""
                UserDefaults.standard.removeObject(forKey: "321doit.mira.model")
            }
            selectedReasoningVariantID = Self.savedReasoningVariant(for: selectedModelID, in: availableModels)
        } catch {
            AppLogger.log(.warning, category: "mira-service", "Could not refresh model list: \(error.localizedDescription)")
        }
    }

    /// Maps the user-configured provider response. OpenCode returns each
    /// model's `variants` here; those are provider-defined reasoning levels.
    static func modelOptions(
        from json: Any,
        explicitlyConfiguredProviders: Set<String> = []
    ) -> [MiraModelOption] {
        guard let object = json as? [String: Any],
              let providers = object["all"] as? [[String: Any]] else { return [] }
        let connected = Set((object["connected"] as? [String]) ?? [])
        var models: [MiraModelOption] = []
        for provider in providers {
            guard let providerID = provider["id"] as? String,
                  connected.contains(providerID) || explicitlyConfiguredProviders.contains(providerID),
                  let entries = provider["models"] as? [String: Any] else { continue }
            let providerName = (provider["name"] as? String) ?? providerID
            for (modelID, rawModel) in entries {
                guard let model = rawModel as? [String: Any] else { continue }
                let fullID = "\(providerID)/\(modelID)"
                let displayName = (model["name"] as? String) ?? modelID
                let cost = model["cost"] as? [String: Any]
                let inputCost = (cost?["input"] as? NSNumber)?.doubleValue
                let outputCost = (cost?["output"] as? NSNumber)?.doubleValue
                let isFree = (inputCost == 0 && outputCost == 0)
                    || modelID.localizedCaseInsensitiveContains("free")
                    || modelID == "big-pickle"
                let variants = Self.modelVariants(from: model)
                models.append(MiraModelOption(
                    id: fullID,
                    name: displayName,
                    isFree: isFree,
                    providerID: providerID,
                    providerName: providerName,
                    variants: variants
                ))
            }
        }
        let unique = Dictionary(grouping: models, by: \.id).compactMap { $0.value.first }
        return unique.sorted {
            if $0.providerName != $1.providerName {
                return $0.providerName.localizedCaseInsensitiveCompare($1.providerName) == .orderedAscending
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func modelVariants(from model: [String: Any]) -> [MiraModelVariant] {
        let identifiers: [String]
        if let variants = model["variants"] as? [String: Any] {
            identifiers = Array(variants.keys)
        } else if let variants = model["variants"] as? [String] {
            identifiers = variants
        } else {
            identifiers = []
        }
        return identifiers
            .filter { !$0.isEmpty && $0 != "default" }
            .sorted()
            .map(MiraModelVariant.init(id:))
    }

    private static func reasoningVariantDefaultsKey(for modelID: String) -> String {
        "321doit.mira.model.variant.\(modelID)"
    }

    private static func savedReasoningVariant(
        for modelID: String,
        in models: [MiraModelOption]
    ) -> String? {
        guard let model = models.first(where: { $0.id == modelID }),
              let saved = UserDefaults.standard.string(forKey: reasoningVariantDefaultsKey(for: modelID)),
              model.variants.contains(where: { $0.id == saved }) else { return nil }
        return saved
    }

    private func removeSessionLocally(_ id: String) {
        sessions.removeAll { $0.id == id }
        if currentSessionID == id {
            resetConversation()
        }
    }

    private func refreshMessages(sessionID: String, revision: Int) async {
        do {
            let json = try await request(path: "/session/\(sessionID)/message")
            guard let list = json as? [[String: Any]] else { return }
            let mapped = list.flatMap { Self.mapMessage($0, language: language) }
            guard revision == conversationRevision, currentSessionID == sessionID else { return }
            let previousCompletedWrites: Set<String> = Set(
                messages.filter(Self.isCompletedWrite).map(\.id)
            )
            messages = mapped
            let newCompletedWrites = mapped.filter { message in
                Self.isCompletedWrite(message) && !previousCompletedWrites.contains(message.id)
            }
            for message in newCompletedWrites {
                if let change = Self.projectDataChange(from: message) {
                    NotificationCenter.default.post(name: .miraProjectDataDidChange, object: change)
                } else if let projectContext {
                    NotificationCenter.default.post(name: .miraProjectDataDidChange, object: projectContext.id)
                }
            }
        } catch {
            AppLogger.log(.warning, category: "mira-service", "Could not refresh messages: \(error.localizedDescription)")
        }
    }

    private func refreshStatus(sessionID: String) async -> Bool {
        do {
            let json = try await request(path: "/session/status")
            guard let statuses = json as? [String: Any],
                  let status = statuses[sessionID] as? [String: Any],
                  let type = status["type"] as? String else { return false }
            return type != "idle"
        } catch {
            return false
        }
    }

    private func refreshPermission(sessionID: String, revision: Int) async {
        do {
            let json = try await request(path: "/permission")
            guard let list = json as? [[String: Any]],
                  let item = list.first(where: { ($0["sessionID"] as? String) == sessionID }),
                  let id = item["id"] as? String,
                  (item["sessionID"] as? String) == sessionID else { return }
            let permission = (item["permission"] as? String) ?? "protected_operation"
            let metadata = item["metadata"] as? [String: Any]
            let title = Self.humanPermissionTitle(permission, language: language)
            let detail = metadata.flatMap(Self.compactJSONString) ?? t("Mira 需要你的确认后才能继续。", "Mira needs your confirmation to continue.")
            guard revision == conversationRevision, currentSessionID == sessionID else { return }
            pendingPermission = MiraPermissionRequest(
                id: id,
                sessionID: sessionID,
                title: title,
                detail: detail,
                reversible: !permission.localizedCaseInsensitiveContains("delete")
            )
        } catch {
            // Older OpenCode versions expose permission requests through events
            // only. Normal conversation remains available if none is pending.
        }
    }

    private func refreshQuestion(sessionID: String, revision: Int) async {
        do {
            let json = try await request(path: "/question")
            guard let list = json as? [[String: Any]] else { return }
            let question = list
                .first(where: { ($0["sessionID"] as? String) == sessionID })
                .flatMap(Self.mapQuestionRequest)
            guard revision == conversationRevision, currentSessionID == sessionID else { return }
            pendingQuestion = question
        } catch {
            // A server without the question endpoint can still use Mira for
            // tasks that do not need an interactive follow-up.
        }
    }

    private func createRemoteSession(title: String) async throws -> String {
        let json = try await request(path: "/session", method: "POST", body: ["title": title])
        guard let object = json as? [String: Any], let id = object["id"] as? String else {
            throw MiraBridgeError.invalidResponse
        }
        return id
    }

    private func resetConversation(selecting sessionID: String? = nil, clearSessions: Bool = false) {
        conversationRevision += 1
        cancelPolling()
        currentSessionID = sessionID
        messages = []
        pendingPermission = nil
        pendingQuestion = nil
        if clearSessions { sessions = [] }
    }

    private func cancelPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isRunning = false
        activeSessionID = nil
    }

    private func abort(sessionID: String?) async {
        guard let sessionID else { return }
        do {
            _ = try await request(path: "/session/\(sessionID)/abort", method: "POST", body: [:])
        } catch {
            AppLogger.log(.warning, category: "mira-service", "Could not stop Mira task: \(error.localizedDescription)")
        }
    }

    private func waitUntilHealthy() async throws -> String {
        var lastError: Error = MiraBridgeError.serviceUnavailable
        for _ in 0..<60 {
            do {
                let json = try await request(path: "/global/health")
                if let object = json as? [String: Any],
                   object["healthy"] as? Bool == true {
                    return (object["version"] as? String) ?? "unknown"
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw lastError
    }

    private func request(
        path: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        expectsJSON: Bool = true
    ) async throws -> Any {
        guard let baseURL,
              let url = URL(string: path, relativeTo: baseURL) else {
            throw MiraBridgeError.serviceUnavailable
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        let auth = Data("mira:\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(auth)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                throw MiraBridgeError.notFound
            }
            let message = String(data: data, encoding: .utf8) ?? t("OpenCode 请求失败", "OpenCode request failed")
            throw MiraBridgeError.server(String(message.prefix(600)))
        }
        if !expectsJSON || data.isEmpty { return true }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func mapMessage(_ item: [String: Any], language: AppLanguage = .system) -> [MiraMessage] {
        guard let info = item["info"] as? [String: Any] else { return [] }
        let messageID = (info["id"] as? String) ?? UUID().uuidString
        let role = MiraMessage.Role(rawValue: (info["role"] as? String) ?? "") ?? .assistant
        let parts = (item["parts"] as? [[String: Any]]) ?? []

        var mapped = parts.enumerated().flatMap { index, part -> [MiraMessage] in
            let type = (part["type"] as? String) ?? ""
            if type == "text", let text = part["text"] as? String, !text.isEmpty {
                // Only assistant output may carry a model's <think> wrapper.
                // User content is displayed exactly as sent, including literal
                // examples of that tag.
                if role == .assistant {
                    return splitThinking(text).enumerated().compactMap { segmentIndex, segment in
                        let messageRole: MiraMessage.Role = segment.isThinking ? .thinking : .assistant
                        guard !segment.text.isEmpty else { return nil }
                        return MiraMessage(
                            id: "\(messageID)-\(index)-\(segmentIndex)",
                            role: messageRole,
                            text: segment.text,
                            toolName: nil,
                            toolStatus: nil,
                            toolInput: nil,
                            toolOutput: nil
                        )
                    }
                }
                return [MiraMessage(
                    id: "\(messageID)-\(index)",
                    role: role,
                    text: text,
                    toolName: nil,
                    toolStatus: nil,
                    toolInput: nil,
                    toolOutput: nil
                )]
            }
            if type == "thinking" || type == "reasoning" {
                let text = (part["text"] as? String)
                    ?? (part["thinking"] as? String)
                    ?? (part["content"] as? String)
                    ?? ""
                if !text.isEmpty {
                    return [MiraMessage(
                        id: "\(messageID)-\(index)",
                        role: .thinking,
                        text: text,
                        toolName: nil,
                        toolStatus: nil,
                        toolInput: nil,
                        toolOutput: nil
                    )]
                }
            }
            if type == "tool" {
                let tool = (part["tool"] as? String) ?? "321doit"
                let state = part["state"] as? [String: Any]
                let status = (state?["status"] as? String) ?? "running"
                // OpenCode puts all tool-call data inside `state`, including
                // inputs and the reason for a failed call.
                let inputStr = state?["input"].flatMap(compactJSONString)
                let outputStr = state?["output"].flatMap(compactJSONString)
                    ?? state?["error"].flatMap(compactJSONString)
                return [MiraMessage(
                    id: "\(messageID)-\(index)",
                    role: .tool,
                    text: humanToolText(tool, status: status, language: language),
                    toolName: tool,
                    toolStatus: status,
                    toolInput: inputStr,
                    toolOutput: outputStr
                )]
            }
            if type == "error" || type == "retry" {
                let errorText = (part["error"] as? String)
                    ?? (part["message"] as? String)
                    ?? L10n.t("模型服务返回错误，请检查网络或模型配置。", "The model service returned an error. Check the network or model configuration.", language: language)
                return [MiraMessage(
                    id: "\(messageID)-\(index)",
                    role: .system,
                    text: errorText,
                    toolName: nil,
                    toolStatus: "failed",
                    toolInput: nil,
                    toolOutput: nil
                )]
            }
            return []
        }
        if mapped.isEmpty, let error = info["error"] {
            let text: String
            if let object = error as? [String: Any],
               let data = object["data"] as? [String: Any],
               let message = data["message"] as? String {
                text = message
            } else if let object = error as? [String: Any],
                      let name = object["name"] as? String {
                text = name
            } else {
                text = L10n.t("模型服务返回错误，请检查网络或模型配置。", "The model service returned an error. Check the network or model configuration.", language: language)
            }
            mapped.append(MiraMessage(
                id: "\(messageID)-error",
                role: .system,
                text: text,
                toolName: nil,
                toolStatus: "failed",
                toolInput: nil,
                toolOutput: nil
            ))
        }
        return mapped
    }

    static func mapQuestionRequest(_ item: [String: Any]) -> MiraQuestionRequest? {
        guard let id = item["id"] as? String,
              let sessionID = item["sessionID"] as? String,
              let rawQuestions = item["questions"] as? [[String: Any]] else {
            return nil
        }
        let questions = rawQuestions.enumerated().compactMap { index, raw -> MiraQuestion? in
            guard let header = raw["header"] as? String,
                  let prompt = raw["question"] as? String else { return nil }
            let options = ((raw["options"] as? [[String: Any]]) ?? []).compactMap { rawOption -> MiraQuestion.Option? in
                guard let label = rawOption["label"] as? String, !label.isEmpty else { return nil }
                return MiraQuestion.Option(
                    label: label,
                    detail: (rawOption["description"] as? String) ?? ""
                )
            }
            return MiraQuestion(
                id: "\(id)-\(index)",
                header: header,
                prompt: prompt,
                options: options,
                allowsMultipleSelection: (raw["multiple"] as? Bool) ?? false,
                allowsCustomAnswer: (raw["custom"] as? Bool) ?? false
            )
        }
        guard !questions.isEmpty else { return nil }
        return MiraQuestionRequest(id: id, sessionID: sessionID, questions: questions)
    }

    private static func humanToolText(_ tool: String, status: String, language: AppLanguage) -> String {
        if tool == "question" {
            switch status {
            case "completed": return L10n.t("已收到你的选择", "Your selection was received", language: language)
            case "error", "failed": return L10n.t("提问失败", "Question failed", language: language)
            default: return L10n.t("等待你的选择", "Waiting for your selection", language: language)
            }
        }
        let action: String
        if tool.contains("storyboard") { action = L10n.t("分镜", "storyboard", language: language) }
        else if tool.contains("production_plan") { action = L10n.t("拍摄计划与通告", "production planning and call sheets", language: language) }
        else if tool.contains("script_log") { action = L10n.t("场记记录", "script logging", language: language) }
        else if tool.contains("offload") { action = L10n.t("素材安全下盘", "secure offload", language: language) }
        else if tool.contains("media_conversion") || tool.contains("media_probe") { action = L10n.t("媒体转换与检查", "media conversion and inspection", language: language) }
        else if tool.contains("project") { action = L10n.t("项目状态", "project", language: language) }
        else { action = L10n.t("321doit 任务", "321doit task", language: language) }

        switch status {
        case "completed": return L10n.t("已完成\(action)操作", "Completed \(action)", language: language)
        case "error", "failed": return L10n.t("\(action)操作失败", "\(action) failed", language: language)
        default: return L10n.t("正在处理\(action)", "Working on \(action)", language: language)
        }
    }

    private static func humanPermissionTitle(_ permission: String, language: AppLanguage) -> String {
        if permission.contains("project_move_to_trash") { return L10n.t("Mira 准备将项目移到废纸篓", "Mira is ready to move a project to the Trash", language: language) }
        if permission.contains("project_create") { return L10n.t("Mira 准备新建项目", "Mira is ready to create a project", language: language) }
        if permission.contains("project_update") { return L10n.t("Mira 准备修改项目信息", "Mira is ready to update project information", language: language) }
        if permission.contains("storyboard") { return L10n.t("Mira 准备修改分镜", "Mira is ready to edit the storyboard", language: language) }
        if permission.contains("production_plan") { return L10n.t("Mira 准备修改拍摄计划或通告", "Mira is ready to edit production planning or call sheets", language: language) }
        if permission.contains("script_log") { return L10n.t("Mira 准备写入场记", "Mira is ready to write to the script log", language: language) }
        if permission.contains("offload") { return L10n.t("Mira 准备开始素材下盘", "Mira is ready to start media offload", language: language) }
        if permission.contains("media_conversion") { return L10n.t("Mira 准备开始媒体转换", "Mira is ready to start media conversion", language: language) }
        if permission.contains("export") { return L10n.t("Mira 准备导出文件", "Mira is ready to export files", language: language) }
        return L10n.t("Mira 请求执行受保护操作", "Mira requests a protected operation", language: language)
    }

    private static func isWriteTool(_ tool: String) -> Bool {
        [
            "create", "update", "trash", "upsert", "record", "export", "apply", "undo", "write",
            "offload_start", "conversion_start", "task_cancel"
        ].contains(where: tool.contains)
    }

    private static func isCompletedWrite(_ message: MiraMessage) -> Bool {
        guard message.role == .tool,
              message.toolStatus == "completed",
              let tool = message.toolName else { return false }
        return isWriteTool(tool)
    }

    private static func projectDataChange(from message: MiraMessage) -> MiraProjectDataChange? {
        guard let toolName = message.toolName,
              let output = message.toolOutput,
              let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let path = (object["project_path"] as? String)
            ?? (object["original_project_path"] as? String)
        guard let path, !path.isEmpty else { return nil }
        let projectID = (object["project_id"] as? String).flatMap(UUID.init(uuidString:))
        let action: String
        if toolName.contains("move_to_trash") { action = "trashed" }
        else if toolName.contains("create") { action = "created" }
        else { action = "updated" }
        return MiraProjectDataChange(
            projectPath: URL(fileURLWithPath: path).standardizedFileURL.path,
            projectID: projectID,
            toolName: toolName,
            action: action
        )
    }

    private static func compactJSONString(_ value: Any) -> String? {
        if let string = value as? String { return String(string.prefix(4_000)) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        return String(text.prefix(4_000))
    }

    private static func splitThinking(_ text: String) -> [(text: String, isThinking: Bool)] {
        guard let regex = try? NSRegularExpression(
            pattern: "(?s)<think>(.*?)(?:</think>|$)",
            options: []
        ) else {
            return [(text, false)]
        }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: fullRange)
        guard !matches.isEmpty else { return [(text, false)] }

        var segments: [(String, Bool)] = []
        var cursor = text.startIndex
        for match in matches {
            guard let matchedRange = Range(match.range(at: 0), in: text),
                  let thinkingRange = Range(match.range(at: 1), in: text) else { continue }
            let visible = String(text[cursor..<matchedRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty { segments.append((visible, false)) }
            let thinking = String(text[thinkingRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinking.isEmpty { segments.append((thinking, true)) }
            cursor = matchedRange.upperBound
        }
        let trailing = String(text[cursor...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty { segments.append((trailing, false)) }
        return segments
    }

    private static func sessionTitle(for text: String) -> String {
        let summary = String(text.prefix(15))
        return summary + (text.count > 15 ? "..." : "")
    }

    private static func splitModelID(_ value: String) -> (providerID: String, modelID: String)? {
        guard let slash = value.firstIndex(of: "/") else { return nil }
        let provider = String(value[..<slash])
        let model = String(value[value.index(after: slash)...])
        guard !provider.isEmpty, !model.isEmpty else { return nil }
        return (provider, model)
    }

    private static func locateExecutable() throws -> URL {
        let fm = FileManager.default
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("Tools/opencode"))
        }
        if let override = ProcessInfo.processInfo.environment["DOIT_OPENCODE_PATH"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates += [
            URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
            URL(fileURLWithPath: "/usr/local/bin/opencode"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".npm-global/bin/opencode"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent(".opencode/bin/opencode")
        ]
        guard let executable = candidates.first(where: {
            fm.isExecutableFile(atPath: $0.resolvingSymlinksInPath().path)
        }) else {
            throw MiraBridgeError.executableMissing
        }
        return executable.resolvingSymlinksInPath()
    }

    /// Imports credentials the user previously configured with the normal
    /// OpenCode CLI. This is explicit opt-in; OpenCode Zen credentials are
    /// deliberately excluded so 321Doit never ships or restores its free
    /// model catalog as a default service.
    static func syncExistingProviderCredentials(language: AppLanguage = .system) throws -> String {
        let fm = FileManager.default
        let source = defaultOpenCodeCredentialURL()
        guard fm.isReadableFile(atPath: source.path) else {
            throw NSError(
                domain: "321Doit.Mira",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: L10n.t("未找到本机 OpenCode 登录信息。请先在终端运行 opencode auth login。", "No local OpenCode sign-in was found. Run opencode auth login in Terminal first.", language: language)]
            )
        }

        let destination = miraProviderCredentialURL()
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("auth-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: temporary) }
        try fm.copyItem(at: source, to: temporary)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try replaceFile(at: destination, with: temporary)
        NotificationCenter.default.post(name: .miraProviderCredentialsDidChange, object: nil)
        return L10n.t("已同步 OpenCode 登录信息；Mira 将重新连接并加载可用模型。", "OpenCode sign-in was synced. Mira will reconnect and load the available models.", language: language)
    }

    static func embeddedOpenCodeVersion(language: AppLanguage = .system) -> String {
        guard let resourceURL = Bundle.main.resourceURL else { return "—" }
        let executable = resourceURL.appendingPathComponent("Tools/opencode")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return L10n.t("未随 App 打包", "Not bundled with the app", language: language)
        }
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["--version"]
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return L10n.t("未知", "Unknown", language: language)
            }
            let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let version = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return version.isEmpty ? L10n.t("未知", "Unknown", language: language) : version
        } catch {
            return L10n.t("未知", "Unknown", language: language)
        }
    }

    private static func defaultOpenCodeCredentialURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/share/opencode/auth.json")
    }

    private static func miraProviderCredentialURL() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("321Doit/Mira/ProviderCredentials/auth.json")
    }

    private static func installProviderCredentials(in dataDirectory: URL) throws {
        let fm = FileManager.default
        let source = miraProviderCredentialURL()
        let destination = dataDirectory.appendingPathComponent("opencode/auth.json")
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var existing: [String: Any] = [:]
        if fm.isReadableFile(atPath: source.path),
           let data = try? Data(contentsOf: source),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existing = object
        }
        let credentials = mergedProviderCredentials(
            existing: existing,
            openCodeGoAPIKey: try MiraOpenCodeGoAPIKeyStore.read()
        )
        guard !credentials.isEmpty else {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            return
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent("auth-\(UUID().uuidString).json")
        defer { try? fm.removeItem(at: temporary) }
        let encoded = try JSONSerialization.data(withJSONObject: credentials, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: temporary, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        try replaceFile(at: destination, with: temporary)
    }

    /// Replace beside the destination so a failed update cannot delete the
    /// last known-good credential file first.
    private static func replaceFile(at destination: URL, with temporary: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            _ = try fm.replaceItemAt(
                destination,
                withItemAt: temporary,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } else {
            try fm.moveItem(at: temporary, to: destination)
        }
    }

    static func mergedProviderCredentials(
        existing: [String: Any],
        openCodeGoAPIKey: String?
    ) -> [String: Any] {
        var result = existing
        result.removeValue(forKey: "opencode")
        if let key = openCodeGoAPIKey?.trimmingCharacters(in: .whitespacesAndNewlines),
           !key.isEmpty {
            result["opencode-go"] = ["type": "api", "key": key]
        }
        return result
    }

    private struct RuntimePaths {
        let root: URL
        let workspace: URL
        let config: URL
        let data: URL
        let cache: URL
        let configuration: URL
        let providerEnvironment: [String: String]
    }

    private static func prepareRuntime(
        projectContext: MiraProjectContext?,
        modelID: String,
        authorizedRoots: [URL],
        executionPermissionMode: MiraExecutionPermissionMode
    ) throws -> RuntimePaths {
        let fm = FileManager.default
        let support = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("321Doit/Mira", isDirectory: true)
        let scope = projectContext?.id.uuidString.lowercased() ?? "unlinked"
        let workspace = root
            .appendingPathComponent("Workspaces", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        let data = root
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        let cache = root
            .appendingPathComponent("Cache", isDirectory: true)
            .appendingPathComponent(scope, isDirectory: true)
        let configuration = root.appendingPathComponent("Configuration", isDirectory: true)
        for directory in [root, workspace, data, cache, configuration] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try installProviderCredentials(in: data)

        let helper = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/321DoitMCP")
            .path
        var command = [helper]
        var seenRoots = Set<String>()
        let roots = (projectContext.map { [$0.folderURL] } ?? []) + authorizedRoots
        for root in roots.map({ $0.standardizedFileURL.resolvingSymlinksInPath() })
            where seenRoots.insert(root.path).inserted {
            command += ["--allow-root", root.path]
        }
        // Mira owns this store for the current project (or its unlinked
        // workspace). Other MCP clients get their own process-scoped stores.
        command += ["--task-store", data.appendingPathComponent("mcp-tasks.json").path]

        let readTools = [
            "321doit_workspace_list_projects",
            "321doit_project_read_snapshot",
            "321doit_production_plan_read_snapshot",
            "321doit_script_log_read_snapshot",
            "321doit_storyboard_read_snapshot",
            "321doit_storyboard_analyze",
            "321doit_storyboard_propose_patch",
            "321doit_storyboard_preview_patch",
            "321doit_offload_preflight",
            "321doit_media_probe",
            "321doit_media_conversion_preflight",
            "321doit_task_get_status"
        ]
        let writeTools = [
            "321doit_project_create",
            "321doit_project_update_metadata",
            "321doit_project_move_to_trash",
            "321doit_production_plan_upsert_call_sheet",
            "321doit_production_plan_export_call_sheet",
            "321doit_script_log_record_take",
            "321doit_script_log_export_report",
            "321doit_storyboard_apply_patch",
            "321doit_storyboard_undo_last_agent_change",
            "321doit_storyboard_write_scene",
            "321doit_offload_start",
            "321doit_media_conversion_start",
            "321doit_task_cancel"
        ]
        let persona = try loadPersona(at: bundledPersonaURL())
        let customProvider = try customProviderConfiguration()
        var permissions: [String: Any] = persona.permissions
        permissions["*"] = "deny"
        permissions["glob"] = "deny"
        permissions["grep"] = "deny"
        readTools.forEach { permissions[$0] = "allow" }
        writeTools.forEach {
            permissions[$0] = writePermissionValue(for: executionPermissionMode)
        }

        var configObject: [String: Any] = [
            "$schema": "https://opencode.ai/config.json",
            "autoupdate": false,
            "share": "disabled",
            "snapshot": false,
            "provider": customProvider.config,
            "mcp": [
                "321doit": [
                    "type": "local",
                    "command": command,
                    "enabled": true,
                    "timeout": 10_000
                ]
            ],
            "agent": [
                "mira": [
                    "description": persona.description,
                    "mode": persona.mode,
                    "temperature": persona.temperature,
                    "prompt": persona.instructions,
                    "permission": permissions
                ]
            ],
            "permission": permissions
        ]
        if !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            configObject["model"] = modelID
        }
        let config = root.appendingPathComponent("opencode.json")
        let dataValue = try JSONSerialization.data(withJSONObject: configObject, options: [.prettyPrinted, .sortedKeys])
        try dataValue.write(to: config, options: .atomic)
        return RuntimePaths(
            root: root,
            workspace: workspace,
            config: config,
            data: data,
            cache: cache,
            configuration: configuration,
            providerEnvironment: customProvider.environment
        )
    }

    static func writePermissionValue(for mode: MiraExecutionPermissionMode) -> String {
        mode == .automatic ? "allow" : "ask"
    }

    private static func customProviderConfiguration() throws -> (config: [String: Any], environment: [String: String]) {
        let service = MiraCustomModelServiceStore.load()
        guard service.isConfigured else { return ([:], [:]) }

        let providerID = service.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelID = service.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = service.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = service.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = service.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String: Any] = ["baseURL": baseURL]
        var environment: [String: String] = [:]
        if let key = try MiraCustomModelAPIKeyStore.read(), !key.isEmpty {
            options["apiKey"] = "{env:DOIT_MIRA_CUSTOM_API_KEY}"
            environment["DOIT_MIRA_CUSTOM_API_KEY"] = key
        }

        let configuration: [String: Any] = [
            providerID: [
                "npm": service.usesResponsesAPI ? "@ai-sdk/openai" : "@ai-sdk/openai-compatible",
                "name": displayName.isEmpty ? providerID : displayName,
                "options": options,
                "models": [
                    modelID: ["name": modelName.isEmpty ? modelID : modelName]
                ]
            ]
        ]
        return (configuration, environment)
    }

    private static func bundledPersonaURL() throws -> URL {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw MiraBridgeError.personaUnavailable
        }
        let url = resourceURL.appendingPathComponent("Mira/mira.md")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw MiraBridgeError.personaUnavailable
        }
        return url
    }

    static func loadPersona(at url: URL) throws -> MiraPersona {
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            throw MiraBridgeError.personaUnavailable
        }
        let lines = source.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
              }) else {
            throw MiraBridgeError.personaUnavailable
        }

        var metadata: [String: String] = [:]
        var permissions: [String: String] = [:]
        var isReadingPermissions = false
        for line in lines[1..<closingIndex] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if !line.hasPrefix(" ") && !line.hasPrefix("\t") {
                isReadingPermissions = key == "permission"
                if !isReadingPermissions { metadata[key] = value }
            } else if isReadingPermissions, !key.isEmpty, !value.isEmpty {
                permissions[key] = value
            }
        }

        let instructions = lines[lines.index(after: closingIndex)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let description = metadata["description"], !description.isEmpty,
              let mode = metadata["mode"], !mode.isEmpty,
              let temperatureText = metadata["temperature"],
              let temperature = Double(temperatureText),
              !permissions.isEmpty,
              !instructions.isEmpty else {
            throw MiraBridgeError.personaUnavailable
        }
        return MiraPersona(
            description: description,
            mode: mode,
            temperature: temperature,
            permissions: permissions,
            instructions: instructions
        )
    }

    private static func availableLoopbackPort() throws -> UInt16 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw MiraBridgeError.serviceUnavailable }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw MiraBridgeError.serviceUnavailable }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(descriptor, $0, &length)
            }
        }
        guard nameResult == 0 else { throw MiraBridgeError.serviceUnavailable }
        return UInt16(bigEndian: address.sin_port)
    }

    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()

    private static var supportsMira: Bool {
#if arch(arm64)
        true
#else
        false
#endif
    }
}
