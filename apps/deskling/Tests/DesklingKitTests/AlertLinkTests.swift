@testable import DesklingKit
import XCTest

@MainActor
final class AlertLinkTests: XCTestCase {
    private func settings() -> Settings {
        Settings(defaults: UserDefaults(suiteName: "clawd.tests.\(UUID().uuidString)")!)
    }

    func testASiteIsItsSchemeHostAndPort() {
        XCTAssertEqual(AlertLink.site(of: URL(string: "https://Kmini.example:4648/#/queue")!), "https://kmini.example:4648")
        XCTAssertEqual(AlertLink.site(of: URL(string: "http://127.0.0.1/x")!), "http://127.0.0.1")
    }

    func testItAsksForANewSiteAndOpensOnlyIfYouSaySo() {
        let settings = settings()
        let url = URL(string: "https://kmini.example:4648/")!
        var opened: [URL] = []
        XCTAssertFalse(AlertLink.open(url, for: "littlebear", settings: settings, ask: { _, _ in .cancel }, opener: { opened.append($0) }))
        XCTAssertTrue(opened.isEmpty)
        XCTAssertTrue(AlertLink.open(url, for: "littlebear", settings: settings, ask: { _, _ in .open }, opener: { opened.append($0) }))
        XCTAssertEqual(opened, [url])
        XCTAssertTrue(settings.allowedLinkSites.isEmpty, "Open is for this time only")
    }

    func testAlwaysAllowStopsTheQuestionForThatSiteOnly() {
        let settings = settings()
        var asked = 0
        let ask: @MainActor (URL, String) -> AlertLink.Answer = { _, _ in asked += 1; return .always }
        AlertLink.open(URL(string: "https://kmini.example:4648/a")!, for: "littlebear", settings: settings, ask: ask, opener: { _ in })
        AlertLink.open(URL(string: "https://kmini.example:4648/b")!, for: "littlebear", settings: settings, ask: ask, opener: { _ in })
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(settings.allowedLinkSites, ["https://kmini.example:4648"])
        AlertLink.open(URL(string: "https://kmini.example:9999/")!, for: "x", settings: settings, ask: ask, opener: { _ in })
        XCTAssertEqual(asked, 2, "another port is another site")
    }
}
