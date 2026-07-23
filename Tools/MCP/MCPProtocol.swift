import Foundation

typealias JSONObject = [String: Any]

enum MCPServerError: LocalizedError {
    case invalidRequest(String)
    case invalidArguments(String)
    case notFound(String)
    case forbidden(String)
    case conflict(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message),
             .invalidArguments(let message),
             .notFound(let message),
             .forbidden(let message),
             .conflict(let message),
             .unavailable(let message):
            return message
        }
    }
}

enum MCPJSON {
    static func object<T: Encodable>(from value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }

    static func dictionary<T: Encodable>(from value: T) throws -> JSONObject {
        guard let object = try object(from: value) as? JSONObject else {
            throw MCPServerError.unavailable("Could not serialize a structured result.")
        }
        return object
    }

    static func compactString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

final class MCPStdioRuntime {
    private let server: DoitMCPServer
    private var initialized = false

    init(server: DoitMCPServer) {
        self.server = server
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            handle(line)
        }
    }

    private func handle(_ line: String) {
        do {
            guard let data = line.data(using: .utf8),
                  let request = try JSONSerialization.jsonObject(with: data) as? JSONObject else {
                sendProtocolError(id: NSNull(), code: -32700, message: "Parse error")
                return
            }
            guard request["jsonrpc"] as? String == "2.0",
                  let method = request["method"] as? String else {
                sendProtocolError(id: request["id"] ?? NSNull(), code: -32600, message: "Invalid Request")
                return
            }

            let id = request["id"]
            let params = request["params"] as? JSONObject ?? [:]

            if id == nil {
                if method == "notifications/initialized" {
                    initialized = true
                }
                return
            }

            let result: JSONObject
            switch method {
            case "initialize":
                let requestedVersion = params["protocolVersion"] as? String
                result = server.initializeResult(requestedVersion: requestedVersion)
            case "ping":
                result = [:]
            case "tools/list":
                try requireInitialized()
                result = ["tools": server.toolDefinitions()]
            case "tools/call":
                try requireInitialized()
                guard let name = params["name"] as? String else {
                    throw MCPServerError.invalidArguments("tools/call requires a tool name.")
                }
                let arguments = params["arguments"] as? JSONObject ?? [:]
                result = server.callTool(name: name, arguments: arguments)
            case "resources/list":
                try requireInitialized()
                result = ["resources": server.resourceDefinitions()]
            case "resources/read":
                try requireInitialized()
                guard let uri = params["uri"] as? String else {
                    throw MCPServerError.invalidArguments("resources/read requires a URI.")
                }
                result = ["contents": [try server.readResource(uri: uri)]]
            case "resources/templates/list":
                try requireInitialized()
                result = ["resourceTemplates": []]
            default:
                sendProtocolError(id: id!, code: -32601, message: "Method not found: \(method)")
                return
            }
            sendResponse(id: id!, result: result)
        } catch let error as MCPServerError {
            if let requestData = line.data(using: .utf8),
               let request = try? JSONSerialization.jsonObject(with: requestData) as? JSONObject,
               let id = request["id"] {
                sendProtocolError(id: id, code: -32602, message: error.localizedDescription)
            }
        } catch {
            if let requestData = line.data(using: .utf8),
               let request = try? JSONSerialization.jsonObject(with: requestData) as? JSONObject,
               let id = request["id"] {
                sendProtocolError(id: id, code: -32603, message: error.localizedDescription)
            }
        }
    }

    private func requireInitialized() throws {
        guard initialized else {
            throw MCPServerError.invalidRequest("The MCP session has not completed initialization.")
        }
    }

    private func sendResponse(id: Any, result: JSONObject) {
        send(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func sendProtocolError(id: Any, code: Int, message: String) {
        send([
            "jsonrpc": "2.0",
            "id": id,
            "error": ["code": code, "message": message]
        ])
    }

    private func send(_ object: JSONObject) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return
        }
        var framed = data
        framed.append(0x0A)
        try? FileHandle.standardOutput.write(contentsOf: framed)
    }
}

