import Foundation

enum MiraTestFailure: Error {
    case failed(String)
}

@main
enum MiraSmokeTests {
    @MainActor
    static func main() throws {
        try testToolPartUsesStatePayload()
        try testQuestionRequestIsMappedForInteractiveReply()
        try testUserThinkTagIsPreserved()
        try testAssistantThinkTagIsSeparated()
        try testConnectedProviderModelsExposeReasoningVariants()
        try testExplicitCustomProviderAppearsWithoutOpenCodeLogin()
        try testOpenCodeGoCredentialMerge()
        try testExecutionPermissionModes()
        try testPersonaMarkdownIsTheConfigurationSource()
        print("321Doit Mira smoke tests passed")
    }

    @MainActor
    private static func testToolPartUsesStatePayload() throws {
        let messages = OpenCodeBridge.mapMessage([
            "info": ["id": "tool-message", "role": "assistant"],
            "parts": [[
                "type": "tool",
                "tool": "storyboard_write_scene",
                "state": [
                    "status": "error",
                    "input": ["scene_number": "12"],
                    "error": "The scene is locked"
                ]
            ]]
        ])
        guard let message = messages.first else {
            throw MiraTestFailure.failed("Tool part was not mapped")
        }
        try expect(message.toolStatus == "error", "Tool status must come from state")
        try expect(message.toolInput?.contains("scene_number") == true, "Tool input must come from state.input")
        try expect(message.toolOutput == "The scene is locked", "Tool failure reason must come from state.error")
    }

    @MainActor
    private static func testQuestionRequestIsMappedForInteractiveReply() throws {
        let request = OpenCodeBridge.mapQuestionRequest([
            "id": "question-1",
            "sessionID": "session-1",
            "questions": [[
                "header": "确认创建项目",
                "question": "是否需要补充导演、制片等信息？",
                "options": [
                    ["label": "直接创建", "description": "项目只有名称"],
                    ["label": "补充信息", "description": "添加导演和制片信息"]
                ],
                "multiple": false,
                "custom": true
            ]]
        ])
        guard let request, let question = request.questions.first else {
            throw MiraTestFailure.failed("Question request was not mapped")
        }
        try expect(request.id == "question-1", "Question request ID was not preserved")
        try expect(request.sessionID == "session-1", "Question request session was not preserved")
        try expect(question.header == "确认创建项目", "Question header was not preserved")
        try expect(question.options.map(\.label) == ["直接创建", "补充信息"], "Question options were not preserved")
        try expect(question.allowsCustomAnswer, "Question custom-answer capability was not preserved")
        try expect(!question.allowsMultipleSelection, "Question selection mode was not preserved")

        let toolMessage = OpenCodeBridge.mapMessage([
            "info": ["id": "question-tool", "role": "assistant"],
            "parts": [["type": "tool", "tool": "question", "state": ["status": "running"]]]
        ]).first
        try expect(toolMessage?.text == "等待你的选择", "Question tools must have a user-facing status")
    }

    @MainActor
    private static func testUserThinkTagIsPreserved() throws {
        let text = "请原样显示 <think>这是示例</think>"
        let messages = OpenCodeBridge.mapMessage([
            "info": ["id": "user-message", "role": "user"],
            "parts": [["type": "text", "text": text]]
        ])
        try expect(messages.count == 1, "User message must not be split into thinking content")
        try expect(messages.first?.role == .user, "User role must be preserved")
        try expect(messages.first?.text == text, "User text must be preserved exactly")
    }

    @MainActor
    private static func testAssistantThinkTagIsSeparated() throws {
        let messages = OpenCodeBridge.mapMessage([
            "info": ["id": "assistant-message", "role": "assistant"],
            "parts": [["type": "text", "text": "<think>检查项目</think>准备好了。"]]
        ])
        try expect(messages.map(\.role) == [.thinking, .assistant], "Assistant thinking must remain separate from the reply")
        try expect(messages.map(\.text) == ["检查项目", "准备好了。"], "Assistant thinking parser returned incorrect text")
    }

    @MainActor
    private static func testConnectedProviderModelsExposeReasoningVariants() throws {
        let models = OpenCodeBridge.modelOptions(from: [
            "connected": ["openai"],
            "all": [[
                "id": "openai",
                "name": "OpenAI",
                "models": [
                    "gpt-5": [
                        "name": "GPT-5",
                        "cost": ["input": 1, "output": 2],
                        "variants": ["low": [:], "high": [:], "xhigh": [:]]
                    ]
                ]
            ]]
        ])
        guard let model = models.first else {
            throw MiraTestFailure.failed("Connected provider model was not discovered")
        }
        try expect(model.id == "openai/gpt-5", "Model ID must include the connected provider")
        try expect(model.providerName == "OpenAI", "Provider display name was not preserved")
        try expect(model.variants.map(\.id) == ["high", "low", "xhigh"], "Model reasoning variants were not preserved")
    }

    @MainActor
    private static func testExplicitCustomProviderAppearsWithoutOpenCodeLogin() throws {
        let models = OpenCodeBridge.modelOptions(
            from: [
                "connected": ["opencode"],
                "all": [[
                    "id": "my-provider",
                    "name": "我的 API",
                    "models": ["filmmaker-1": ["name": "Filmmaker 1"]]
                ]]
            ],
            explicitlyConfiguredProviders: ["my-provider"]
        )
        try expect(models.map(\.id) == ["my-provider/filmmaker-1"], "Explicit custom API provider must be selectable without OpenCode auth")
    }

    @MainActor
    private static func testOpenCodeGoCredentialMerge() throws {
        let merged = OpenCodeBridge.mergedProviderCredentials(
            existing: ["anthropic": ["type": "api", "key": "existing"]],
            openCodeGoAPIKey: "go-test-key"
        )
        let credential = merged["opencode-go"] as? [String: String]
        try expect(credential?["type"] == "api", "OpenCode Go credential must use OpenCode's API auth format")
        try expect(credential?["key"] == "go-test-key", "OpenCode Go API key was not installed")
        try expect(merged["anthropic"] != nil, "Installing a Go key must preserve synced provider credentials")
    }

    @MainActor
    private static func testExecutionPermissionModes() throws {
        try expect(
            OpenCodeBridge.writePermissionValue(for: .automatic) == "allow",
            "Automatic mode must allow 321Doit write tools"
        )
        try expect(
            OpenCodeBridge.writePermissionValue(for: .confirmEveryWrite) == "ask",
            "Confirm-every-write mode must request permission"
        )
    }

    @MainActor
    private static func testPersonaMarkdownIsTheConfigurationSource() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mira-persona-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: url) }
        let source = """
        ---
        description: 测试人设
        mode: primary
        temperature: 0.3
        permission:
          read: deny
          question: allow
        ---

        这段文字必须成为 Mira 的唯一运行时人设。
        """
        try source.write(to: url, atomically: true, encoding: .utf8)

        let persona = try OpenCodeBridge.loadPersona(at: url)
        try expect(persona.description == "测试人设", "Persona description must come from mira.md")
        try expect(persona.mode == "primary", "Persona mode must come from mira.md")
        try expect(persona.temperature == 0.3, "Persona temperature must come from mira.md")
        try expect(persona.permissions == ["read": "deny", "question": "allow"], "Persona permissions must come from mira.md")
        try expect(persona.instructions == "这段文字必须成为 Mira 的唯一运行时人设。", "Persona instructions must come from mira.md")
    }

    private static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw MiraTestFailure.failed(message) }
    }
}
