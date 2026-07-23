import Foundation

private func configuredRoots() -> [URL] {
    var paths: [String] = []
    var index = 1
    while index < CommandLine.arguments.count {
        let argument = CommandLine.arguments[index]
        if argument == "--allow-root", index + 1 < CommandLine.arguments.count {
            paths.append(CommandLine.arguments[index + 1])
            index += 2
            continue
        }
        index += 1
    }

    if let environment = ProcessInfo.processInfo.environment["DOIT_MCP_ALLOWED_ROOTS"] {
        paths += environment
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
    return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
}

private func configuredTaskStore() -> URL? {
    var index = 1
    while index < CommandLine.arguments.count {
        if CommandLine.arguments[index] == "--task-store", index + 1 < CommandLine.arguments.count {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        index += 1
    }
    return nil
}

let server = DoitMCPServer(
    allowedRoots: configuredRoots(),
    executionCoordinator: MCPExecutionCoordinator(persistenceURL: configuredTaskStore())
)
MCPStdioRuntime(server: server).run()
