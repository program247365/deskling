import AppKit
import ServiceManagement

/// The menubar item: the whole UI apart from About.
@MainActor
final class MenuController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let performer: Performer
    private let settings: Settings
    private let about: AboutWindowController
    private let settingsWindow: SettingsWindowController
    private let roster: Roster
    private let agents: AgentListener
    private let picker: CharacterPickerWindowController
    private let updater: Updater?
    /// The "Waiting on you" section at the top, rebuilt each time the menu opens.
    private var waitingItems: [NSMenuItem] = []
    private var characterItems: [String: NSMenuItem] = [:]
    private let visibilityItem = NSMenuItem(title: "", action: #selector(toggleVisibility), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var sizeItems: [CharacterSize: NSMenuItem] = [:]
    private var icons: (shown: NSImage?, hidden: NSImage?) = (nil, nil)

    init(performer: Performer, settings: Settings, roster: Roster, agents: AgentListener,
         picker: CharacterPickerWindowController, updater: Updater?) {
        self.performer = performer
        self.settings = settings
        self.roster = roster
        self.agents = agents
        self.picker = picker
        self.updater = updater
        settingsWindow = SettingsWindowController(updater: updater)
        about = AboutWindowController(characters: roster.characters)
        super.init()

        showIcon(for: roster.character(id: settings.characterID))
        performer.onShownChange = { [weak self] in self?.refreshIcon() }

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(visibilityItem)

        let characterMenu = NSMenu()
        for character in roster.characters {
            let item = NSMenuItem(title: character.name, action: #selector(chooseCharacter(_:)), keyEquivalent: "")
            item.representedObject = character.id
            characterItems[character.id] = item
            characterMenu.addItem(item)
        }
        characterMenu.addItem(.separator())
        characterMenu.addItem(NSMenuItem(title: "Show All…", action: #selector(showPicker), keyEquivalent: ""))
        let characterItem = NSMenuItem(title: "Character", action: nil, keyEquivalent: "")
        characterItem.submenu = characterMenu
        menu.addItem(characterItem)

        let sizeMenu = NSMenu()
        for size in CharacterSize.allCases {
            let item = NSMenuItem(title: size.rawValue.capitalized, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.representedObject = size.rawValue
            sizeItems[size] = item
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)

        menu.addItem(loginItem)
        menu.addItem(.separator())
        if updater != nil {
            let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
            check.target = self
            menu.addItem(check)
        }
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "About Deskling (v\(AppInfo.version))", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit Deskling", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items + sizeMenu.items + characterMenu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    /// Clawd keeps his committed icon; everyone else gets one made from their standing pose.
    func showIcon(for character: Character) {
        let icon = character.id == Character.clawdID
            ? Bundle.main.image(forResource: "MenuIcon").map { $0.isTemplate = true; return $0 }
            : MenuIcon.make(for: character)
        icons = (icon, icon.flatMap(MenuIcon.hollow))
        statusItem.button?.title = icon == nil ? character.name : ""
        statusItem.button?.setAccessibilityLabel(character.name)
        refreshIcon()
    }

    /// Solid while the character is on the desktop, a hollow outline while hidden.
    private func refreshIcon() {
        statusItem.button?.image = performer.isRunning ? icons.shown : icons.hidden ?? icons.shown
    }

    /// Titles and check marks are read from the real state each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let name = performer.characterName
        visibilityItem.title = performer.isRunning && !performer.isLeaving ? "Hide \(name)" : "Show \(name)"
        showWaiting(in: menu)
        let current = roster.character(id: settings.characterID).id
        for (id, item) in characterItems { item.state = id == current ? .on : .off }
        for (size, item) in sizeItems { item.state = size == settings.size ? .on : .off }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleVisibility() {
        // Show while he is on his way out calls the exit off.
        if performer.isRunning, !performer.isLeaving { performer.beamUp() } else { performer.start() }
    }

    @objc private func chooseSize(_ item: NSMenuItem) {
        guard let raw = item.representedObject as? String, let size = CharacterSize(rawValue: raw) else { return }
        settings.size = size
        performer.refresh()
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            // The check mark is read from the service's real state, so a failure simply leaves it unchanged.
            NSLog("Deskling: could not change Launch at Login: \(error.localizedDescription)")
        }
    }

    @objc private func chooseCharacter(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        picker.choose(roster.character(id: id))
    }

    @objc private func showPicker() { picker.show() }

    /// One item per waiting session; choosing one dismisses it. Nothing at all when no one is waiting.
    private func showWaiting(in menu: NSMenu) {
        for item in waitingItems { menu.removeItem(item) }
        waitingItems = []
        let waiting = agents.waiting
        guard !waiting.isEmpty else { return }

        let header = NSMenuItem(title: "Waiting on you", action: nil, keyEquivalent: "")
        header.isEnabled = false
        var items = [header]
        let now = Date()
        for session in waiting {
            let item = NSMenuItem(title: session.menuTitle(at: now), action: #selector(dismissWaiting(_:)), keyEquivalent: "")
            item.representedObject = session.id
            item.target = self
            item.toolTip = "Stop waving for this one"
            items.append(item)
        }
        if waiting.count > 1 {
            let all = NSMenuItem(title: "Dismiss All", action: #selector(dismissAllWaiting), keyEquivalent: "")
            all.target = self
            items.append(all)
        }
        items.append(.separator())
        for (index, item) in items.enumerated() { menu.insertItem(item, at: index) }
        waitingItems = items
    }

    @objc private func dismissWaiting(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        agents.dismiss(id)
    }

    @objc private func dismissAllWaiting() { agents.dismissAll() }

    @objc private func checkForUpdates() { updater?.checkNow() }

    @objc private func showAbout() { about.show() }

    @objc private func showSettings() { settingsWindow.show() }

    @objc private func quit() { NSApp.terminate(nil) }
}
