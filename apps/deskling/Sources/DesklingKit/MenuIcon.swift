import AppKit

/// A character's menubar icon, made the way Clawd's committed one is: their standing pose as a
/// template silhouette, with the eyes cut out so the shape reads as them.
@MainActor
enum MenuIcon {
    /// Tallest icon, in pixels at 2x (18pt).
    static let maxHeight = 36

    static func make(for character: Character) -> NSImage? {
        guard let walking = character.catalog.load("walking"),
              // One rendered pixel per 10 Lottie units: each art pixel is a 10 x 10 block.
              let frame = FrameRenderer.render(walking.animation, frame: character.standingFrame, pixelSize: CGSize(width: 275, height: 185))
        else { return nil }
        guard let mask = silhouette(of: frame, holes: character.iconHoles) else { return nil }
        let rows = mask.count, columns = mask[0].count
        // Whole pixels per art pixel, so the icon stays crisp.
        let scale = max(1, maxHeight / rows)
        let width = columns * scale, height = rows * scale
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for (row, line) in mask.enumerated() {
            for (column, filled) in line.enumerated() where filled {
                // y-up: the first row is the top.
                context.fill(CGRect(x: column * scale, y: (rows - 1 - row) * scale, width: scale, height: scale))
            }
        }
        guard let image = context.makeImage() else { return nil }
        let icon = NSImage(cgImage: image, size: NSSize(width: CGFloat(width) / 2, height: CGFloat(height) / 2))
        icon.isTemplate = true
        return icon
    }

    /// Rim thickness of the hidden icon, in pixels at 2x (1pt).
    static let rimWidth = 2

    /// The same icon with only its rim left, shown while the character is hidden.
    static func hollow(_ icon: NSImage) -> NSImage? {
        let width = Int(icon.size.width * 2), height = Int(icon.size.height * 2)
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            icon.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        guard drawn else { return nil }

        let opaque = { (x: Int, y: Int) in
            x >= 0 && y >= 0 && x < width && y < height && data[(y * width + x) * 4 + 3] > 127
        }
        // A pixel stays when it is opaque and within the rim of a transparent pixel or the edge.
        var rim = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width where opaque(x, y) {
                let nearEmpty = (-rimWidth...rimWidth).contains { dy in
                    (-rimWidth...rimWidth).contains { dx in !opaque(x + dx, y + dy) }
                }
                if nearEmpty { rim[(y * width + x) * 4 + 3] = 255 }
            }
        }
        guard let provider = CGDataProvider(data: Data(rim) as CFData),
              let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        let hollow = NSImage(cgImage: image, size: icon.size)
        hollow.isTemplate = true
        return hollow
    }

    /// The art pixels (sampled at each 10 x 10 block's centre) that are opaque and not a hole color,
    /// cropped to the figure. Rows run top to bottom.
    static func silhouette(of image: CGImage, holes: [(Int, Int, Int)]) -> [[Bool]]? {
        let width = image.width, height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The art grid starts 36 x 50 Lottie units in: 3.6 and 5 rendered pixels.
        var grid: [[Bool]] = []
        for row in 0..<18 {
            var line: [Bool] = []
            for column in 0..<27 {
                let x = Int(3.6 + Double(column) * 10 + 5), y = 5 + row * 10 + 5
                let index = (y * width + x) * 4
                let (r, g, b, a) = (Int(data[index]), Int(data[index + 1]), Int(data[index + 2]), data[index + 3])
                let isHole = holes.contains { abs($0.0 - r) <= 40 && abs($0.1 - g) <= 40 && abs($0.2 - b) <= 40 }
                line.append(a > 127 && !isHole)
            }
            grid.append(line)
        }
        let rows = grid.indices.filter { grid[$0].contains(true) }
        let columns = (0..<27).filter { column in grid.contains { $0[column] } }
        guard let top = rows.first, let bottom = rows.last, let left = columns.first, let right = columns.last
        else { return nil }
        return grid[top...bottom].map { Array($0[left...right]) }
    }
}
