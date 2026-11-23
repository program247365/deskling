import DesklingEvents
import Foundation

/// What the character should do about an agent event.
public enum AgentReaction: Equatable {
    /// Play an act for this role, optionally with a few words over his head.
    case perform(Role, saying: String?)
    /// Say a few words where he stands, with no act to go with them.
    case speak(String)
    /// Come and wave until it is cleared. Replaces any alert already showing.
    case alert(String)
    case clearAlert
}

/// One agent session that is waiting on you.
public struct WaitingSession: Equatable, Identifiable {
    /// The agent and session, e.g. "claude/0b1c…".
    public let id: String
    public let agent: String
    public let project: String
    public let since: Date
    /// Where it runs, if the hook could tell.
    public var origin: AgentEvent.Origin? = nil
    /// What the agent asked him to say, for an alert sent with `deskling alert`.
    public var message: String? = nil
    /// The page clicking him opens, for an alert sent with `deskling alert --open`.
    public var link: URL? = nil

    /// "Claude Code", "Codex", or the agent's own name.
    public var agentName: String {
        switch agent {
        case "claude": "Claude Code"
        case "codex": "Codex"
        case DesklingCommand.agent: "Agent"
        default: agent.prefix(1).uppercased() + agent.dropFirst()
        }
    }

    /// "Claude Code · api · 3 min": the minutes tell apart two sessions in the same folder.
    public func menuTitle(at now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(since) / 60)
        let waited = switch minutes {
        case ..<1: "just now"
        case ..<60: "\(minutes) min"
        default: "\(minutes / 60) hr"
        }
        return "\(agentName) · \(project) · \(waited)"
    }
}

/// Keeps track of which agent sessions are waiting on you and turns events into reactions,
/// sparingly: a character that acts out every tool call is noise.
public struct AgentDesk {
    /// Shortest gap between two ambient acts.
    public static let ambientGap: TimeInterval = 45
    /// Shortest gap between two celebrations.
    public static let celebrateGap: TimeInterval = 10

    /// Shortest gap between two things agents ask him to say; any sooner and they are dropped, so a chatty agent cannot keep him talking.
    public static let commandGap: TimeInterval = 4

    /// The bubble names the waiting projects when they fit in this many characters, and counts them otherwise.
    public static let longestNamedMessage = 30

    /// The sessions waiting on you, longest-waiting first.
    public private(set) var waiting: [WaitingSession] = []
    private var lastAmbient: Date?
    private var lastCelebration: Date?
    private var lastSaid: Date?

    public init() {}

    public mutating func handle(_ event: AgentEvent, at now: Date, ambient: Bool = true, alerts: Bool = true) -> [AgentReaction] {
        let key = "\(event.agent)/\(event.session)"
        var reactions: [AgentReaction] = []

        if event.kind == .needsInput {
            guard alerts else { return [] }
            // Asking again keeps its place in line.
            if !waiting.contains(where: { $0.id == key }) {
                waiting.append(WaitingSession(id: key, agent: event.agent, project: event.project, since: now, origin: event.origin))
            }
            return [.alert(alertMessage)]
        }

        // Anything else from a waiting session means you answered it.
        if let answered = dismiss(key) { reactions.append(answered) }
        // So does a new prompt in the folder an agent sent `deskling alert` from, in case it never sends `clear`.
        if event.kind == .promptSubmitted, let answered = dismiss("\(DesklingCommand.agent)/\(event.project)") {
            reactions.append(answered)
        }
        // While someone is waiting, he stays put and keeps waving.
        guard waiting.isEmpty else { return reactions }

        if event.kind == .finished {
            if lastCelebration.map({ now.timeIntervalSince($0) >= Self.celebrateGap }) ?? true {
                lastCelebration = now
                reactions.append(.perform(.celebrate, saying: "\(event.project) is done"))
            }
            return reactions
        }

        guard ambient, let role = Self.role(for: event),
              lastAmbient.map({ now.timeIntervalSince($0) >= Self.ambientGap }) ?? true
        else { return reactions }
        lastAmbient = now
        reactions.append(.perform(role, saying: nil))
        return reactions
    }

    /// Something an agent asked for on purpose. `speaks` is whether agents may speak through him at all;
    /// `alerts` whether he may come and tell you things.
    public mutating func handle(_ command: DesklingCommand, at now: Date, speaks: Bool = true, alerts: Bool = true) -> [AgentReaction] {
        let key = "\(DesklingCommand.agent)/\(command.project)"
        switch command.action {
        case .say:
            guard speaks, waiting.isEmpty,
                  lastSaid.map({ now.timeIntervalSince($0) >= Self.commandGap }) ?? true
            else { return [] }
            lastSaid = now
            if let role = command.role.flatMap(Role.init(rawValue:)) { return [.perform(role, saying: command.text)] }
            return command.text.map { [.speak($0)] } ?? []
        case .alert:
            guard speaks, alerts, let text = command.text else { return [] }
            if let index = waiting.firstIndex(where: { $0.id == key }) {
                waiting[index].message = text
                if let origin = command.origin { waiting[index].origin = origin }
                if let link = command.open { waiting[index].link = link }
            } else {
                waiting.append(WaitingSession(
                    id: key, agent: DesklingCommand.agent, project: command.project, since: now,
                    origin: command.origin, message: text, link: command.open))
            }
            return [.alert(alertMessage)]
        case .clear:
            return dismiss(key).map { [$0] } ?? []
        }
    }

    /// Forgets every waiting session, as when you dismiss them all from the menu.
    public mutating func dismissAll() {
        waiting.removeAll()
    }

    /// Forgets one waiting session. Nil if it was not waiting; otherwise the alert as it now stands.
    public mutating func dismiss(_ id: String) -> AgentReaction? {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return nil }
        waiting.remove(at: index)
        return waiting.isEmpty ? .clearAlert : .alert(alertMessage)
    }

    /// "api needs you", "api and clawd need you", or "3 agents need you" when names would not fit.
    public var alertMessage: String {
        let projects = waiting.map(\.project)
        switch projects.count {
        case 0:
            return ""
        case 1:
            return waiting[0].message ?? "\(projects[0]) needs you"
        case 2 where projects[0] != projects[1]:
            let named = "\(projects[0]) and \(projects[1]) need you"
            if named.count <= Self.longestNamedMessage { return named }
            fallthrough
        default:
            return "\(projects.count) agents need you"
        }
    }

    static func role(for event: AgentEvent) -> Role? {
        switch event.kind {
        case .promptSubmitted: return .think
        case .compacting: return .compact
        case .toolStarted:
            switch event.tool {
            case "Bash", "BashOutput", "shell", "exec_command": return .type
            case "Edit", "MultiEdit", "Write", "NotebookEdit", "TodoWrite", "apply_patch": return .write
            case "WebFetch", "WebSearch": return .browse
            case "Read", "Grep", "Glob", "LS": return .search
            case "Task", "Agent": return .delegate
            default: return nil
            }
        default: return nil
        }
    }
}
