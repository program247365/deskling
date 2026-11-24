import DesklingKit
import XCTest

@MainActor
final class PerformerTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func testCancelledPopOutDoesNotLeaveHimInvisible() async {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        defer { window.hide() }
        let popping = Task { await window.pop(visible: false) }
        try? await Task.sleep(for: .milliseconds(30))

        // What a size change or a display change does: cancel the routine, then show him again.
        popping.cancel()
        window.show()
        await popping.value

        XCTAssertEqual(window.opacity, 1)
    }

    func testHeAppearsOnceAScreenArrivesIfHeWasStartedWithoutOne() {
        var visibleFrame: CGRect?
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window,
            settings: Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!),
            visibleFrame: { visibleFrame })
        defer { performer.stop() }

        // Launched at login with the display still asleep.
        performer.start()
        XCTAssertTrue(performer.isRunning, "he was asked to be shown, so the menu should offer Hide")
        XCTAssertFalse(window.isVisible)

        visibleFrame = screen
        performer.refresh()
        XCTAssertTrue(window.isVisible)
    }

    func testHideStaysHiddenThroughAScreenChange() {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window,
            settings: Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!),
            visibleFrame: { self.screen })
        performer.start()
        performer.stop()

        performer.refresh()

        XCTAssertFalse(performer.isRunning)
        XCTAssertFalse(window.isVisible)
    }

    func testBeamUpPutsTheLightAtTheMiddleAndLeavesHimHidden() async {
        // The real screen where there is one: leaving it is what once stalled the lift, and the light never went out.
        let screen = NSScreen.screens.first?.visibleFrame ?? self.screen
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { screen }, cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        performer.start()

        performer.beamUp()
        XCTAssertTrue(performer.isRunning, "the menubar icon stays solid until he has actually gone")
        XCTAssertTrue(performer.isLeaving)

        // He started at the left edge, so he pops over and walks the last steps to the middle.
        let reachedTheLight = await eventually(within: 8) { abs(window.frame.midX - screen.midX) < 1 }
        XCTAssertTrue(reachedTheLight)
        XCTAssertEqual(window.frame.minY, screen.minY, "he walks in along the floor")

        let gone = await eventually(within: 12) { !performer.isRunning }
        XCTAssertTrue(gone)
        XCTAssertFalse(performer.isLeaving)
        XCTAssertFalse(window.isVisible)
    }

    func testShowDuringTheExitCallsItOff() async {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen }, cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        performer.start()
        performer.beamUp()
        try? await Task.sleep(for: .milliseconds(600))

        performer.start()

        XCTAssertFalse(performer.isLeaving)
        XCTAssertTrue(performer.isRunning)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.opacity, 1)
        XCTAssertEqual(window.frame.minY, screen.minY)
        // He is still there well after the exit would have finished.
        try? await Task.sleep(for: .seconds(1))
        XCTAssertTrue(performer.isRunning)
    }

    func testShownAgainWithAnEntranceHeDropsInAtTheMiddle() async {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen }, cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        performer.start()
        performer.stop()

        performer.start(entrance: true)

        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 1)
        XCTAssertGreaterThan(window.frame.minY, screen.minY, "he starts above the floor, not standing on it")
        let landed = await eventually { window.frame.minY == self.screen.minY }
        XCTAssertTrue(landed)
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 1)
    }

    func testBeamUpWhileHiddenDoesNothing() {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen })
        performer.beamUp()
        XCTAssertFalse(performer.isLeaving)
        XCTAssertFalse(window.isVisible)
    }

    private func settings() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!)
    }

    /// Lets the routine run until `condition` holds or `seconds` pass.
    private func eventually(within seconds: Double = 3, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func testAnAlertComesToTheScreenYouAreOnAndGoesHomeAfter() async {
        let other = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen }, alertFrame: { other },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
        defer { performer.stop() }
        performer.start()

        performer.alert("api needs you")
        let arrived = await eventually { other.contains(window.frame) }
        XCTAssertTrue(arrived, "he should wave on the screen with the cursor, not stay on his own")

        performer.clearAlert()
        let home = await eventually { self.screen.contains(window.frame) }
        XCTAssertTrue(home, "once answered he goes back to his own screen")
    }

    func testHeNapsWhileYouAreAwayAndWakesWhenYouComeBack() async {
        var idle: TimeInterval = 0
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen }, cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { idle })
        defer { performer.stop() }
        performer.start()
        let stayedAwake = await eventually(within: 0.5) { performer.isNapping }
        XCTAssertFalse(stayedAwake)

        idle = Performer.napAfter + 1
        let napped = await eventually { performer.isNapping }
        XCTAssertTrue(napped)

        idle = 0.2
        let woke = await eventually { !performer.isNapping }
        XCTAssertTrue(woke)
    }

    func testAnAlertWakesHim() async {
        let window = CharacterWindow(size: CharacterSize.medium.size)
        let performer = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: window, settings: settings(),
            visibleFrame: { self.screen }, alertFrame: { self.screen },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { Performer.napAfter + 1 })
        defer { performer.stop() }
        performer.start()
        let napped = await eventually { performer.isNapping }
        XCTAssertTrue(napped)

        performer.alert("api needs you")
        XCTAssertFalse(performer.isNapping)
        XCTAssertEqual(performer.alertText, "api needs you")
    }

    private func announcer(bubble: SpeechBubble) -> Performer {
        Performer(
            character: Character.clawd(directory: stagedAnimations()), window: CharacterWindow(size: CharacterSize.medium.size),
            bubble: bubble, settings: settings(), visibleFrame: { self.screen }, alertFrame: { self.screen },
            cursorLocation: { CGPoint(x: -5000, y: -5000) }, idleTime: { 0 })
    }

    func testAnAnnouncementYouAskedForSpeaksStraightAway() async {
        let bubble = SpeechBubble()
        let performer = announcer(bubble: bubble)
        defer { performer.stop() }
        performer.start()
        performer.announce(Performer.Announcement(lines: ["Let me check…"], asked: true))
        // No hello wave first: the menu click should get an answer at once.
        let spoke = await eventually(within: 0.6) { bubble.isVisible && bubble.text == "Let me check…" }
        XCTAssertTrue(spoke)
    }

    func testANewAnnouncementTakesOverWithoutStartingAgain() async {
        let bubble = SpeechBubble()
        let performer = announcer(bubble: bubble)
        defer { performer.stop() }
        performer.start()
        performer.announce(Performer.Announcement(lines: ["Let me check…"], asked: true))
        _ = await eventually(within: 0.6) { bubble.text == "Let me check…" }
        performer.announce(Performer.Announcement(lines: ["Psst! Deskling 9.9.9 is out", "Click me"], asked: true))
        let replaced = await eventually(within: 0.6) { bubble.text == "Psst! Deskling 9.9.9 is out" }
        XCTAssertTrue(replaced, "the offer replaces the line he is saying, without another hello wave")
    }

    func testAnAnnouncementYouAskedForGetsThroughAnAlertThenHeGoesBackToIt() async {
        let bubble = SpeechBubble()
        let performer = announcer(bubble: bubble)
        defer { performer.stop() }
        performer.start()
        performer.alert("api needs you")
        _ = await eventually { bubble.text == "api needs you" }

        performer.announce(Performer.Announcement(lines: ["You're up to date!"], holdFor: 0.3, asked: true))
        let told = await eventually { bubble.text == "You're up to date!" }
        XCTAssertTrue(told, "a check you asked for answers even while he waves for an agent")
        let back = await eventually { bubble.text == "api needs you" }
        XCTAssertTrue(back, "then he goes back to waving for the agent")
    }

    func testAnAnnouncementNobodyAskedForWaitsForTheAlert() async {
        let bubble = SpeechBubble()
        let performer = announcer(bubble: bubble)
        defer { performer.stop() }
        performer.start()
        performer.alert("api needs you")
        _ = await eventually { bubble.text == "api needs you" }
        performer.announce(Performer.Announcement(lines: ["Psst! Deskling 9.9.9 is out"]))
        let interrupted = await eventually(within: 1) { bubble.text == "Psst! Deskling 9.9.9 is out" }
        XCTAssertFalse(interrupted)
    }
}

