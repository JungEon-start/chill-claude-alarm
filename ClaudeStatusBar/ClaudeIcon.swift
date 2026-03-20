import AppKit
import CoreImage

/// Renders the Claude character icon for the menu bar.
/// Loads PNG from ~/.claude-status/icon.png and applies CIFilter tinting per status.
/// Falls back to a built-in pixel grid if no PNG is found.
/// Supports bounce animation for the "running" state.
struct ClaudeIcon {
    private static let targetHeight: CGFloat = 18.0
    static let frameCount = 6
    private static let bounceOffsets: [CGFloat] = [0, 1, 2, 3, 2, 1]

    // Cache: final frame per status+frame
    private static var tintedCache: [ClaudeStatus: NSImage] = [:]
    private static var frameCache: [String: NSImage] = [:]
    // Per-status image cache: icon-running.png, icon-idle.png, etc.
    private static var statusImages: [ClaudeStatus: NSImage?] = [:]
    private static var baseImage: NSImage?
    private static var baseImageLoaded = false

    static func render(for status: ClaudeStatus, frame: Int = 0) -> NSImage {
        let key = "\(status.rawValue)-\(frame)"
        if let cached = frameCache[key] { return cached }

        // Get or create tinted base image (no bounce yet)
        let base: NSImage
        if let cached = tintedCache[status] {
            base = cached
        } else {
            // Priority: icon-{status}.png → icon.png (tinted) → pixel grid
            if let statusImg = loadStatusImage(for: status) {
                base = statusImg
            } else if let loaded = loadImage() {
                base = applyTint(to: loaded, for: status)
            } else {
                base = fallbackGrid(for: status)
            }
            tintedCache[status] = base
        }

        // Badge dots: blinking for permission_required/completed, static for error
        let result: NSImage
        if status == .error {
            result = addBadgeDot(to: base, color: NSColor(red: 0.96, green: 0.26, blue: 0.21, alpha: 1.0))
        } else if (status == .permissionRequired || status == .completed) && frame % 2 == 0 {
            result = addBadgeDot(to: base, color: status == .permissionRequired
                ? NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0)
                : NSColor(red: 0.3, green: 0.85, blue: 0.4, alpha: 1.0))
        } else {
            result = base
        }

        frameCache[key] = result
        return result
    }

    /// Draw a colored circle badge at the top-right corner.
    private static func addBadgeDot(to image: NSImage, color: NSColor) -> NSImage {
        let dotSize: CGFloat = 6.0
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(at: .zero, from: NSRect(origin: .zero, size: image.size),
                   operation: .sourceOver, fraction: 1.0)
        color.setFill()
        let dotRect = NSRect(
            x: image.size.width - dotSize - 1,
            y: image.size.height - dotSize - 1,
            width: dotSize, height: dotSize
        )
        NSBezierPath(ovalIn: dotRect).fill()
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    static func clearCache() {
        tintedCache.removeAll()
        frameCache.removeAll()
        statusImages.removeAll()
        baseImage = nil
        baseImageLoaded = false
    }

    // MARK: - Bounce Animation

    private static func applyBounce(to image: NSImage, frame: Int) -> NSImage {
        let maxBounce = bounceOffsets.max() ?? 0
        let offset = bounceOffsets[frame % bounceOffsets.count]
        let canvasSize = NSSize(width: image.size.width, height: image.size.height + maxBounce)

        let result = NSImage(size: canvasSize)
        result.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: canvasSize).fill()
        image.draw(
            at: NSPoint(x: 0, y: offset),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        result.unlockFocus()
        result.isTemplate = false
        return result
    }

    // MARK: - PNG Loading

    /// Load per-status image: ~/.claude-status/icon-{status}.png
    private static func loadStatusImage(for status: ClaudeStatus) -> NSImage? {
        if let cached = statusImages[status] { return cached }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let filename = "icon-\(status.rawValue).png"
        let path = home.appendingPathComponent(".claude-status/\(filename)")
        guard let raw = NSImage(contentsOf: path) else {
            statusImages[status] = nil
            return nil
        }

        let height: CGFloat = (status == .running || status == .completed || status == .permissionRequired || status == .error) ? 24.0 : targetHeight
        let result = scaleForMenuBar(removeBackground(from: raw), height: height)
        statusImages[status] = result
        return result
    }

    /// Load default image: ~/.claude-status/icon.png
    private static func loadImage() -> NSImage? {
        if baseImageLoaded { return baseImage }
        baseImageLoaded = true

        let home = FileManager.default.homeDirectoryForCurrentUser
        let path = home.appendingPathComponent(".claude-status/icon.png")
        guard let raw = NSImage(contentsOf: path) else { return nil }

        let result = scaleForMenuBar(removeBackground(from: raw))
        baseImage = result
        return result
    }

    /// Scale image to menu bar height with nearest-neighbor interpolation.
    private static func scaleForMenuBar(_ image: NSImage, height: CGFloat? = nil) -> NSImage {
        let scale = (height ?? targetHeight) / image.size.height
        let newSize = NSSize(
            width: round(image.size.width * scale),
            height: round(image.size.height * scale)
        )
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        NSColor.clear.set()
        NSRect(origin: .zero, size: newSize).fill()
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: NSRect(origin: .zero, size: newSize))
        scaled.unlockFocus()
        return scaled
    }

    /// Removes background pixels by auto-detecting the background color from corners.
    /// Skips removal if the image already has transparent pixels.
    private static func removeBackground(from image: NSImage) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return image }

        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        guard w > 0 && h > 0 else { return image }

        // Check if image already has transparency → skip
        for y in 0..<h {
            for x in 0..<w {
                if let c = bitmap.colorAt(x: x, y: y), c.alphaComponent < 0.5 {
                    return image  // already has transparency
                }
            }
        }

        // Sample corner pixels to detect background color
        let corners = [(0,0), (w-1,0), (0,h-1), (w-1,h-1)]
        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0
        var count: CGFloat = 0
        for (cx, cy) in corners {
            if let c = bitmap.colorAt(x: cx, y: cy) {
                bgR += c.redComponent
                bgG += c.greenComponent
                bgB += c.blueComponent
                count += 1
            }
        }
        guard count > 0 else { return image }
        bgR /= count; bgG /= count; bgB /= count

        // Remove pixels close to the background color
        let threshold: CGFloat = 0.15
        for y in 0..<h {
            for x in 0..<w {
                guard let c = bitmap.colorAt(x: x, y: y) else { continue }
                let dist = abs(c.redComponent - bgR) + abs(c.greenComponent - bgG) + abs(c.blueComponent - bgB)
                if dist < threshold {
                    bitmap.setColor(.clear, atX: x, y: y)
                }
            }
        }

        let result = NSImage(size: image.size)
        result.addRepresentation(bitmap)
        return result
    }

    // MARK: - CIFilter Tinting

    private static func applyTint(to image: NSImage, for status: ClaudeStatus) -> NSImage {
        guard let tiffData = image.tiffRepresentation,
              var ci = CIImage(data: tiffData) else { return image }

        switch status {
        case .idle:
            if let f = CIFilter(name: "CIColorControls") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(NSNumber(value: 0.0), forKey: kCIInputSaturationKey)
                if let o = f.outputImage { ci = o }
            }
        case .running:
            break
        case .permissionRequired:
            if let f = CIFilter(name: "CIHueAdjust") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(NSNumber(value: 0.75), forKey: kCIInputAngleKey)
                if let o = f.outputImage { ci = o }
            }
        case .completed:
            if let f = CIFilter(name: "CIHueAdjust") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(NSNumber(value: 1.85), forKey: kCIInputAngleKey)
                if let o = f.outputImage { ci = o }
            }
        case .error:
            if let f = CIFilter(name: "CIHueAdjust") {
                f.setValue(ci, forKey: kCIInputImageKey)
                f.setValue(NSNumber(value: -0.25), forKey: kCIInputAngleKey)
                if let o = f.outputImage { ci = o }
            }
        }

        let rep = NSCIImageRep(ciImage: ci)
        let result = NSImage(size: image.size)
        result.addRepresentation(rep)
        result.isTemplate = false
        return result
    }

    // MARK: - Fallback Pixel Grid

    // High-res pixel grid: 26 wide x 16 tall (2x detail, 1pt per cell)
    // 0 = transparent, 1 = body color
    private static let grid: [[Int]] = [
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],  // top
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,0,0,0,0],  // eyes (wider apart)
        [1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1],  // arms + eyes (3 rows)
        [1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1],
        [1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],  // body
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],  // legs: paired
        [0,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
        [0,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
        [0,0,0,0,0,0,1,1,0,1,1,0,0,0,0,1,1,0,1,1,0,0,0,0,0,0],
    ]

    // Running state: character working on a laptop
    // 0 = transparent, 1 = body color, 2 = laptop color (faceColor)
    // Laptop = outlined screen (narrow) + solid keyboard (wider)
    private static let runningGrid: [[Int]] = [
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],  // head
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,0,0,0,0],  // eyes
        [0,0,0,0,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,0,0,1,1,1,1,1,1,1,1,0,0,1,1,1,0,0,0,0],
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],  // body
        [0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0],
        [0,0,0,0,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0],  // screen top
        [0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0],  // screen (hollow)
        [0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0],  // screen (hollow)
        [0,0,0,0,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0,0,0],  // screen bottom
        [0,0,1,1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,1,1,0,0],  // hands + keyboard
        [0,0,0,0,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,0,0,0,0],  // keyboard base
        [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
    ]

    private static func fallbackGrid(for status: ClaudeStatus) -> NSImage {
        let activeGrid = status == .running ? runningGrid : grid
        let rows = activeGrid.count
        let cols = activeGrid[0].count
        let px: CGFloat = 1.0
        let w = CGFloat(cols) * px
        let h = CGFloat(rows) * px

        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()

        let body = status.bodyColor
        let face = status.faceColor
        for row in 0..<rows {
            for col in 0..<cols {
                let v = activeGrid[row][col]
                if v == 0 { continue }
                (v == 1 ? body : face).setFill()
                NSRect(
                    x: CGFloat(col) * px,
                    y: CGFloat(rows - 1 - row) * px,
                    width: px, height: px
                ).fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = false

        // Scale down idle by 20%
        if status == .idle {
            let scale: CGFloat = 0.8
            let newSize = NSSize(width: round(w * scale), height: round(h * scale))
            let scaled = NSImage(size: newSize)
            scaled.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .none
            image.draw(in: NSRect(origin: .zero, size: newSize))
            scaled.unlockFocus()
            scaled.isTemplate = false
            return scaled
        }

        return image
    }
}
