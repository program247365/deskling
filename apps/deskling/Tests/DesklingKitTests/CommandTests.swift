import DesklingEvents
@testable import DesklingKit
import XCTest

final class CommandTests: XCTestCase {
    func testTextIsTidiedOntoOneShortLine() throws {
        XCTAssertEqual(DesklingCommand(.say, text: "  tests\n  pass  ", project: "api")?.text, "tests pass")
        let long = try XCTUnwrap(DesklingCommand(.say, text: String(repeating: "a", count: 200), project: "api")?.text)
        XCTAssertEqual(long.count, DesklingCommand.longestText)
        XCTAssertTrue(long.hasSuffix("…"))
    }

    func testNeedsSomethingToDoAndAKnownRole() {
        XCTAssertNil(DesklingCommand(.say, text: "   ", project: "api"))
        XCTAssertNil(DesklingCommand(.say, project: "api"))
        XCTAssertNil(DesklingCommand(.say, text: "hi", role: "pet", project: "api"), "petting is yours, not an agent's")
        XCTAssertEqual(DesklingCommand(.say, role: "Celebrate", project: "api")?.role, "celebrate")
        XCTAssertNil(DesklingCommand(.alert, project: "api"), "an alert needs words")
        XCTAssertNotNil(DesklingCommand(.clear, project: "api"))
    }

    func testEveryRoleAnAgentMayAskForIsARealRole() {
        for role in DesklingCommand.roles { XCTAssertNotNil(Role(rawValue: role), role) }
    }

    func testRoundTripsThroughUserInfo() {
        let said = DesklingCommand(.say, text: "shipped", role: "celebrate", project: "api")
        XCTAssertEqual(DesklingCommand(userInfo: said?.userInfo), said)
        let alert = DesklingCommand(
            .alert, text: "review the plan", project: "api",
            origin: AgentEvent.Origin(processes: [42, 7], bundleID: "com.apple.Terminal", tty: "/dev/ttys003"))
        XCTAssertEqual(DesklingCommand(userInfo: alert?.userInfo), alert)
        let visitor = DesklingCommand(.alert, text: "3 notes waiting", project: "littlebear", character: " Nook ")
        XCTAssertEqual(visitor?.character, "nook")
        XCTAssertEqual(DesklingCommand(userInfo: visitor?.userInfo), visitor)
        XCTAssertNil(DesklingCommand(.say, text: "hi", project: "api", character: "nook")?.character, "only an alert brings a visitor")
        XCTAssertNil(DesklingCommand(userInfo: ["action": "say", "role": "nap"]))
        XCTAssertNil(DesklingCommand(userInfo: ["action": "explode"]))
    }

    func testAnAlertOpensOnlyAPlainWebAddress() {
        let open = { DesklingCommand(.alert, text: "hi", project: "littlebear", open: $0)?.open?.absoluteString }
        XCTAssertEqual(open("https://kmini-home.example.ts.net:4648/#/queue"), "https://kmini-home.example.ts.net:4648/#/queue")
        XCTAssertEqual(open("http://127.0.0.1:4648"), "http://127.0.0.1:4648")
        XCTAssertNil(open("file:///etc/passwd"))
        XCTAssertNil(open("x-apple.systempreferences:com.apple.preference.security"))
        XCTAssertNil(open("javascript:alert(1)"))
        XCTAssertNil(open("https://user:secret@example.com/"))
        XCTAssertNil(open("https:///no-host"))
        XCTAssertNil(open("not a url"))
        XCTAssertNil(DesklingCommand(.say, text: "hi", project: "api", open: "https://example.com")?.open, "only an alert opens a page")
        let alert = DesklingCommand(.alert, text: "hi", project: "littlebear", character: "nook", open: "https://example.com:4648/")
        XCTAssertEqual(DesklingCommand(userInfo: alert?.userInfo), alert)
        XCTAssertNil(DesklingCommand(userInfo: ["action": "alert", "text": "hi", "project": "x", "open": "file:///tmp"])?.open)
    }

    // MARK: The deskling binary

    private var binary: URL {
        URL(fileURLWithPath: "\(#filePath)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".build/debug/deskling-cli")
    }

    /// Runs the binary with a private notification name, so a Deskling running on this Mac hears nothing.
    private func run(_ arguments: [String], input: String = "", channel: String) throws -> (status: Int32, output: String) {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: binary.path), "run swift build first")
        let process = Process()
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ["DESKLING_COMMAND_NAME": channel]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: output, as: UTF8.self))
    }

    func testSayPostsTheCommand() throws {
        let channel = "sh.kbr.deskling.tests.\(UUID().uuidString)"
        let received = expectation(description: "command posted")
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(channel), object: nil, queue: .main
        ) { notification in
            XCTAssertEqual(
                DesklingCommand(userInfo: notification.userInfo),
                DesklingCommand(.say, text: "tests pass", role: "celebrate", project: "web"))
            received.fulfill()
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        let result = try run(["say", "tests", "pass", "--as", "celebrate", "--project", "web"], channel: channel)
        XCTAssertEqual(result.status, 0)
        wait(for: [received], timeout: 3)
    }

    func testUnknownRolesAndMissingTextFail() throws {
        let channel = "sh.kbr.deskling.tests.\(UUID().uuidString)"
        XCTAssertEqual(try run(["act", "pet"], channel: channel).status, 1)
        XCTAssertEqual(try run(["say"], channel: channel).status, 1)
        XCTAssertEqual(try run(["alert"], channel: channel).status, 1)
        XCTAssertEqual(try run(["alert", "hi", "--open", "file:///etc/passwd"], channel: channel).status, 1)
        XCTAssertEqual(try run([], channel: channel).status, 1)
    }

    func testAlertCarriesTheCharacterAndPageToOpen() throws {
        let channel = "sh.kbr.deskling.tests.\(UUID().uuidString)"
        let received = expectation(description: "command posted")
        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(channel), object: nil, queue: .main
        ) { notification in
            let command = DesklingCommand(userInfo: notification.userInfo)
            XCTAssertEqual(command?.character, "nook")
            XCTAssertEqual(command?.open?.absoluteString, "https://kmini.example:4648/#/queue")
            received.fulfill()
        }
        defer { DistributedNotificationCenter.default().removeObserver(observer) }

        let result = try run(
            ["alert", "3 notes", "--character", "nook", "--open", "https://kmini.example:4648/#/queue", "--project", "littlebear"],
            channel: channel)
        XCTAssertEqual(result.status, 0)
        wait(for: [received], timeout: 3)
    }

    func testMCPServerListsAndCallsItsTools() throws {
        let lines = [
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
            #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"say","arguments":{"text":"hello"}}}"#,
            #"{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"act","arguments":{"role":"nap"}}}"#,
            #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"alert","arguments":{"text":"need you"}}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"clear","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"alert","arguments":{"text":"notes waiting","character":"Nook"}}}"#,
        ]
        let result = try run(["mcp"], input: lines.joined(separator: "\n") + "\n", channel: "sh.kbr.deskling.tests.\(UUID().uuidString)")
        let replies = try result.output.split(separator: "\n").map {
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any])
        }
        XCTAssertEqual(replies.map { $0["id"] as? Int }, [1, 2, 3, 4, 5, 6, 7, 8], "the notification gets no reply")

        let initialized = try XCTUnwrap(replies[0]["result"] as? [String: Any])
        XCTAssertEqual(initialized["protocolVersion"] as? String, "2025-06-18")
        let tools = try XCTUnwrap((replies[1]["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.compactMap { $0["name"] as? String }, ["say", "act", "alert", "clear"])
        XCTAssertEqual((replies[2]["result"] as? [String: Any])?["isError"] as? Bool, false)
        XCTAssertEqual((replies[3]["result"] as? [String: Any])?["isError"] as? Bool, true)
        XCTAssertEqual((replies[4]["error"] as? [String: Any])?["code"] as? Int, -32601)
        XCTAssertEqual((replies[5]["result"] as? [String: Any])?["isError"] as? Bool, false)
        XCTAssertEqual((replies[6]["result"] as? [String: Any])?["isError"] as? Bool, false)

        let alert = try XCTUnwrap(tools.first { $0["name"] as? String == "alert" })
        let properties = try XCTUnwrap((alert["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        XCTAssertNotNil(properties["character"], "an agent can ask for a visitor")
        let visited = try XCTUnwrap(replies[7]["result"] as? [String: Any])
        XCTAssertEqual(visited["isError"] as? Bool, false)
        let said = try XCTUnwrap((visited["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertEqual(said, "Alerting the user as nook: \"notes waiting\".")
    }
}

final class CommandDeskTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func command(_ action: DesklingCommand.Action, _ text: String? = nil, role: String? = nil, project: String = "api") -> DesklingCommand {
        DesklingCommand(action, text: text, role: role, project: project)!
    }

    func testSayingIsThrottledSoAChattyAgentCannotKeepHimTalking() {
        var desk = AgentDesk()
        XCTAssertEqual(desk.handle(command(.say, "one"), at: start), [.speak("one")])
        XCTAssertEqual(desk.handle(command(.say, "two"), at: start.addingTimeInterval(1)), [])
        XCTAssertEqual(
            desk.handle(command(.say, "three", role: "celebrate"), at: start.addingTimeInterval(AgentDesk.commandGap)),
            [.perform(.celebrate, saying: "three")])
    }

    func testSettingsSilenceCommands() {
        var desk = AgentDesk()
        XCTAssertEqual(desk.handle(command(.say, "hi"), at: start, speaks: false), [])
        XCTAssertEqual(desk.handle(command(.alert, "come"), at: start, speaks: false), [])
        XCTAssertEqual(desk.handle(command(.alert, "come"), at: start, alerts: false), [])
        XCTAssertTrue(desk.waiting.isEmpty)
    }

    func testAnAlertWavesWithItsOwnWordsUntilClearedFromTheSameFolder() {
        var desk = AgentDesk()
        XCTAssertEqual(desk.handle(command(.alert, "review the plan"), at: start), [.alert("review the plan")])
        XCTAssertEqual(desk.waiting.first?.menuTitle(at: start), "Agent · api · just now")
        XCTAssertEqual(desk.handle(command(.say, "busy"), at: start), [], "nothing else is said while he waves")
        XCTAssertEqual(desk.handle(command(.clear, project: "web"), at: start), [], "another folder's clear is not this one's")
        XCTAssertEqual(desk.handle(command(.alert, "still need you"), at: start), [.alert("still need you")], "asking again updates the words")
        XCTAssertEqual(desk.waiting.count, 1)
        XCTAssertEqual(desk.handle(command(.clear), at: start), [.clearAlert])
    }

    func testANewPromptInTheSameFolderAnswersAnAlert() {
        var desk = AgentDesk()
        _ = desk.handle(command(.alert, "review the plan"), at: start)
        _ = desk.handle(AgentEvent(agent: "claude", kind: .promptSubmitted, session: "s1", project: "web"), at: start)
        XCTAssertEqual(desk.waiting.count, 1, "a prompt somewhere else is not an answer")
        let reactions = desk.handle(AgentEvent(agent: "claude", kind: .promptSubmitted, session: "s1", project: "api"), at: start)
        XCTAssertEqual(reactions.first, .clearAlert)
        XCTAssertTrue(desk.waiting.isEmpty)
    }

    func testAnAlertJoinsAgentsAlreadyWaiting() {
        var desk = AgentDesk()
        _ = desk.handle(AgentEvent(agent: "claude", kind: .needsInput, session: "s1", project: "web"), at: start)
        XCTAssertEqual(desk.handle(command(.alert, "review the plan"), at: start), [.alert("web and api need you")])
        XCTAssertEqual(desk.handle(AgentEvent(agent: "claude", kind: .toolFinished, session: "s1", project: "web"), at: start),
                       [.alert("review the plan")])
    }
}

@MainActor
final class SpeakingTests: XCTestCase {
    func testHeSaysWhatAnAgentAsksUnlessSpeakingIsOff() async {
        let defaults = UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        let bubble = SpeechBubble()
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, bubble: bubble, settings: settings,
            visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop(); bubble.hide() }
        let agents = AgentListener(performer: performer, settings: settings)
        performer.start()

        settings.agentsCanSpeak = false
        agents.handle(DesklingCommand(.say, text: "muted", project: "api")!)
        try? await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(bubble.isVisible && bubble.text == "muted")

        settings.agentsCanSpeak = true
        agents.handle(DesklingCommand(.say, text: "tests pass", project: "api")!, at: Date().addingTimeInterval(60))
        let said = await eventually { bubble.isVisible && bubble.text == "tests pass" }
        XCTAssertTrue(said)
    }

    func testClickingAPlainAlertOpensItsPageAndStopsWavingForIt() {
        let settings = Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!)
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings,
            visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        var opened: [(URL, String)] = []
        let agents = AgentListener(performer: performer, settings: settings, openLink: { opened.append(($0, $1)) })
        performer.start()

        agents.handle(DesklingCommand(.alert, text: "3 notes waiting", project: "littlebear", open: "https://kmini.example:4648/#/queue")!)
        agents.handle(DesklingCommand(.alert, text: "3 notes waiting", project: "littlebear")!, at: Date().addingTimeInterval(5))
        XCTAssertEqual(agents.waiting.first?.link?.absoluteString, "https://kmini.example:4648/#/queue", "a later alert keeps the page")

        agents.goToWaiting()

        XCTAssertEqual(opened.map(\.0.absoluteString), ["https://kmini.example:4648/#/queue"])
        XCTAssertEqual(opened.map(\.1), ["littlebear"])
        XCTAssertTrue(agents.waiting.isEmpty)
    }

    func testClickingAnAlertThatTakesYouSomewhereAlsoStopsWavingForIt() {
        let settings = Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!)
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings,
            visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        var went: [AgentEvent.Origin?] = []
        let agents = AgentListener(performer: performer, settings: settings, goTo: { went.append($0); return true })
        performer.start()
        let origin = AgentEvent.Origin(processes: [42], bundleID: "com.apple.Terminal", tty: "/dev/ttys003")
        agents.handle(DesklingCommand(.alert, text: "srv needs you", project: "srv", origin: origin)!)
        agents.handle(DesklingCommand(.alert, text: "api needs you", project: "api", origin: origin)!, at: Date().addingTimeInterval(5))

        agents.goToWaiting()

        XCTAssertEqual(went, [origin])
        XCTAssertEqual(agents.waiting.map(\.project), ["api"], "only the one you were taken to is dismissed")
        XCTAssertEqual(performer.alertText, "api needs you")
    }

    func testWordsSentWhileHeNapsWaitUntilYouAreBack() async {
        var idle = Performer.napAfter + 1
        let bubble = SpeechBubble()
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, bubble: bubble,
            settings: Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!),
            visibleFrame: { CGRect(x: 0, y: 0, width: 1440, height: 900) },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { idle })
        defer { performer.stop(); bubble.hide() }
        performer.start()
        let napped = await eventually { performer.isNapping }
        XCTAssertTrue(napped)

        for word in ["one", "two", "three", "four"] { performer.speak(word) }
        performer.react(.celebrate, saying: "five")
        XCTAssertEqual(performer.heldWords, ["three", "four", "five"], "only the latest few are kept")
        XCTAssertFalse(bubble.isVisible, "nothing is said to an empty room")

        idle = 0.2
        let told = await eventually(within: 6) { bubble.isVisible && bubble.text == "three" }
        XCTAssertTrue(told, "once you are back he wakes and tells you, oldest first")
    }

    private func eventually(within seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }
}
