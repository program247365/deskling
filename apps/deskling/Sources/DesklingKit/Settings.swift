import Foundation

public final class Settings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The app was called Clawd, under the bundle identifier `sh.kbr.clawd`. Its settings are copied
    /// across once, the first time Deskling runs. Launch at Login is not a setting and cannot come along.
    public static let previousDomain = "sh.kbr.clawd"

    static let importedKey = "importedPreviousSettings"
    static let importableKeys = [
        roamsKey, visitsLockScreenKey, "size", characterKey, "hasChosenCharacter", reactsToAgentsKey, alertsForAgentsKey,
    ]

    /// Copies settings from `previous` that this app has not set itself. Runs once; later launches do nothing.
    public func importPrevious(from previous: UserDefaults?) {
        guard !defaults.bool(forKey: Self.importedKey) else { return }
        defaults.set(true, forKey: Self.importedKey)
        guard let previous else { return }
        for key in Self.importableKeys where defaults.object(forKey: key) == nil {
            if let value = previous.object(forKey: key) { defaults.set(value, forKey: key) }
        }
    }

    /// Whether he may teleport around the screen. Off by default: he stays at the bottom.
    public var roams: Bool {
        get { defaults.bool(forKey: Self.roamsKey) }
        set { defaults.set(newValue, forKey: Self.roamsKey) }
    }

    /// The Settings window binds to this key directly.
    public static let roamsKey = "roams"

    /// Whether he follows you onto the lock screen. Off by default.
    public var visitsLockScreen: Bool {
        get { defaults.bool(forKey: Self.visitsLockScreenKey) }
        set { defaults.set(newValue, forKey: Self.visitsLockScreenKey) }
    }

    public static let visitsLockScreenKey = "visitsLockScreen"

    /// Which character lives on the desktop. Nil until one is chosen; the roster falls back to Clawd.
    public var characterID: String? {
        get { defaults.string(forKey: Self.characterKey) }
        set { defaults.set(newValue, forKey: Self.characterKey) }
    }

    public static let characterKey = "character"

    /// Whether the character picker has been shown once.
    public var hasChosenCharacter: Bool {
        get { defaults.bool(forKey: "hasChosenCharacter") }
        set { defaults.set(newValue, forKey: "hasChosenCharacter") }
    }

    /// Whether he acts out what coding agents are doing. On by default; nothing happens until the hook is installed.
    public var reactsToAgents: Bool {
        get { defaults.object(forKey: Self.reactsToAgentsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.reactsToAgentsKey) }
    }

    public static let reactsToAgentsKey = "reactsToAgents"

    /// Whether he comes to tell you when an agent is waiting on you. On by default.
    public var alertsForAgents: Bool {
        get { defaults.object(forKey: Self.alertsForAgentsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.alertsForAgentsKey) }
    }

    public static let alertsForAgentsKey = "alertsForAgents"

    /// Whether agents and scripts may have him say things and act on request (`deskling say`, the MCP server). On by default.
    public var agentsCanSpeak: Bool {
        get { defaults.object(forKey: Self.agentsCanSpeakKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.agentsCanSpeakKey) }
    }

    public static let agentsCanSpeakKey = "agentsCanSpeak"

    /// The version that ran last, so after an update they can tell you what you are on now.
    public var lastRunVersion: String? {
        get { defaults.string(forKey: "lastRunVersion") }
        set { defaults.set(newValue, forKey: "lastRunVersion") }
    }

    /// Sites an alert may open when you click it, as "https://host:4648", added the first time you choose Always Allow.
    public var allowedLinkSites: [String] {
        get { defaults.stringArray(forKey: "allowedLinkSites") ?? [] }
        set { defaults.set(newValue, forKey: "allowedLinkSites") }
    }

    public var size: CharacterSize {
        get { defaults.string(forKey: "size").flatMap(CharacterSize.init(rawValue:)) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "size") }
    }
}
