import AppKit

/// The web page an alert asked to open when you click it, as `deskling alert --open URL`.
/// Any process on the Mac can send an alert, so a site opens without asking only after you chose Always Allow for it.
@MainActor
enum AlertLink {
    enum Answer { case open, always, cancel }

    /// "https://host:4648": the part of a link that Always Allow remembers.
    static func site(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        return url.port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)"
    }

    /// Opens `url` if its site is allowed or you say so. True if it opened.
    @discardableResult
    static func open(
        _ url: URL, for project: String, settings: Settings,
        ask: @MainActor (URL, String) -> Answer = askInDialog, opener: @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) -> Bool {
        let site = site(of: url)
        if !settings.allowedLinkSites.contains(site) {
            switch ask(url, project) {
            case .cancel: return false
            case .always: settings.allowedLinkSites.append(site)
            case .open: break
            }
        }
        opener(url)
        return true
    }

    static func askInDialog(_ url: URL, _ project: String) -> Answer {
        let alert = NSAlert()
        alert.messageText = "Open \(site(of: url))?"
        alert.informativeText = "\(project) asked to open \(url.absoluteString) when you click its alert."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .open
        case .alertSecondButtonReturn: return .always
        default: return .cancel
        }
    }
}
