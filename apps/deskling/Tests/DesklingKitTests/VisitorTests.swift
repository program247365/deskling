import DesklingEvents
@testable import DesklingKit
import XCTest

final class FloorTests: XCTestCase {
    func testNearestFreeSpotIsBesideWhoeverIsInTheWay() {
        let blocked: [ClosedRange<CGFloat>] = [400...600]
        XCTAssertEqual(Floor.nearestFree(to: 450, in: 0...1000, blocked: blocked), 400)
        XCTAssertEqual(Floor.nearestFree(to: 590, in: 0...1000, blocked: blocked), 600)
        XCTAssertEqual(Floor.nearestFree(to: 100, in: 0...1000, blocked: blocked), 100, "a free spot is kept")
        XCTAssertEqual(Floor.nearestFree(to: 500, prefer: 900, in: 0...1000, blocked: blocked), 600, "a tie goes toward prefer")
        XCTAssertNil(Floor.nearestFree(to: 500, in: 0...1000, blocked: [-10...1010]), "no room anywhere")
    }

    func testEdgesOfABlockedStretchAreFree() {
        XCTAssertFalse(Floor.isBlocked(400, by: [400...600]))
        XCTAssertTrue(Floor.isBlocked(401, by: [400...600]))
    }

    func testRoomStopsAtTheNeighboursEitherSide() {
        XCTAssertEqual(Floor.room(around: 300, in: 0...1000, blocked: [100...200, 600...700]), 200...600)
        XCTAssertEqual(Floor.room(around: 800, in: 0...1000, blocked: [100...200, 600...700]), 700...1000)
        XCTAssertEqual(Floor.room(around: 300, in: 0...1000, blocked: []), 0...1000)
    }
}

@MainActor
final class VisitorTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let away = CGPoint(x: -5000, y: -5000)

    private func roster() -> Roster {
        Roster(clawdDirectory: stagedAnimations(),
               charactersDirectory: stagedAnimations().deletingLastPathComponent().appendingPathComponent("characters"))
    }

    private func settings(roams: Bool = false) -> Settings {
        let settings = Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!)
        settings.roams = roams
        return settings
    }

    private func eventually(within seconds: Double = 5, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func overlaps(_ spans: [ClosedRange<CGFloat>]) -> Bool {
        spans.count == 2 && spans[0].overlaps(spans[1])
    }

    private struct Scene {
        let host: Performer
        let hostWindow: CharacterWindow
        let floor: Floor
        let visitors: Visitors
        let listener: AgentListener
    }

    private func scene(roams: Bool = false, openLink: (@MainActor (URL, String) -> Void)? = nil) -> Scene {
        let settings = settings(roams: roams)
        let floor = Floor()
        let hostWindow = CharacterWindow(size: CharacterSize.medium.size)
        let host = Performer(
            character: Character.clawd(directory: stagedAnimations()), window: hostWindow, settings: settings,
            visibleFrame: { self.screen }, alertFrame: { self.screen },
            cursorLocation: { self.away }, idleTime: { 0 }, floor: floor)
        let visitors = Visitors(
            roster: roster(), settings: settings, floor: floor, host: host, alertFrame: { self.screen }, openLink: openLink)
        return Scene(host: host, hostWindow: hostWindow, floor: floor, visitors: visitors,
                     listener: AgentListener(performer: host, settings: settings, visitors: visitors))
    }

    private func alert(as character: String) -> DesklingCommand {
        DesklingCommand(.alert, text: "3 Bear notes waiting", project: "littlebear", character: character)!
    }

    func testANamedCharacterVisitsInsteadOfTheHostAlerting() async throws {
        let scene = scene()
        defer { scene.host.stop(); scene.visitors.dismissAll() }
        scene.host.start()

        scene.listener.handle(alert(as: "Nook"))

        XCTAssertNil(scene.host.alertText, "the host carries on, free to talk for agents")
        XCTAssertEqual(scene.visitors.visiting, ["littlebear"])
        let visitor = try XCTUnwrap(scene.visitors.performer(for: "littlebear"))
        XCTAssertEqual(visitor.characterID, "polarbear")
        XCTAssertEqual(visitor.alertText, "3 Bear notes waiting")
    }

    func testClickingAVisitorOpensThePageTheAlertNamedAndSendsThemHome() {
        var opened: [(URL, String)] = []
        let scene = scene(openLink: { opened.append(($0, $1)) })
        defer { scene.host.stop(); scene.visitors.dismissAll() }
        scene.host.start()
        scene.listener.handle(DesklingCommand(
            .alert, text: "3 Bear notes waiting", project: "littlebear", character: "nook",
            open: "https://kmini-home.example.ts.net:4648/#/queue")!)

        scene.visitors.click("littlebear")

        XCTAssertEqual(opened.map(\.0.absoluteString), ["https://kmini-home.example.ts.net:4648/#/queue"])
        XCTAssertEqual(opened.map(\.1), ["littlebear"])
        XCTAssertTrue(scene.visitors.visiting.isEmpty)
    }

    func testANewerAlertKeepsTheLinkUnlessItNamesAnother() {
        var opened: [URL] = []
        let scene = scene(openLink: { url, _ in opened.append(url) })
        defer { scene.host.stop(); scene.visitors.dismissAll() }
        scene.host.start()
        scene.listener.handle(DesklingCommand(
            .alert, text: "3 waiting", project: "littlebear", character: "nook", open: "https://a.example/")!)
        scene.listener.handle(alert(as: "nook"))
        scene.visitors.click("littlebear")
        XCTAssertEqual(opened.map(\.absoluteString), ["https://a.example/"])
    }

    func testTheHostsOwnCharacterOrAnUnknownOneAlertsAsBefore() {
        let scene = scene()
        defer { scene.host.stop() }
        scene.host.start()

        scene.listener.handle(DesklingCommand(.alert, text: "api needs you", project: "api", character: "clawd")!)
        XCTAssertEqual(scene.host.alertText, "api needs you")
        scene.listener.handle(DesklingCommand(.alert, text: "b needs you", project: "b", character: "nobody")!)
        XCTAssertTrue(scene.visitors.visiting.isEmpty)
    }

    func testTheyStandSideBySideAndNeverInFrontOfEachOther() async {
        let scene = scene(roams: true)
        defer { scene.host.stop(); scene.visitors.dismissAll() }
        scene.host.start()
        scene.listener.handle(alert(as: "nook"))
        let both = await eventually { scene.floor.spans(except: nil, on: self.screen).count == 2 }
        XCTAssertTrue(both)

        // Watch the host roam around the visitor for a while.
        let deadline = Date().addingTimeInterval(6)
        var closest = CGFloat.infinity
        while Date() < deadline {
            let spans = scene.floor.spans(except: nil, on: screen)
            XCTAssertFalse(overlaps(spans), "\(spans)")
            if spans.count == 2 {
                closest = min(closest, max(spans[0].lowerBound, spans[1].lowerBound) - min(spans[0].upperBound, spans[1].upperBound))
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertGreaterThanOrEqual(closest, Floor.gap - 1)
    }

    func testTheVisitorArrivesBesideTheHostWavingForAnAgent() async {
        let scene = scene()
        defer { scene.host.stop(); scene.visitors.dismissAll() }
        scene.host.start()
        scene.listener.handle(DesklingCommand(.alert, text: "api needs you", project: "api")!)
        scene.listener.handle(alert(as: "nook"))

        // Both settle at the middle of the screen, side by side.
        let settled = await eventually {
            let spans = scene.floor.spans(except: nil, on: self.screen)
            guard spans.count == 2, !self.overlaps(spans) else { return false }
            let gap = max(spans[0].lowerBound, spans[1].lowerBound) - min(spans[0].upperBound, spans[1].upperBound)
            return gap < 40 && abs((spans[0].lowerBound + spans[1].upperBound) / 2 - self.screen.midX) < 300
        }
        XCTAssertTrue(settled, "\(scene.floor.spans(except: nil, on: screen))")
    }

    func testClearingSendsTheVisitorHome() async {
        let scene = scene()
        defer { scene.host.stop() }
        scene.host.start()
        scene.listener.handle(alert(as: "nook"))
        let visitor = scene.visitors.performer(for: "littlebear")

        scene.listener.handle(DesklingCommand(.clear, project: "littlebear")!)

        XCTAssertTrue(scene.visitors.visiting.isEmpty)
        let gone = await eventually { visitor?.isRunning == false }
        XCTAssertTrue(gone)
        let left = await eventually { scene.floor.spans(except: nil, on: self.screen).count == 1 }
        XCTAssertTrue(left, "the visitor no longer holds a spot")
    }

    func testNoVisitWhileAlertsAreOffOrTheHostIsHidden() {
        let scene = scene()
        scene.host.stop()
        scene.listener.handle(alert(as: "nook"))
        XCTAssertTrue(scene.visitors.visiting.isEmpty)
        XCTAssertNil(scene.host.alertText, "nor does the host take it instead")
    }
}
