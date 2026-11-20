import AppKit

enum AnnotationTool: String, CaseIterable, Identifiable, Sendable {
    case pen = "Pen"
    case arrow = "Arrow"
    case rectangle = "Rectangle"
    case highlight = "Highlight"
    case text = "Text"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .pen: return "pencil.tip"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "square"
        case .highlight: return "highlighter"
        case .text: return "character"
        }
    }
}

enum AnnotationColor: String, CaseIterable, Identifiable, Sendable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case blue = "Blue"
    case white = "White"
    case black = "Black"

    var id: String { rawValue }

    var nsColor: NSColor {
        switch self {
        case .red: return NSColor(calibratedRed: 0.95, green: 0.26, blue: 0.28, alpha: 1.0)
        case .orange: return NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.18, alpha: 1.0)
        case .yellow: return NSColor(calibratedRed: 0.98, green: 0.82, blue: 0.20, alpha: 1.0)
        case .green: return NSColor(calibratedRed: 0.30, green: 0.85, blue: 0.45, alpha: 1.0)
        case .blue: return NSColor(calibratedRed: 0.22, green: 0.60, blue: 0.98, alpha: 1.0)
        case .white: return NSColor.white
        case .black: return NSColor.black
        }
    }
}

struct AnnotationItem: Identifiable, Equatable {
    let id: UUID
    var tool: AnnotationTool
    var startPoint: CGPoint
    var endPoint: CGPoint
    var points: [CGPoint]
    var text: String
    var color: NSColor
    var strokeWidth: CGFloat

    init(id: UUID = UUID(), tool: AnnotationTool, startPoint: CGPoint, endPoint: CGPoint,
         points: [CGPoint] = [], text: String = "", color: NSColor, strokeWidth: CGFloat) {
        self.id = id
        self.tool = tool
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.points = points.isEmpty ? [startPoint, endPoint] : points
        self.text = text
        self.color = color
        self.strokeWidth = strokeWidth
    }
}

final class ScreenshotAnnotationHistory {
    private(set) var items: [AnnotationItem] = []
    private var undoStack: [[AnnotationItem]] = []
    private var redoStack: [[AnnotationItem]] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func add(_ item: AnnotationItem) {
        undoStack.append(items)
        redoStack.removeAll()
        items.append(item)
    }

    func updateLastItem(_ item: AnnotationItem) {
        guard !items.isEmpty else { return }
        items[items.count - 1] = item
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(items)
        items = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(items)
        items = next
    }

    func clear() {
        if !items.isEmpty {
            undoStack.append(items)
            redoStack.removeAll()
            items.removeAll()
        }
    }
}

enum ScreenshotRenderer {
    /// Draws an individual annotation item onto an NSGraphicsContext.
    /// Coordinates must already be translated to the selection coordinate space.
    static func draw(item: AnnotationItem, in context: CGContext, scale: CGFloat = 1.0) {
        context.saveGState()
        defer { context.restoreGState() }

        let strokeWidth = item.strokeWidth * scale

        switch item.tool {
        case .pen:
            guard item.points.count > 1 else { return }
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.beginPath()
            context.move(to: item.points[0])
            for i in 1..<item.points.count {
                context.addLine(to: item.points[i])
            }
            context.strokePath()

        case .highlight:
            guard item.points.count > 1 else { return }
            let hlColor = item.color.withAlphaComponent(0.35)
            context.setStrokeColor(hlColor.cgColor)
            context.setLineWidth(max(16.0 * scale, strokeWidth * 2.5))
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setBlendMode(.normal)
            context.beginPath()
            context.move(to: item.points[0])
            for i in 1..<item.points.count {
                context.addLine(to: item.points[i])
            }
            context.strokePath()

        case .rectangle:
            let rect = CGRect(
                x: min(item.startPoint.x, item.endPoint.x),
                y: min(item.startPoint.y, item.endPoint.y),
                width: abs(item.endPoint.x - item.startPoint.x),
                height: abs(item.endPoint.y - item.startPoint.y)
            )
            guard rect.width > 1 && rect.height > 1 else { return }
            context.setStrokeColor(item.color.cgColor)
            context.setLineWidth(strokeWidth)
            context.setLineJoin(.miter)
            let path = CGPath(roundedRect: rect, cornerWidth: 3 * scale, cornerHeight: 3 * scale, transform: nil)
            context.addPath(path)
            context.strokePath()

        case .arrow:
            drawArrow(from: item.startPoint, to: item.endPoint, color: item.color, strokeWidth: strokeWidth, in: context, scale: scale)

        case .text:
            drawText(item.text, at: item.startPoint, color: item.color, scale: scale)
        }
    }

    /// Draws a directional arrow from start to end with an arrowhead.
    static func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, strokeWidth: CGFloat, in context: CGContext, scale: CGFloat) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 4 else { return }

        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Draw arrow shaft
        context.beginPath()
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()

        // Draw arrowhead
        let headLength = min(length * 0.45, max(14 * scale, strokeWidth * 3.5))
        let headAngle: CGFloat = .pi / 6.0 // 30 degrees

        let angle = atan2(dy, dx)
        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        context.beginPath()
        context.move(to: end)
        context.addLine(to: p1)
        context.addLine(to: p2)
        context.closePath()
        context.fillPath()
    }

    /// Renders text with a subtle readable background tag.
    static func drawText(_ text: String, at point: CGPoint, color: NSColor, scale: CGFloat) {
        guard !text.isEmpty else { return }
        let fontSize = max(13.0, 16.0 * scale)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let attrString = NSAttributedString(string: text, attributes: attributes)
        let size = attrString.size()

        // Background pill for crisp contrast against any desktop background
        let bgRect = CGRect(x: point.x - 4 * scale, y: point.y - 2 * scale, width: size.width + 8 * scale, height: size.height + 4 * scale)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 4 * scale, yRadius: 4 * scale)
        NSColor.black.withAlphaComponent(0.65).setFill()
        bgPath.fill()

        attrString.draw(at: point)
    }

    /// Composites the annotations directly over the cropped source image at full native Retina resolution.
    /// - Parameters:
    ///   - sourceImage: The full desktop screenshot CGImage.
    ///   - selectionRect: The user selection in AppKit view coordinates.
    ///   - desktopBounds: The full desktop bounds in AppKit view coordinates.
    ///   - annotations: The annotation items in AppKit view coordinates.
    ///   - screenScale: Backing scale factor (e.g. 2.0 for Retina).
    static func composite(
        sourceImage: CGImage,
        selectionRect: CGRect,
        desktopBounds: CGRect,
        annotations: [AnnotationItem],
        screenScale: CGFloat
    ) -> (image: NSImage, pngData: Data)? {
        // In CoreGraphics CGImage, row 0 is at the top of the desktop.
        // In AppKit view coordinates, y=0 is at the bottom of the desktop.
        // The top of selectionRect is selectionRect.maxY.
        // Distance of selection top from desktop top in pixels:
        let cropY = (desktopBounds.height - selectionRect.maxY) * screenScale
        let pixelCrop = CGRect(
            x: selectionRect.origin.x * screenScale,
            y: max(0, cropY),
            width: selectionRect.size.width * screenScale,
            height: selectionRect.size.height * screenScale
        )

        let targetWidth = Int(round(pixelCrop.width))
        let targetHeight = Int(round(pixelCrop.height))
        guard targetWidth > 0, targetHeight > 0 else { return nil }

        // Crop the source image
        guard let croppedCG = sourceImage.cropping(to: pixelCrop) else { return nil }

        // Create bitmap context for compositing
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }

        // Draw cropped source image
        let drawRect = CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight)
        context.draw(croppedCG, in: drawRect)

        // Setup NSGraphicsContext for drawing annotations
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        // Annotations are in points in AppKit view coordinates.
        // Both the AppKit view and CGContext have y=0 at the bottom.
        // Convert to context coordinates (which start at 0, 0 with scaling).
        for item in annotations {
            var scaledItem = item
            scaledItem.startPoint = CGPoint(
                x: (item.startPoint.x - selectionRect.origin.x) * screenScale,
                y: (item.startPoint.y - selectionRect.origin.y) * screenScale
            )
            scaledItem.endPoint = CGPoint(
                x: (item.endPoint.x - selectionRect.origin.x) * screenScale,
                y: (item.endPoint.y - selectionRect.origin.y) * screenScale
            )
            scaledItem.points = item.points.map { pt in
                CGPoint(
                    x: (pt.x - selectionRect.origin.x) * screenScale,
                    y: (pt.y - selectionRect.origin.y) * screenScale
                )
            }
            draw(item: scaledItem, in: context, scale: screenScale)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCG = context.makeImage() else { return nil }
        let pointSize = NSSize(width: selectionRect.width, height: selectionRect.height)
        let finalImage = NSImage(cgImage: finalCG, size: pointSize)

        let rep = NSBitmapImageRep(cgImage: finalCG)
        rep.size = pointSize
        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }

        return (finalImage, pngData)
    }

    /// Convenience overload with cropRect for backwards compatibility with tests.
    static func composite(
        sourceImage: CGImage,
        cropRect: CGRect,
        annotations: [AnnotationItem],
        screenScale: CGFloat
    ) -> (image: NSImage, pngData: Data)? {
        let desktopHeight = CGFloat(sourceImage.height) / screenScale
        let effectiveDesktopHeight = max(desktopHeight, cropRect.maxY)
        let desktopBounds = CGRect(x: 0, y: 0, width: CGFloat(sourceImage.width) / screenScale, height: effectiveDesktopHeight)
        return composite(
            sourceImage: sourceImage,
            selectionRect: cropRect,
            desktopBounds: desktopBounds,
            annotations: annotations,
            screenScale: screenScale
        )
    }
}
