import Foundation

/// Something an agent asks the character to do on purpose. Unlike `AgentEvent`, which reports what an agent
/// is doing, this carries words the agent chose to show you.
public struct DesklingCommand: Equatable, Sendable {
    public enum Action: String, Sendable {
        /// A few words over his head, an act, or both.
        case say
        /// Come and wave with `text` until you answer or the same folder sends `clear`.
        case alert
        /// Stop waving for the alert this folder sent.
        case clear
    }

    public let action: Action
    /// What he says, tidied onto one short line.
    public let text: String?
    /// One of `roles`, for `say` only.
    public let role: String?
    /// The last component of the folder it came from: names the alert, and lets `clear` find it.
    public let project: String
    /// Where the sender runs, so clicking an alert can take you there. Only sent with `alert`.
    public var origin: AgentEvent.Origin?
    /// Who should bring an alert, by id or name, as in "nook": they come and stand beside the character who lives
    /// on the desktop instead of that one coming. Only sent with `alert`.
    public let character: String?
    /// A web page clicking the alert opens, as "https://host:4648/#/queue". Only http and https, and only sent with `alert`.
    public let open: URL?

    /// The agent name commands are filed under, as in "agent/api" for an alert sent from a folder named api.
    public static let agent = "agent"

    /// The roles an agent may ask for: the ones agent events already use, plus celebrating.
    /// Petting, napping, and waking belong to you and the clock.
    public static let roles = ["think", "type", "write", "browse", "search", "delegate", "compact", "celebrate"]

    /// The bubble is one line; longer text is cut short with an ellipsis.
    public static let longestText = 60

    /// Nil when there is nothing to do: `say` with no text and no known role, `alert` with no text.
    public init?(
        _ action: Action, text: String? = nil, role: String? = nil, project: String, origin: AgentEvent.Origin? = nil,
        character: String? = nil, open: String? = nil
    ) {
        let text = text.map(Self.tidy).flatMap { $0.isEmpty ? nil : $0 }
        let role = action == .say ? role?.lowercased() : nil
        switch action {
        case .say:
            if let role, !Self.roles.contains(role) { return nil }
            guard text != nil || role != nil else { return nil }
        case .alert:
            guard text != nil else { return nil }
        case .clear:
            break
        }
        self.action = action
        self.text = action == .clear ? nil : text
        self.role = role
        self.project = project.isEmpty ? "your agent" : project
        self.origin = action == .alert ? origin : nil
        let character = character?.trimmingCharacters(in: .whitespaces).lowercased()
        self.character = action == .alert && character?.isEmpty == false ? character : nil
        self.open = action == .alert ? Self.link(open) : nil
    }

    /// An http or https address with a host and no password in it; anything else is dropped.
    public static func link(_ string: String?) -> URL? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), string.count <= 2048,
              let url = URL(string: string), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false, url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    /// One line, no runs of spaces, at most `longestText` characters.
    static func tidy(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > longestText else { return line }
        return line.prefix(longestText - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The name the CLI posts on and the app listens for. `DESKLING_COMMAND_NAME` replaces it for tests.
    public static var notificationName: Notification.Name {
        Notification.Name(ProcessInfo.processInfo.environment["DESKLING_COMMAND_NAME"] ?? "sh.kbr.deskling.command")
    }

    public var userInfo: [String: String] {
        var info = ["action": action.rawValue, "project": project]
        info["text"] = text
        info["role"] = role
        info["character"] = character
        info["open"] = open?.absoluteString
        if let origin { info.merge(origin.userInfo) { mine, _ in mine } }
        return info
    }

    /// Anything can post this notification, so what arrives is checked again here.
    public init?(userInfo: [AnyHashable: Any]?) {
        guard let info = userInfo, let action = (info["action"] as? String).flatMap(Action.init(rawValue:)) else { return nil }
        self.init(action, text: info["text"] as? String, role: info["role"] as? String,
                  project: info["project"] as? String ?? "", origin: AgentEvent.Origin(userInfo: info),
                  character: info["character"] as? String, open: info["open"] as? String)
    }

    public func post() {
        DistributedNotificationCenter.default().postNotificationName(
            Self.notificationName, object: nil, userInfo: userInfo, deliverImmediately: true)
    }
}
