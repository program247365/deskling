import AppKit
import DesklingEvents

// Shipped as Deskling.app/Contents/Helpers/deskling. Built as `deskling-cli`, because on a case-insensitive disk
// a `deskling` product would overwrite the `Deskling` app binary in .build.
//
// Lets you, a script, or an agent have the Deskling say something, act something out, or come and get you.

let usage = """
    Usage:
      deskling say TEXT [--as ROLE]    say TEXT in a bubble, acting out ROLE if given
      deskling act ROLE [--say TEXT]   act out ROLE, saying TEXT if given
      deskling alert TEXT [--character NAME] [--open URL]
                                       come and wave with TEXT until you answer or `deskling clear`;
                                       NAME, if given, comes instead and stands beside whoever is out;
                                       URL (http or https), if given, opens when you click them
      deskling clear                   stop waving for the alert sent from this folder
      deskling mcp                     run as an MCP server over stdio, with the same four as tools

    Roles: \(DesklingCommand.roles.joined(separator: ", "))
    Text is cut to one line of \(DesklingCommand.longestText) characters. Words said within \
    a few seconds of the last are dropped.
    An alert belongs to the folder it was sent from; --project NAME names it instead.
    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Splits `--flag value` off the arguments.
func option(_ flag: String, in arguments: inout [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    guard index + 1 < arguments.count else { fail("\(flag) needs a value.\n\n\(usage)") }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...index + 1)
    return value
}

/// Tests post on a private name (`DESKLING_COMMAND_NAME`) that no Deskling listens on, so there is nothing to look for.
var isDesklingRunning: Bool {
    ProcessInfo.processInfo.environment["DESKLING_COMMAND_NAME"] != nil
        || !NSRunningApplication.runningApplications(withBundleIdentifier: "sh.kbr.deskling").isEmpty
}

let currentFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).lastPathComponent

enum CommandError: Error, CustomStringConvertible {
    case unknownRole(String), nothingToDo(DesklingCommand.Action), notRunning

    var description: String {
        switch self {
        case let .unknownRole(role): "Unknown role \"\(role)\". Roles: \(DesklingCommand.roles.joined(separator: ", "))"
        case .nothingToDo(.alert): "An alert needs some text."
        case .nothingToDo: "Nothing to say or act out."
        case .notRunning: "Deskling isn't running."
        }
    }
}

/// Posts the command, or says why it could not.
func send(
    _ action: DesklingCommand.Action, text: String? = nil, role: String? = nil, project: String?, character: String? = nil,
    open: String? = nil
) -> Result<DesklingCommand, CommandError> {
    if let role, !DesklingCommand.roles.contains(role.lowercased()) { return .failure(.unknownRole(role)) }
    guard let command = DesklingCommand(
        action, text: text, role: role, project: project ?? currentFolder,
        origin: action == .alert ? .current() : nil, character: character, open: open)
    else { return .failure(.nothingToDo(action)) }
    guard isDesklingRunning else { return .failure(.notRunning) }
    command.post()
    return .success(command)
}

// MARK: MCP

/// Newline-delimited JSON-RPC 2.0 over stdio, the MCP stdio transport. Only what a tools-only server needs.
enum MCPServer {
    static let roleSchema: [String: Any] = [
        "type": "string", "enum": DesklingCommand.roles,
        "description": "An act to play: think, type, write, browse, search, delegate, compact, or celebrate.",
    ]
    static let textSchema: [String: Any] = [
        "type": "string",
        "description": "A few words for the speech bubble. One line; cut to \(DesklingCommand.longestText) characters.",
    ]

    static let characterSchema: [String: Any] = [
        "type": "string",
        "description": "Optional. A Deskling character to bring the alert, by name or id (for example nook): they drop in beside the user's own character instead of it coming. Leave out to use the user's own character.",
    ]

    static func schema(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    static let tools: [[String: Any]] = [
        [
            "name": "say",
            "description": "Show a short message in a speech bubble over the Deskling, the pixel character on the user's Mac desktop, optionally acting out a role. Use it sparingly, for things worth a glance: a long task finished, a milestone. Messages sent within a few seconds of the last are dropped, and none show while the user is being alerted.",
            "inputSchema": schema(["text": textSchema, "role": roleSchema], required: ["text"]),
        ],
        [
            "name": "act",
            "description": "Have the Deskling, the pixel character on the user's Mac desktop, act out a role (for example celebrate when something works), optionally with a short message.",
            "inputSchema": schema(["role": roleSchema, "text": textSchema], required: ["role"]),
        ],
        [
            "name": "alert",
            "description": "Have the Deskling come to the middle of the user's screen and wave with a message until they respond. Clicking it takes them to this agent's terminal. Only for when you are blocked on the user; call clear once they have answered, if your own hooks do not already tell Deskling.",
            "inputSchema": schema(["text": textSchema, "character": characterSchema], required: ["text"]),
        ],
        [
            "name": "clear",
            "description": "Stop the Deskling waving for the alert this agent sent.",
            "inputSchema": schema([:], required: []),
        ],
    ]

    static func run() {
        while let line = readLine() {
            guard !line.isEmpty else { continue }
            guard let request = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
                write(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            // Notifications have no id and get no reply.
            guard let id = request["id"] else { continue }
            write(reply(to: request["method"] as? String, params: request["params"] as? [String: Any] ?? [:], id: id))
        }
    }

    static func reply(to method: String?, params: [String: Any], id: Any) -> [String: Any] {
        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "deskling", "version": "1"],
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": tools]
        case "tools/call":
            result = call(params["name"] as? String, arguments: params["arguments"] as? [String: Any] ?? [:])
        default:
            return ["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method ?? "")"]]
        }
        return ["jsonrpc": "2.0", "id": id, "result": result]
    }

    static func call(_ name: String?, arguments: [String: Any]) -> [String: Any] {
        let text = arguments["text"] as? String
        let role = arguments["role"] as? String
        let sent: Result<DesklingCommand, CommandError>
        switch name {
        case "say", "act": sent = send(.say, text: text, role: role, project: nil)
        case "alert": sent = send(.alert, text: text, project: nil, character: arguments["character"] as? String)
        case "clear": sent = send(.clear, project: nil)
        default: return toolResult("Unknown tool \(name ?? "").", isError: true)
        }
        switch sent {
        case let .success(command): return toolResult(summary(of: command), isError: false)
        case let .failure(error): return toolResult(error.description, isError: true)
        }
    }

    static func summary(of command: DesklingCommand) -> String {
        switch (command.action, command.text, command.role) {
        case let (.alert, text?, _): "Alerting the user\(command.character.map { " as \($0)" } ?? ""): \"\(text)\"."
        case (.clear, _, _): "Cleared."
        case let (_, text?, role?): "Sent: act out \(role), saying \"\(text)\"."
        case let (_, text?, nil): "Sent: \"\(text)\"."
        case let (_, nil, role?): "Sent: act out \(role)."
        default: "Sent."
        }
    }

    static func toolResult(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    static func write(_ message: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}

// MARK: Main

var arguments = Array(CommandLine.arguments.dropFirst())
let subcommand = arguments.isEmpty ? nil : arguments.removeFirst()
let project = option("--project", in: &arguments)
let sent: Result<DesklingCommand, CommandError>

switch subcommand {
case "say":
    let role = option("--as", in: &arguments)
    sent = send(.say, text: arguments.joined(separator: " "), role: role, project: project)
case "act":
    let text = option("--say", in: &arguments)
    guard arguments.count == 1 else { fail(usage) }
    sent = send(.say, text: text, role: arguments[0], project: project)
case "alert":
    let character = option("--character", in: &arguments)
    let link = option("--open", in: &arguments)
    if let link, DesklingCommand.link(link) == nil { fail("--open takes an http or https URL.") }
    sent = send(.alert, text: arguments.joined(separator: " "), project: project, character: character, open: link)
case "clear":
    guard arguments.isEmpty else { fail(usage) }
    sent = send(.clear, project: project)
case "mcp":
    MCPServer.run()
    exit(0)
case "-h", "--help", "help":
    print(usage)
    exit(0)
default:
    fail(usage)
}
if case let .failure(error) = sent { fail(error.description) }
