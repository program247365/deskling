import AppKit

/// Draws a stage spotlight: a soft cone of light widening from the top, and a pool where it meets the floor.
private final class SpotlightView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let light = { (alpha: CGFloat) in CGColor(red: 1, green: 0.96, blue: 0.84, alpha: alpha) }
        let colors = CGColorSpaceCreateDeviceRGB()

        // The beam: nested cones, each a little narrower and brighter, so the edges fall off softly.
        let layers = 7
        for layer in 0..<layers {
            let inset = CGFloat(layer) / CGFloat(layers)
            let topHalf = bounds.width * 0.07 * (1 - inset * 0.6)
            let bottomHalf = bounds.width * 0.5 * (1 - inset * 0.55)
            let cone = CGMutablePath()
            cone.move(to: CGPoint(x: bounds.midX - topHalf, y: bounds.maxY))
            cone.addLine(to: CGPoint(x: bounds.midX + topHalf, y: bounds.maxY))
            cone.addLine(to: CGPoint(x: bounds.midX + bottomHalf, y: bounds.minY))
            cone.addLine(to: CGPoint(x: bounds.midX - bottomHalf, y: bounds.minY))
            cone.closeSubpath()
            context.saveGState()
            context.addPath(cone)
            context.clip()
            // Brighter at the lamp, thinning toward the floor.
            let gradient = CGGradient(colorsSpace: colors, colors: [light(0.07), light(0.025)] as CFArray, locations: [0, 1])!
            context.drawLinearGradient(
                gradient, start: CGPoint(x: bounds.midX, y: bounds.maxY),
                end: CGPoint(x: bounds.midX, y: bounds.minY), options: [])
            context.restoreGState()
        }

        // The pool on the floor: a flattened radial glow under him.
        let poolHeight = bounds.width * 0.22
        context.saveGState()
        context.translateBy(x: bounds.midX, y: bounds.minY + poolHeight * 0.35)
        context.scaleBy(x: 1, y: poolHeight / bounds.width)
        let pool = CGGradient(colorsSpace: colors, colors: [light(0.5), light(0.18), light(0)] as CFArray, locations: [0, 0.55, 1])!
        context.drawRadialGradient(
            pool, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: bounds.width * 0.5, options: [])
        context.restoreGState()
    }
}

/// A click-through window holding the spotlight for Clawd's launch entrance. It exists only for those few seconds.
@MainActor
public final class SpotlightWindow {
    private let panel: NSPanel

    public init(frame: CGRect) {
        // The stage stops under the menubar, but a lamp hangs from the very top of the screen.
        var frame = frame
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            frame.size.height = screen.frame.maxY - frame.minY
        }
        panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // One below Clawd's window, so the light falls behind him.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.contentView = SpotlightView(frame: CGRect(origin: .zero, size: frame.size))
        panel.alphaValue = 0
    }

    public func fadeIn() {
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }, completionHandler: nil)
    }

    /// Fades the light out, removes the window, and returns once it is dark.
    public func fadeOut() async {
        let duration = 0.7
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            panel.animator().alphaValue = 0
        }, completionHandler: nil)
        try? await Task.sleep(for: .seconds(duration))
        panel.orderOut(nil)
    }

    /// Removes the window at once.
    public func close() {
        panel.orderOut(nil)
    }
}
