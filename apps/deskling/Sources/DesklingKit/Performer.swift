import AppKit

/// Calls a handler on every display refresh until the handler says it is done or `stop()` is called.
@MainActor
private final class Ticker: NSObject {
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var handler: ((TimeInterval) -> Bool)?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Resumes when `handler` returns true or the ticker is stopped. `handler` receives seconds since the last tick.
    func run(on window: CharacterWindow, handler: @escaping (TimeInterval) -> Bool) async {
        stop()
        guard let link = window.displayLink(target: self, selector: #selector(tick(_:))) else { return }
        // He walks about 70pt a second; 30 moves a second is smooth for 12fps pixel art
        // and halves the cost of moving the window on every display refresh.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 24, maximum: 30, preferred: 30)
        self.link = link
        self.handler = handler
        lastTimestamp = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.continuation = continuation
            link.add(to: .main, forMode: .common)
        }
    }

    func stop() {
        link?.invalidate()
        link = nil
        handler = nil
        continuation?.resume()
        continuation = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        let elapsed = lastTimestamp.map { link.timestamp - $0 } ?? link.duration
        lastTimestamp = link.timestamp
        if handler?(elapsed) == true { stop() }
    }
}

/// Clawd's routine: walk to a stop, perform an act, repeat; sometimes teleport instead of walking.
/// Agent events and the cursor can interrupt it; afterwards he picks up where he left off.
@MainActor
public final class Performer {
    private enum Mode {
        case idle, entrance, routine, watching, reacting, alerting, napping, announcing, leaving
    }

    /// Something to tell you that is not about an agent, such as an update. He says each line in turn
    /// and holds the last one until `endAnnouncement()`, or until `holdFor` has passed.
    public struct Announcement {
        public var lines: [String]
        /// Set when clicking him should do something while he holds the last line.
        public var onClick: (() -> Void)?
        public var holdFor: TimeInterval?
        public var onTimeout: (() -> Void)?
        /// You asked for this, as from the menu: he answers at once, without a hello wave, and even
        /// while he waves for an agent, going back to that after.
        public var asked: Bool

        public init(
            lines: [String], onClick: (() -> Void)? = nil, holdFor: TimeInterval? = nil,
            onTimeout: (() -> Void)? = nil, asked: Bool = false
        ) {
            self.lines = lines
            self.onClick = onClick
            self.holdFor = holdFor
            self.onTimeout = onTimeout
            self.asked = asked
        }
    }

    /// How long each line of an announcement stays up before the next.
    static let announcementLineDuration: TimeInterval = 3.5

    private var character: Character
    private var catalog: AnimationCatalog
    private let window: CharacterWindow
    private let settings: Settings
    private let ticker = Ticker()
    private let bubble: SpeechBubble
    private var queue: ActQueue
    private var rng = SystemRandomNumberGenerator()
    private var loop: Task<Void, Never>?
    private var stage: Stage?
    private var mode = Mode.idle
    /// Horizontal position along the floor, in `0...stage.maxX`.
    private var offset: CGFloat = 40
    private var facing: Facing = .right
    /// False while a teleport has him somewhere above the floor.
    private var onFloor = true
    /// Exists only during the launch entrance and the exit from the menu's Hide.
    private var spotlight: SpotlightWindow?
    /// Whether the user wants him shown. A loop may not exist yet, for example with no screen attached.
    private var wantsVisible = false {
        didSet { if wantsVisible != oldValue { onShownChange?() } }
    }
    /// Called when he is shown or hidden, so the menubar icon can follow.
    public var onShownChange: (() -> Void)?
    /// After the entrance his first move is a walk from where he landed, never a teleport.
    private var mustWalkNext = false
    /// What he is telling you while an agent waits on you; he keeps waving until it is cleared.
    public private(set) var alertText: String?
    /// Called when you click him, or his bubble, while he waves for an agent.
    public var onAlertClick: (() -> Void)?
    /// What he has to tell you once no agent needs him; nil when nothing.
    public private(set) var announcement: Announcement?
    /// Bumped by each `announce`, so a new one said mid-announcement starts from its first line.
    private var announcementNumber = 0
    private let visibleFrame: () -> CGRect?
    /// Shared with any other character on screen, so they keep out of each other's way.
    private let floor: Floor?
    /// Half the width of his standing drawing, as a fraction of his window's width.
    private var halfWidth: CGFloat?
    private let alertFrame: () -> CGRect?
    private let cursorLocation: () -> CGPoint
    private let idleTime: () -> TimeInterval

    private var walking: CharacterAnimation?
    private var looking: CharacterAnimation?
    /// Where the top of his head is in his standing pose, as a fraction of his window's height.
    private var headTop: CGFloat?
    private var cursorTimer: Timer?
    private var watchStarted = Date.distantPast
    private var cursorLastNear = Date.distantPast
    /// Set when he has watched the cursor long enough; cleared once it moves away from him.
    private var ignoresCursorUntilItLeaves = false
    private var petting = PetDetector()

    /// `visibleFrame` is the usable area of the display he lives on, or nil when there is none.
    /// By default that is the first screen, the one with the menubar. `alertFrame` is the usable area
    /// he comes to when an agent needs you: by default the screen the cursor is on, so you see him.
    /// `idleTime` is how long since you last touched the keyboard, mouse, or trackpad.
    public init(
        character: Character, window: CharacterWindow, bubble: SpeechBubble? = nil, settings: Settings,
        visibleFrame: @escaping () -> CGRect? = { NSScreen.screens.first?.visibleFrame },
        alertFrame: @escaping () -> CGRect? = { MainActor.assumeIsolated { Performer.cursorScreenFrame() } },
        cursorLocation: @escaping () -> CGPoint = { NSEvent.mouseLocation },
        idleTime: @escaping () -> TimeInterval = Performer.secondsSinceInput,
        floor: Floor? = nil
    ) {
        self.character = character
        catalog = character.catalog
        self.window = window
        self.bubble = bubble ?? SpeechBubble()
        self.settings = settings
        self.visibleFrame = visibleFrame
        self.alertFrame = alertFrame
        self.cursorLocation = cursorLocation
        self.idleTime = idleTime
        self.floor = floor
        queue = ActQueue(names: character.routineActs)
    }

    /// The usable area of the screen under the cursor.
    public static func cursorScreenFrame() -> CGRect? {
        let cursor = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(cursor, $0.frame, false) } ?? NSScreen.screens.first
        return screen?.visibleFrame
    }

    public nonisolated static func secondsSinceInput() -> TimeInterval {
        // ~0 is the system's "any input event".
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// True while he is asleep because you are away.
    public var isNapping: Bool { mode == .napping }

    /// What agents asked him to say while he napped, oldest first. He wakes up and tells you once you are back.
    public private(set) var heldWords: [String] = []
    /// Only the latest few are kept: a long nap should not end in a speech.
    static let mostHeldWords = 3

    private func hold(_ text: String) {
        heldWords = Array((heldWords + [text]).suffix(Self.mostHeldWords))
    }

    /// True from `start()` until `stop()`, whether or not there is a screen to show him on yet.
    public var isRunning: Bool { wantsVisible }

    /// True while he makes his exit after `beamUp()`: still on screen, but on his way out.
    public var isLeaving: Bool { mode == .leaving }

    public var characterName: String { character.name }

    public var characterID: String { character.id }

    /// Places him on the floor and begins the routine. Does nothing if already running.
    /// With `entrance`, he first drops in from the top of the screen, waving: at launch, and when shown from the menu.
    public func start(entrance: Bool = false) {
        wantsVisible = true
        startCursorWatch()
        // Asked back while on his way out: he stays, wherever on the floor he had got to.
        if mode == .leaving { cancelLoop() }
        guard loop == nil, let stage = placeOnFloor() else { return }
        if entrance {
            // Above the screen before the window appears, so he is never seen standing on the floor first.
            offset = stage.maxX / 2
            moveTo(stage.entranceOrigin(x: offset))
            mode = .entrance
        }
        window.show()
        loop = Task { [weak self] in await self?.begin(on: stage, entrance: entrance) }
    }

    public func stop() {
        wantsVisible = false
        cancelLoop()
        cursorTimer?.invalidate()
        cursorTimer = nil
        mode = .idle
        window.hide()
        floor?.remove(self)
    }

    /// Call when the screen layout or the size setting changes.
    public func refresh() {
        // The screen changed under his exit: he is simply gone.
        if mode == .leaving { stop() }
        cancelLoop()
        if wantsVisible { start() } else { placeOnFloor() }
    }

    /// Swaps who is on the desktop. The new character starts their routine where the old one stood.
    public func setCharacter(_ newCharacter: Character) {
        guard newCharacter != character else { return }
        character = newCharacter
        catalog = newCharacter.catalog
        queue = ActQueue(names: newCharacter.routineActs)
        walking = nil
        looking = nil
        headTop = nil
        halfWidth = nil
        refresh()
    }

    // MARK: Agents

    /// Plays an act for `role` where he stands, with `saying` over his head. Ignored during the entrance,
    /// while he is alerting you, or when this character has no act for the role.
    public func react(_ role: Role, saying: String? = nil) {
        if mode == .napping, let saying { return hold(saying) }
        guard mode == .routine || mode == .watching || mode == .reacting,
              !character.acts(for: role).isEmpty
        else { return }
        interrupt(as: .reacting) { performer, _ in await performer.play(role, saying: saying) }
    }

    public func hasActs(for role: Role) -> Bool {
        !character.acts(for: role).isEmpty
    }

    /// Waves once with `text` over his head and holds it long enough to read. Ignored at the same times as `react`.
    public func speak(_ text: String) {
        if mode == .napping { return hold(text) }
        guard mode == .routine || mode == .watching || mode == .reacting else { return }
        interrupt(as: .reacting) { performer, _ in
            performer.say(text)
            if let waving = performer.catalog.load("waving") { await performer.window.play(waving) }
            if Task.isCancelled { return }
            performer.standStill()
            try? await Task.sleep(for: .seconds(Self.readingTime(for: text)))
            performer.bubble.hide()
        }
    }

    /// Long enough to read `text` at a glance: a couple of seconds, more for longer lines, never long enough to get in the way.
    static func readingTime(for text: String) -> TimeInterval {
        min(max(1.5 + Double(text.count) * 0.08, 2.5), 6)
    }

    /// Plays one of the acts for `role`, if the character has any.
    private func play(_ role: Role, saying: String? = nil) async {
        guard let name = character.acts(for: role).randomElement(using: &rng) else { return }
        let catalog = catalog
        guard let act = await Task.detached(operation: { catalog.load(name) }).value,
              !Task.isCancelled
        else { return }
        if let saying { say(saying) }
        await perform(act)
        bubble.hide()
    }

    /// Comes to the middle of the floor and waves with `text` over his head until `clearAlert()`.
    public func alert(_ text: String) {
        alertText = text
        switch mode {
        case .alerting: say(text)
        case .idle, .entrance, .leaving: break // picked up when the routine would start
        default: interrupt(as: .alerting) { _, _ in }
        }
    }

    public func clearAlert() {
        alertText = nil
        if mode == .alerting { interrupt(as: .routine) { _, _ in } }
    }

    /// Stops what he is doing to tell you something, unless an agent needs you or you are away:
    /// then it waits until that is over.
    public func announce(_ announcement: Announcement) {
        self.announcement = announcement
        announcementNumber += 1
        switch mode {
        case .announcing: break // the one telling you picks it up, without waving hello again
        case .routine, .watching, .reacting: interrupt(as: .announcing) { _, _ in }
        case .alerting where announcement.asked:
            // Told straight away; afterwards carrying on brings the agent's alert back.
            interrupt(as: .announcing) { performer, _ in await performer.tellYou() }
        default: break // picked up when the routine would start
        }
    }

    /// Whether he is meant to be on screen; false once hidden from the menu.
    public var isShown: Bool { wantsVisible }

    /// Changes what he is saying without starting over, as for download progress. Takes no clicks.
    public func updateAnnouncement(_ text: String) {
        guard announcement != nil else { return announce(Announcement(lines: [text])) }
        announcement = Announcement(lines: [text])
    }

    public func endAnnouncement() {
        announcement = nil
        if mode == .announcing { interrupt(as: .routine) { _, _ in } }
    }

    // MARK: Routine

    private func cancelLoop() {
        loop?.cancel()
        loop = nil
        spotlight?.close()
        spotlight = nil
        ticker.stop()
        window.stopAnimation()
        bubble.hide()
        takesClicks(nil)
    }

    /// He only takes a click while he has something for it to do; the rest of the time clicks pass through him.
    private func takesClicks(_ click: (() -> Void)?) {
        window.onClick = click
        bubble.onClick = click
    }

    /// Stops what he is doing, runs `body`, then carries on with the routine or the alert.
    private func interrupt(as newMode: Mode, _ body: @escaping (Performer, Stage) async -> Void) {
        guard wantsVisible, stage != nil else { return }
        cancelLoop()
        mode = newMode
        loop = Task { [weak self] in
            guard let self else { return }
            await returnToFloor()
            guard !Task.isCancelled, let stage = self.stage else { return }
            await body(self, stage)
            if Task.isCancelled { return }
            await carryOn(on: stage)
        }
    }

    @discardableResult
    private func placeOnFloor() -> Stage? {
        guard let visibleFrame = visibleFrame() else { return nil }
        let stage = Stage(visibleFrame: visibleFrame, size: settings.size.size)
        self.stage = stage
        offset = min(max(offset, 0), stage.maxX)
        onFloor = true
        window.resize(to: stage.size)
        moveTo(stage.floorOrigin(x: offset))
        window.facing = facing
        return stage
    }

    private func loadWalking() -> CharacterAnimation? {
        if walking == nil { walking = catalog.load("walking") }
        return walking
    }

    private func standStill() {
        if let walking = loadWalking() { window.pose(walking, frame: character.standingFrame) }
    }

    private func begin(on stage: Stage, entrance: Bool) async {
        guard let walking = loadWalking() else { return }
        moveTo(entrance ? stage.entranceOrigin(x: offset) : stage.floorOrigin(x: offset))
        if entrance {
            await dropIn(on: stage, thenStandAs: walking)
            if Task.isCancelled { return }
            mustWalkNext = true
        } else {
            standStill()
        }
        await carryOn(on: stage)
    }

    /// The alert if an agent is waiting on you, then anything he has to tell you, otherwise the routine.
    private func carryOn(on stage: Stage) async {
        if alertText != nil, settings.alertsForAgents {
            await waveForAttention()
        } else if !heldWords.isEmpty {
            await sayHeldWords()
            if !Task.isCancelled { await routine(on: stage) }
        } else if announcement != nil {
            await tellYou()
            if !Task.isCancelled { await routine(on: stage) }
        } else {
            await routine(on: stage)
        }
    }

    /// Waves to get your attention, then says what he was asked to while he napped, one line at a time.
    private func sayHeldWords() async {
        face(.right)
        if let waving = catalog.load("waving") { await window.play(waving) }
        if Task.isCancelled { return }
        standStill()
        // A line is only done with once it has stayed up long enough to read; an interruption leaves it for next time.
        while !Task.isCancelled, let text = heldWords.first {
            say(text)
            try? await Task.sleep(for: .seconds(Self.readingTime(for: text)))
            if !Task.isCancelled { heldWords.removeFirst() }
        }
        bubble.hide()
    }

    /// Waves hello, then says the announcement's lines in turn and holds the last.
    /// Reads `announcement` afresh each step, so `updateAnnouncement` shows without starting over.
    private func tellYou() async {
        mode = .announcing
        face(.right)
        if announcement?.asked != true, let waving = catalog.load("waving") { await window.play(waving) }
        if Task.isCancelled { return }
        standStill()
        var index = 0
        var said: String?
        var holdingSince: Date?
        var number = announcementNumber
        while !Task.isCancelled, let current = announcement, !current.lines.isEmpty {
            if number != announcementNumber {
                number = announcementNumber
                index = 0
                holdingSince = nil
            }
            let line = min(index, current.lines.count - 1)
            if current.lines[line] != said {
                said = current.lines[line]
                say(current.lines[line])
            }
            let isLast = line == current.lines.count - 1
            takesClicks(isLast ? current.onClick : nil)
            if !isLast {
                index += 1
                // A new announcement cuts the line short rather than waiting it out.
                let next = Date().addingTimeInterval(Self.announcementLineDuration)
                while !Task.isCancelled, Date() < next, number == announcementNumber {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continue
            }
            let since = holdingSince ?? Date()
            holdingSince = since
            if let hold = current.holdFor, Date().timeIntervalSince(since) >= hold {
                announcement = nil
                current.onTimeout?()
                break
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        bubble.hide()
        takesClicks(nil)
    }

    /// A teleport can leave him in mid-air, and an alert on another screen away from home;
    /// anything that interrupts him brings him back to his own floor first.
    private func returnToFloor() async {
        guard let stage else { return }
        let awayFromHome = visibleFrame().map { $0 != stage.visibleFrame } ?? false
        guard !onFloor || window.opacity < 1 || awayFromHome else { return }
        await window.pop(visible: false)
        if Task.isCancelled { return }
        placeOnFloor()
        standStill()
        await window.pop(visible: true)
    }

    private func routine(on stage: Stage) async {
        mode = .routine
        guard let walking = loadWalking() else { return }
        while !Task.isCancelled {
            guard let name = queue.next(using: &rng) else {
                // Someone with no acts drawn yet just strolls.
                await walk(to: nextWalkStop(on: stage), on: stage, with: walking)
                try? await Task.sleep(for: .seconds(3))
                continue
            }
            // Parsed off the main thread, one act at a time, and dropped after it plays.
            let catalog = catalog
            guard let act = await Task.detached(operation: { catalog.load(name) }).value else {
                // An unreadable act is skipped; the pause keeps a folder of bad files from spinning.
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            if Task.isCancelled { return }

            let walksFirst = mustWalkNext
            mustWalkNext = false
            // Read each time round, so changing the setting takes effect on his very next move.
            if !walksFirst, Choreography.shouldTeleport(roams: settings.roams, using: &rng) {
                onFloor = false
                await window.pop(visible: false)
                if Task.isCancelled { return }
                var up = stage.teleportOrigin(using: &rng)
                up.x = stage.visibleFrame.minX + freeSpot(near: up.x - stage.visibleFrame.minX, on: stage)
                moveTo(up)
                window.pose(act, frame: 0)
                await window.pop(visible: true)
                if Task.isCancelled { return }
                await perform(act)
                if Task.isCancelled { return }
                await window.pop(visible: false)
                if Task.isCancelled { return }
                offset = freeSpot(near: CGFloat.random(in: 0...stage.maxX, using: &rng), on: stage)
                moveTo(stage.floorOrigin(x: offset))
                onFloor = true
                window.pose(walking, frame: character.standingFrame)
                await window.pop(visible: true)
            } else {
                await walk(to: nextWalkStop(on: stage), on: stage, with: walking)
                if Task.isCancelled { return }
                await perform(act)
            }
            if Task.isCancelled { return }
        }
    }

    private func walk(to target: CGFloat, on stage: Stage, with walking: CharacterAnimation) async {
        face(target >= offset ? .right : .left)
        window.loopWalk(walking, cycle: character.walkCycle)
        await ticker.run(on: window) { [weak self] elapsed in
            guard let self else { return true }
            let step = Choreography.step(x: offset, toward: target, width: stage.size.width, elapsed: elapsed)
            // Someone arrived in his path: he stops short rather than walk in front of them.
            let blocked = blocked(on: stage)
            if Floor.isBlocked(step.x, by: blocked), !Floor.isBlocked(offset, by: blocked) { return true }
            offset = step.x
            moveTo(stage.floorOrigin(x: offset))
            return step.arrived
        }
        if !Task.isCancelled { standStill() }
    }

    private func face(_ direction: Facing) {
        facing = direction
        window.facing = direction
    }

    /// Hurries to the middle of the floor of the screen you are using and waves until the alert is
    /// cleared or replaced. If you move to another screen, he follows.
    private func waveForAttention() async {
        mode = .alerting
        guard let walking = loadWalking() else { return }
        let waving = catalog.load("waving")
        var saidIt = false
        while !Task.isCancelled {
            let moved = await comeToAlertSpot(of: alertFrame(), justArrived: !saidIt)
            if Task.isCancelled { return }
            if moved || !saidIt {
                face(.right)
                if let alertText { say(alertText) }
                takesClicks { [weak self] in self?.onAlertClick?() }
                saidIt = true
            }
            if let waving { await window.play(waving) }
            if Task.isCancelled { return }
            window.pose(walking, frame: character.standingFrame)
            try? await Task.sleep(for: .seconds(1.5))
        }
    }

    /// Pops over to the middle of the floor of `frame` (his own screen when nil), or beside whoever is already
    /// there. Once there he stays put, unless you move to another screen or someone ends up where he stands.
    /// True if he moved.
    private func comeToAlertSpot(of frame: CGRect?, justArrived: Bool) async -> Bool {
        guard let here = stage else { return false }
        let there = frame.map { Stage(visibleFrame: $0, size: here.size) } ?? here
        let spot = alertSpot(on: there)
        let crowded = Floor.isBlocked(offset, by: blocked(on: there))
        guard there != here || crowded || (justArrived && abs(offset - spot) > here.size.width) else { return false }
        bubble.hide()
        await window.pop(visible: false)
        if Task.isCancelled { return false }
        stage = there
        offset = spot
        onFloor = true
        moveTo(there.floorOrigin(x: offset))
        standStill()
        await window.pop(visible: true)
        return true
    }

    // MARK: Sharing the floor

    /// Moves his window, and tells the floor where he now stands.
    private func moveTo(_ origin: CGPoint) {
        window.origin = origin
        guard let floor, let stage else { return }
        let frame = window.frame
        let half = (bodyHalfWidth() ?? 0.5) * frame.width
        floor.set(self, screen: stage.visibleFrame, span: (frame.midX - half)...(frame.midX + half))
    }

    private func bodyHalfWidth() -> CGFloat? {
        if halfWidth == nil, let walking = loadWalking(),
           let image = FrameRenderer.render(walking.animation, frame: character.standingFrame, pixelSize: CGSize(width: 275, height: 185)) {
            halfWidth = FrameRenderer.drawnHalfWidth(of: image)
        }
        return halfWidth
    }

    /// The positions along `stage`'s floor where he would stand in front of someone else.
    private func blocked(on stage: Stage) -> [ClosedRange<CGFloat>] {
        guard let floor else { return [] }
        let others = floor.spans(except: self, on: stage.visibleFrame)
        guard !others.isEmpty else { return [] }
        let half = (bodyHalfWidth() ?? 0.5) * stage.size.width
        // The offset that puts his middle at screen x is x - minX - width / 2.
        let shift = stage.visibleFrame.minX + stage.size.width / 2
        return others.map { ($0.lowerBound - Floor.gap - half - shift)...($0.upperBound + Floor.gap + half - shift) }
    }

    /// The nearest place to `x` on `stage`'s floor where he is in no one's way; `x` itself if there is nowhere.
    private func freeSpot(near x: CGFloat, on stage: Stage) -> CGFloat {
        Floor.nearestFree(to: x, in: 0...stage.maxX, blocked: blocked(on: stage)) ?? x
    }

    /// Where to stroll to next, staying between whoever stands either side of him.
    private func nextWalkStop(on stage: Stage) -> CGFloat {
        let room = Floor.room(around: offset, in: 0...stage.maxX, blocked: blocked(on: stage))
        return room.lowerBound + Choreography.nextWalkStop(
            from: offset - room.lowerBound, facing: facing, maxX: room.upperBound - room.lowerBound, using: &rng)
    }

    /// Where he waves from on `stage`: the middle, or as near it as he can stand without being in front of anyone.
    private func alertSpot(on stage: Stage) -> CGFloat {
        freeSpot(near: stage.maxX / 2, on: stage)
    }

    // MARK: Visiting

    /// Drops in as a visitor at the middle of the screen, beside whoever is already there, and waves with `text` until `leave()`.
    /// For a character called on by a command, not the one who lives on the desktop.
    public func visit(saying text: String) {
        alertText = text
        wantsVisible = true
        startCursorWatch()
        guard loop == nil, let stage = placeOnFloor() else { return }
        offset = alertSpot(on: stage)
        moveTo(stage.entranceOrigin(x: offset))
        mode = .entrance
        window.show()
        loop = Task { [weak self] in await self?.begin(on: stage, entrance: true) }
    }

    /// Pops out of sight and stays gone.
    public func leave() async {
        cancelLoop()
        mode = .idle
        await window.pop(visible: false)
        stop()
    }

    /// Space between his head and the bubble's tail, as a fraction of his window's height.
    static let bubbleGap: CGFloat = 0.1

    /// Puts `text` just over his head. His window has room above him for acts that reach up, so the
    /// bubble goes by where the art actually stops, not by the top of the window.
    private func say(_ text: String) {
        guard let screen = stage?.visibleFrame ?? visibleFrame() else { return }
        if headTop == nil, let walking = loadWalking(),
           let image = FrameRenderer.render(walking.animation, frame: character.standingFrame, pixelSize: CGSize(width: 275, height: 185)) {
            headTop = FrameRenderer.drawnTop(of: image)
        }
        var head = window.frame
        // A little air between the tail and his head, in proportion to his size, so a wave does not touch it.
        head.size.height *= min((headTop ?? 1) + Self.bubbleGap, 1)
        bubble.show(text, above: head, within: screen)
    }

    // MARK: Cursor

    /// Eight looks a second is plenty to notice a cursor and costs next to nothing. While he watches
    /// it he looks thirty times a second, fast enough to feel the cursor rubbed back and forth over him.
    static let glanceInterval: TimeInterval = 1.0 / 8
    static let watchInterval: TimeInterval = 1.0 / 30

    private func startCursorWatch() {
        guard cursorTimer == nil else { return }
        watchCursor(every: Self.glanceInterval)
    }

    private func watchCursor(every interval: TimeInterval) {
        guard cursorTimer?.timeInterval != interval else { return }
        cursorTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    /// How long you must be away before he naps.
    public static let napAfter: TimeInterval = 5 * 60

    /// How long he watches before going back to his routine, and how long the cursor must be gone first.
    static let longestWatch: TimeInterval = 20
    static let watchLinger: TimeInterval = 1

    private func cursorTick() {
        defer { watchCursor(every: mode == .watching ? Self.watchInterval : Self.glanceInterval) }
        guard let stage else { return }
        let now = Date()
        let cursor = cursorLocation()
        let gaze = Gaze.toward(cursor, from: window.frame)
        switch mode {
        case .routine:
            if idleTime() >= Self.napAfter { return nap() }
            guard let gaze else {
                ignoresCursorUntilItLeaves = false
                return
            }
            guard onFloor, window.opacity == 1, !ignoresCursorUntilItLeaves else { return }
            cancelLoop()
            mode = .watching
            watchStarted = now
            cursorLastNear = now
            petting.reset()
            look(gaze)
        case .napping:
            if idleTime() < Self.napAfter { wake() }
        case .watching:
            if window.frame.contains(cursor), petting.track(x: cursor.x, at: now) { return pet() }
            if let gaze { cursorLastNear = now; look(gaze) }
            let bored = now.timeIntervalSince(watchStarted) > Self.longestWatch
            guard bored || now.timeIntervalSince(cursorLastNear) > Self.watchLinger else { return }
            ignoresCursorUntilItLeaves = bored
            mustWalkNext = true
            mode = .routine
            loop = Task { [weak self] in await self?.carryOn(on: stage) }
        default:
            break
        }
    }

    /// Asleep where he stands until you come back: his nap act on a loop, or just standing still.
    private func nap() {
        interrupt(as: .napping) { performer, _ in
            let name = performer.character.acts(for: .nap).first
            let napping = name.flatMap { performer.catalog.load($0) }
            if napping == nil { performer.standStill() }
            // Never returns on its own: only waking him (or an alert) ends the nap.
            while !Task.isCancelled {
                if let napping { await performer.window.play(napping) } else { try? await Task.sleep(for: .seconds(60)) }
            }
        }
    }

    private func wake() {
        interrupt(as: .reacting) { performer, _ in await performer.play(.wake) }
    }

    /// Their pet act, or a celebration for someone who has none drawn yet.
    private func pet() {
        interrupt(as: .reacting) { performer, _ in
            await performer.play(performer.character.acts(for: .pet).isEmpty ? .celebrate : .pet)
        }
    }

    private func look(_ gaze: Gaze) {
        if gaze.facing != facing { face(gaze.facing) }
        if gaze.eyes == .up {
            if looking == nil { looking = catalog.load("looking") }
            if let looking {
                window.pose(looking, frame: character.lookUpFrame)
                return
            }
        }
        standStill()
    }

    /// The launch entrance: he falls from above the screen, lands, waves once, and then stands
    /// where he landed until the spotlight has faded.
    private func dropIn(on stage: Stage, thenStandAs walking: CharacterAnimation) async {
        guard let waving = catalog.load("waving") else { return }
        let top = stage.entranceOrigin(x: offset)
        var falling: TimeInterval = 0
        moveTo(top)
        window.pose(walking, frame: character.standingFrame)
        let spotlight = SpotlightWindow(frame: stage.spotlightFrame(x: offset))
        self.spotlight = spotlight
        spotlight.fadeIn()
        await ticker.run(on: window) { [weak self] elapsed in
            guard let self else { return true }
            // Sum honored ticks rather than reading a clock, so a stalled frame cannot skip the fall.
            falling += min(max(elapsed, 0), Choreography.maxStep)
            let drop = Choreography.drop(from: top.y, to: stage.floorY, elapsed: falling)
            moveTo(CGPoint(x: top.x, y: drop.y))
            return drop.landed
        }
        if Task.isCancelled { return }
        await window.play(waving)
        if Task.isCancelled { return }
        window.pose(walking, frame: character.standingFrame)
        await spotlight.fadeOut()
        self.spotlight = nil
    }

    /// Hides him the way he arrived, played backwards: the spotlight comes on at the middle of the floor,
    /// he walks into it, waves goodbye, and is lifted off the top of the screen before the light goes out.
    /// `start()` part-way through calls it off.
    public func beamUp() {
        guard wantsVisible, mode != .leaving else { return }
        guard loop != nil, stage != nil, let walking = loadWalking() else { return stop() }
        cancelLoop()
        mode = .leaving
        loop = Task { [weak self] in
            guard let self else { return }
            await returnToFloor()
            guard !Task.isCancelled, let stage = self.stage else { return }
            await exit(on: stage, with: walking)
            if !Task.isCancelled { stop() }
        }
    }

    private func exit(on stage: Stage, with walking: CharacterAnimation) async {
        let centre = stage.maxX / 2
        let spotlight = SpotlightWindow(frame: stage.spotlightFrame(x: centre))
        self.spotlight = spotlight
        spotlight.fadeIn()

        // From further off he pops over to the edge of the light, so the walk in is always a few steps.
        let approach = stage.size.width * Stage.exitApproachFactor
        if abs(offset - centre) > approach {
            await window.pop(visible: false)
            if Task.isCancelled { return }
            offset = min(max(offset < centre ? centre - approach : centre + approach, 0), stage.maxX)
            moveTo(stage.floorOrigin(x: offset))
            face(offset < centre ? .right : .left)
            standStill()
            await window.pop(visible: true)
            if Task.isCancelled { return }
        }
        await walk(to: centre, on: stage, with: walking)
        if Task.isCancelled { return }

        face(.right)
        if let waving = catalog.load("waving") { await window.play(waving) }
        if Task.isCancelled { return }
        standStill()

        let floor = stage.floorOrigin(x: offset)
        // No further than where the entrance begins: the ticks that move him stop once his window is off the screen.
        let gone = stage.entranceOrigin(x: offset).y
        var rising: TimeInterval = 0
        onFloor = false
        await ticker.run(on: window) { [weak self] elapsed in
            guard let self else { return true }
            rising += min(max(elapsed, 0), Choreography.maxStep)
            let rise = Choreography.rise(from: floor.y, to: gone, elapsed: rising)
            moveTo(CGPoint(x: floor.x, y: rise.y))
            return rise.gone
        }
        if Task.isCancelled { return }
        window.hide()
        await spotlight.fadeOut()
        self.spotlight = nil
    }

    private func perform(_ act: CharacterAnimation) async {
        for _ in 0..<Choreography.plays(forFrameCount: act.frameCount) {
            await window.play(act)
            if Task.isCancelled { return }
        }
    }

}
