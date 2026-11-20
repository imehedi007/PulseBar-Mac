import AppKit
import SwiftUI

final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScreenshotOverlayController: NSObject {
    private var windows: [NSWindow] = []
    private var canvasViews: [ScreenshotCanvasView] = []
    private var keyMonitor: Any?
    var onComplete: ((NSImage, Data, Bool) -> Void)? // image, pngData, isSave
    var onCancel: (() -> Void)?

    func show(capturedImage: CGImage, screenFrame: CGRect, scaleFactor: CGFloat) {
        close()

        let window = ScreenshotOverlayWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true

        let canvas = ScreenshotCanvasView(
            frame: CGRect(origin: .zero, size: screenFrame.size),
            capturedImage: capturedImage,
            screenFrame: screenFrame,
            scaleFactor: scaleFactor
        )

        canvas.onCopy = { [weak self] image, data in
            self?.close()
            self?.onComplete?(image, data, false)
        }

        canvas.onSave = { [weak self] image, data in
            self?.close()
            self?.onComplete?(image, data, true)
        }

        canvas.onCancel = { [weak self] in
            self?.close()
            self?.onCancel?()
        }

        window.contentView = canvas
        windows.append(window)
        canvasViews.append(canvas)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.makeFirstResponder(canvas)
        ScreenshotCanvasView.precisionCursor.set()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak canvas] event in
            if canvas?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }
    }

    func close() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        canvasViews.removeAll()
    }
}

// MARK: - Canvas View
@MainActor
final class ScreenshotCanvasView: NSView, NSTextFieldDelegate {
    let capturedImage: CGImage
    let screenFrame: CGRect
    let scaleFactor: CGFloat

    var selectionRect: CGRect? {
        didSet {
            updateToolbarPosition()
            needsDisplay = true
        }
    }

    var activeTool: AnnotationTool = .pen {
        didSet {
            toolbarHosting?.rootView = makeToolbarView()
            updateCursor()
        }
    }

    var activeColor: AnnotationColor = .red {
        didSet {
            toolbarHosting?.rootView = makeToolbarView()
        }
    }

    var strokeWidth: CGFloat = 3.5
    let history = ScreenshotAnnotationHistory()

    var onCopy: ((NSImage, Data) -> Void)?
    var onSave: ((NSImage, Data) -> Void)?
    var onCancel: (() -> Void)?

    static let precisionCursor: NSCursor = {
        let size = NSSize(width: 28, height: 28)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Outer shadow reticle
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            ctx.setLineWidth(3.0)
            ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: 16, height: 16))

            // Inner crisp white reticle
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: CGRect(x: 6, y: 6, width: 16, height: 16))

            // High-contrast crosshair ticks (black shadow backing)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.65).cgColor)
            ctx.setLineWidth(3.0)
            ctx.move(to: CGPoint(x: 14, y: 22)); ctx.addLine(to: CGPoint(x: 14, y: 27))
            ctx.move(to: CGPoint(x: 14, y: 6)); ctx.addLine(to: CGPoint(x: 14, y: 1))
            ctx.move(to: CGPoint(x: 6, y: 14)); ctx.addLine(to: CGPoint(x: 1, y: 14))
            ctx.move(to: CGPoint(x: 22, y: 14)); ctx.addLine(to: CGPoint(x: 27, y: 14))
            ctx.strokePath()

            // Inner white crosshair ticks
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 14, y: 22)); ctx.addLine(to: CGPoint(x: 14, y: 27))
            ctx.move(to: CGPoint(x: 14, y: 6)); ctx.addLine(to: CGPoint(x: 14, y: 1))
            ctx.move(to: CGPoint(x: 6, y: 14)); ctx.addLine(to: CGPoint(x: 1, y: 14))
            ctx.move(to: CGPoint(x: 22, y: 14)); ctx.addLine(to: CGPoint(x: 27, y: 14))
            ctx.strokePath()

            // Precision center target dot (Apple Cyan/Blue)
            ctx.setFillColor(NSColor(calibratedRed: 0.15, green: 0.65, blue: 1.0, alpha: 1.0).cgColor)
            ctx.fillEllipse(in: CGRect(x: 12.5, y: 12.5, width: 3, height: 3))

            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 14, y: 14))
    }()

    private var currentMousePoint: CGPoint?
    private var currentAnnotation: AnnotationItem?
    private var dragStart: CGPoint = .zero
    private var isSelecting = false
    private var isDrawing = false
    private var isMovingSelection = false
    private var resizingHandle: HandleType?
    private var dragOffset: CGPoint = .zero
    private var activeTextField: NSTextField?

    private var toolbarHosting: ScreenshotToolbarHostingView?

    enum HandleType: CaseIterable {
        case topLeft, topMid, topRight
        case midLeft, midRight
        case bottomLeft, bottomMid, bottomRight
    }

    init(frame: CGRect, capturedImage: CGImage, screenFrame: CGRect, scaleFactor: CGFloat) {
        self.capturedImage = capturedImage
        self.screenFrame = screenFrame
        self.scaleFactor = scaleFactor
        super.init(frame: frame)
        wantsLayer = true
        setupToolbar()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        currentMousePoint = pt
        updateCursor(at: pt)
        if selectionRect == nil {
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        currentMousePoint = nil
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateCursor(at: pt)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if let toolbar = toolbarHosting, !toolbar.isHidden {
            addCursorRect(toolbar.frame, cursor: .pointingHand)
        }
        if let sel = selectionRect {
            for handle in HandleType.allCases {
                let rect = rectForHandle(handle, in: sel)
                addCursorRect(rect, cursor: cursorForHandle(handle))
            }
            addCursorRect(sel, cursor: activeToolCursor)
        } else {
            addCursorRect(bounds, cursor: ScreenshotCanvasView.precisionCursor)
        }
    }

    private func updateCursor(at pt: CGPoint? = nil) {
        let targetPt = pt ?? currentMousePoint ?? .zero
        if let toolbar = toolbarHosting, !toolbar.isHidden, toolbar.frame.contains(targetPt) {
            NSCursor.pointingHand.set()
            return
        }
        if let sel = selectionRect {
            if let handle = handleAtPoint(targetPt, for: sel) {
                cursorForHandle(handle).set()
            } else if sel.contains(targetPt) {
                activeToolCursor.set()
            } else {
                ScreenshotCanvasView.precisionCursor.set()
            }
        } else {
            ScreenshotCanvasView.precisionCursor.set()
        }
    }

    private func cursorForHandle(_ handle: HandleType) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight, .topRight, .bottomLeft:
            return NSCursor.crosshair
        case .topMid, .bottomMid:
            return NSCursor.resizeUpDown
        case .midLeft, .midRight:
            return NSCursor.resizeLeftRight
        }
    }

    private var activeToolCursor: NSCursor {
        switch activeTool {
        case .text:
            return NSCursor.iBeam
        case .pen, .arrow, .rectangle, .highlight:
            return ScreenshotCanvasView.precisionCursor
        }
    }

    private func rectForHandle(_ handle: HandleType, in rect: CGRect) -> CGRect {
        let handleSize: CGFloat = 14.0
        let midX = rect.midX
        let midY = rect.midY
        let pt: CGPoint
        switch handle {
        case .topLeft: pt = CGPoint(x: rect.minX, y: rect.maxY)
        case .topMid: pt = CGPoint(x: midX, y: rect.maxY)
        case .topRight: pt = CGPoint(x: rect.maxX, y: rect.maxY)
        case .midLeft: pt = CGPoint(x: rect.minX, y: midY)
        case .midRight: pt = CGPoint(x: rect.maxX, y: midY)
        case .bottomLeft: pt = CGPoint(x: rect.minX, y: rect.minY)
        case .bottomMid: pt = CGPoint(x: midX, y: rect.minY)
        case .bottomRight: pt = CGPoint(x: rect.maxX, y: rect.minY)
        }
        return CGRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
    }

    // MARK: - Toolbar Setup
    private func setupToolbar() {
        let hosting = ScreenshotToolbarHostingView(rootView: makeToolbarView())
        hosting.isHidden = true
        addSubview(hosting)
        self.toolbarHosting = hosting
    }

    private func makeToolbarView() -> ScreenshotToolbarView {
        ScreenshotToolbarView(
            activeTool: activeTool,
            activeColor: activeColor,
            canUndo: history.canUndo,
            canRedo: history.canRedo,
            onSelectTool: { [weak self] tool in
                self?.activeTool = tool
            },
            onSelectColor: { [weak self] color in
                self?.activeColor = color
            },
            onUndo: { [weak self] in
                self?.history.undo()
                self?.toolbarHosting?.rootView = self?.makeToolbarView() ?? ScreenshotToolbarView.empty
                self?.needsDisplay = true
            },
            onRedo: { [weak self] in
                self?.history.redo()
                self?.toolbarHosting?.rootView = self?.makeToolbarView() ?? ScreenshotToolbarView.empty
                self?.needsDisplay = true
            },
            onCopy: { [weak self] in
                self?.performCopy()
            },
            onSave: { [weak self] in
                self?.performSave()
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )
    }

    private func updateToolbarPosition() {
        guard let sel = selectionRect, let toolbar = toolbarHosting else {
            toolbarHosting?.isHidden = true
            window?.invalidateCursorRects(for: self)
            return
        }

        toolbar.rootView = makeToolbarView()
        let idealSize = toolbar.fittingSize
        toolbar.frame.size = idealSize
        toolbar.isHidden = false

        // Position: prefer below selection, right aligned
        var originX = sel.maxX - idealSize.width
        var originY = sel.minY - idealSize.height - 12

        // Clamp horizontally
        originX = max(10, min(bounds.width - idealSize.width - 10, originX))

        // If not enough room below, place above selection
        if originY < 10 {
            originY = sel.maxY + 12
        }
        // If still offscreen at top, place inside bottom of selection
        if originY + idealSize.height > bounds.height - 10 {
            originY = sel.minY + 12
        }

        toolbar.frame.origin = CGPoint(x: originX, y: originY)
        window?.invalidateCursorRects(for: self)
        toolbar.window?.invalidateCursorRects(for: toolbar)
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw captured desktop image at 1:1 scale
        context.draw(capturedImage, in: bounds)

        // 2. Dim background with translucent dark mask, cutting out selectionRect
        let maskColor = NSColor.black.withAlphaComponent(0.48)
        maskColor.setFill()

        if let sel = selectionRect, sel.width > 0, sel.height > 0 {
            // Fill 4 rectangles around selection
            let topRect = CGRect(x: 0, y: sel.maxY, width: bounds.width, height: bounds.height - sel.maxY)
            let bottomRect = CGRect(x: 0, y: 0, width: bounds.width, height: sel.minY)
            let leftRect = CGRect(x: 0, y: sel.minY, width: sel.minX, height: sel.height)
            let rightRect = CGRect(x: sel.maxX, y: sel.minY, width: bounds.width - sel.maxX, height: sel.height)

            topRect.fill()
            bottomRect.fill()
            leftRect.fill()
            rightRect.fill()

            // 3. Draw dual border around selection with outer contrast glow
            let outerGlow = NSColor.black.withAlphaComponent(0.35)
            outerGlow.setStroke()
            let glowPath = NSBezierPath(rect: sel.insetBy(dx: -0.5, dy: -0.5))
            glowPath.lineWidth = 3.0
            glowPath.stroke()

            let strokeColor = NSColor(calibratedRed: 0.15, green: 0.60, blue: 1.0, alpha: 1.0)
            strokeColor.setStroke()
            let borderPath = NSBezierPath(rect: sel)
            borderPath.lineWidth = 2.0
            borderPath.stroke()

            // 4. Draw 8 circular resize handles
            drawHandles(for: sel)

            // 5. Draw dimensions pill
            drawDimensionsPill(for: sel)

            // 6. Clip annotations to selection rectangle
            context.saveGState()
            context.clip(to: sel)

            for item in history.items {
                ScreenshotRenderer.draw(item: item, in: context, scale: 1.0)
            }
            if let current = currentAnnotation {
                ScreenshotRenderer.draw(item: current, in: context, scale: 1.0)
            }

            context.restoreGState()
        } else {
            bounds.fill()
            drawTopBanner()
            if let pt = currentMousePoint {
                drawCursorGuide(at: pt)
            }
        }
    }

    private func drawHandles(for rect: CGRect) {
        let handleSize: CGFloat = 10.0
        let strokeColor = NSColor(calibratedRed: 0.15, green: 0.60, blue: 1.0, alpha: 1.0)
        let fillColor = NSColor.white

        let midX = rect.midX
        let midY = rect.midY

        let points = [
            CGPoint(x: rect.minX, y: rect.maxY), // TopLeft
            CGPoint(x: midX, y: rect.maxY),      // TopMid
            CGPoint(x: rect.maxX, y: rect.maxY), // TopRight
            CGPoint(x: rect.minX, y: midY),      // MidLeft
            CGPoint(x: rect.maxX, y: midY),      // MidRight
            CGPoint(x: rect.minX, y: rect.minY), // BottomLeft
            CGPoint(x: midX, y: rect.minY),      // BottomMid
            CGPoint(x: rect.maxX, y: rect.minY)  // BottomRight
        ]

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 3
        shadow.set()

        for pt in points {
            let handleRect = CGRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
            let path = NSBezierPath(ovalIn: handleRect)
            fillColor.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 2.0
            path.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawDimensionsPill(for rect: CGRect) {
        let widthPx = Int(round(rect.width * scaleFactor))
        let heightPx = Int(round(rect.height * scaleFactor))
        let text = "\(widthPx) × \(heightPx) px"

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let size = attrText.size()

        let pillWidth = size.width + 16
        let pillHeight = size.height + 8
        var pillY = rect.maxY + 8
        if pillY + pillHeight > bounds.height - 10 {
            pillY = rect.minY - pillHeight - 8
        }
        let pillRect = CGRect(x: max(10, min(bounds.width - pillWidth - 10, rect.minX)), y: pillY, width: pillWidth, height: pillHeight)

        let bg = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.black.withAlphaComponent(0.82).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: pillRect, xRadius: 6, yRadius: 6)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        border.lineWidth = 1.0
        border.stroke()

        attrText.draw(at: CGPoint(x: pillRect.origin.x + 8, y: pillRect.origin.y + 4))
    }

    private func drawTopBanner() {
        let title = "Screenshot Mode"
        let subtitle = "•  Click and drag to select area  •  Esc to cancel"

        let titleFont = NSFont.systemFont(ofSize: 13, weight: .bold)
        let subtitleFont = NSFont.systemFont(ofSize: 12, weight: .medium)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.72, blue: 1.0, alpha: 1.0)
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: NSColor.white.withAlphaComponent(0.85)
        ]

        let combined = NSMutableAttributedString()
        combined.append(NSAttributedString(string: "📸  " + title + "  ", attributes: titleAttrs))
        combined.append(NSAttributedString(string: subtitle, attributes: subtitleAttrs))

        let size = combined.size()
        let bannerWidth = size.width + 28
        let bannerHeight = size.height + 14
        let bannerRect = CGRect(
            x: (bounds.width - bannerWidth) / 2,
            y: bounds.height - bannerHeight - 20,
            width: bannerWidth,
            height: bannerHeight
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
        shadow.shadowOffset = NSSize(width: 0, height: -3)
        shadow.shadowBlurRadius = 10
        shadow.set()

        let bg = NSBezierPath(roundedRect: bannerRect, xRadius: 10, yRadius: 10)
        NSColor.black.withAlphaComponent(0.80).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: bannerRect, xRadius: 10, yRadius: 10)
        NSColor.white.withAlphaComponent(0.20).setStroke()
        border.lineWidth = 1.0
        border.stroke()
        NSGraphicsContext.restoreGraphicsState()

        combined.draw(at: CGPoint(x: bannerRect.origin.x + 14, y: bannerRect.origin.y + 7))
    }

    private func drawCursorGuide(at pt: CGPoint) {
        let xCoord = Int(pt.x)
        let yCoord = Int(bounds.height - pt.y)
        let text = "X: \(xCoord)  Y: \(yCoord)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white.withAlphaComponent(0.90)
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let size = attrText.size()

        let pillW = size.width + 12
        let pillH = size.height + 6
        var pillX = pt.x + 16
        var pillY = pt.y - 24

        if pillX + pillW > bounds.width - 10 { pillX = pt.x - pillW - 16 }
        if pillY < 10 { pillY = pt.y + 16 }

        let pillRect = CGRect(x: pillX, y: pillY, width: pillW, height: pillH)
        let bg = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        bg.fill()

        let border = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
        NSColor.white.withAlphaComponent(0.25).setStroke()
        border.lineWidth = 0.5
        border.stroke()

        attrText.draw(at: CGPoint(x: pillRect.origin.x + 6, y: pillRect.origin.y + 3))
    }

    // MARK: - Mouse Handling
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragStart = pt

        commitActiveText()

        // 1. Check if clicking on resize handle
        if let sel = selectionRect, let handle = handleAtPoint(pt, for: sel) {
            resizingHandle = handle
            return
        }

        // 2. Check if inside existing selection
        if let sel = selectionRect, sel.contains(pt) {
            // Draw annotation
            isDrawing = true
            currentAnnotation = AnnotationItem(
                tool: activeTool,
                startPoint: pt,
                endPoint: pt,
                points: [pt],
                text: "",
                color: activeColor.nsColor,
                strokeWidth: strokeWidth
            )
            needsDisplay = true
            return
        }

        // 3. Otherwise start brand new selection
        isSelecting = true
        selectionRect = CGRect(origin: pt, size: .zero)
        history.clear()
        toolbarHosting?.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if let handle = resizingHandle, let sel = selectionRect {
            selectionRect = resize(rect: sel, handle: handle, to: pt)
            return
        }

        if isSelecting {
            let x = min(dragStart.x, pt.x)
            let y = min(dragStart.y, pt.y)
            let w = abs(pt.x - dragStart.x)
            let h = abs(pt.y - dragStart.y)
            selectionRect = CGRect(x: x, y: y, width: w, height: h)
            return
        }

        if isDrawing, var current = currentAnnotation {
            current.endPoint = pt
            current.points.append(pt)
            currentAnnotation = current
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)

        if isSelecting {
            isSelecting = false
            if let sel = selectionRect, (sel.width < 10 || sel.height < 10) {
                selectionRect = nil
            }
            updateToolbarPosition()
            needsDisplay = true
            return
        }

        if resizingHandle != nil {
            resizingHandle = nil
            updateToolbarPosition()
            needsDisplay = true
            return
        }

        if isDrawing {
            isDrawing = false
            if let current = currentAnnotation {
                if current.tool == .text {
                    showTextInput(at: current.startPoint)
                } else {
                    history.add(current)
                }
                currentAnnotation = nil
                toolbarHosting?.rootView = makeToolbarView()
                needsDisplay = true
            }
        }
    }

    // MARK: - Text Annotation Input
    private func showTextInput(at point: CGPoint) {
        commitActiveText()

        let field = NSTextField(frame: CGRect(x: point.x, y: point.y - 12, width: 220, height: 26))
        field.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        field.textColor = activeColor.nsColor
        field.backgroundColor = NSColor.black.withAlphaComponent(0.80)
        field.isBordered = false
        field.focusRingType = .none
        field.wantsLayer = true
        field.layer?.cornerRadius = 4
        field.placeholderString = "Type annotation..."
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        activeTextField = field
    }

    private func commitActiveText() {
        guard let field = activeTextField else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let item = AnnotationItem(
                tool: .text,
                startPoint: field.frame.origin,
                endPoint: field.frame.origin,
                text: text,
                color: activeColor.nsColor,
                strokeWidth: strokeWidth
            )
            history.add(item)
            toolbarHosting?.rootView = makeToolbarView()
        }
        field.removeFromSuperview()
        activeTextField = nil
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            commitActiveText()
            return true
        } else if commandSelector == #selector(cancelOperation(_:)) {
            activeTextField?.removeFromSuperview()
            activeTextField = nil
            window?.makeFirstResponder(self)
            needsDisplay = true
            return true
        }
        return false
    }

    // MARK: - Handle Detection & Resize
    private func handleAtPoint(_ pt: CGPoint, for rect: CGRect) -> HandleType? {
        let tolerance: CGFloat = 8.0
        func hit(_ target: CGPoint) -> Bool {
            abs(pt.x - target.x) <= tolerance && abs(pt.y - target.y) <= tolerance
        }

        let midX = rect.midX
        let midY = rect.midY

        if hit(CGPoint(x: rect.minX, y: rect.maxY)) { return .topLeft }
        if hit(CGPoint(x: midX, y: rect.maxY)) { return .topMid }
        if hit(CGPoint(x: rect.maxX, y: rect.maxY)) { return .topRight }
        if hit(CGPoint(x: rect.minX, y: midY)) { return .midLeft }
        if hit(CGPoint(x: rect.maxX, y: midY)) { return .midRight }
        if hit(CGPoint(x: rect.minX, y: rect.minY)) { return .bottomLeft }
        if hit(CGPoint(x: midX, y: rect.minY)) { return .bottomMid }
        if hit(CGPoint(x: rect.maxX, y: rect.minY)) { return .bottomRight }
        return nil
    }

    private func resize(rect: CGRect, handle: HandleType, to pt: CGPoint) -> CGRect {
        var minX = rect.minX
        var maxX = rect.maxX
        var minY = rect.minY
        var maxY = rect.maxY

        switch handle {
        case .topLeft: minX = min(pt.x, maxX - 10); maxY = max(pt.y, minY + 10)
        case .topMid: maxY = max(pt.y, minY + 10)
        case .topRight: maxX = max(pt.x, minX + 10); maxY = max(pt.y, minY + 10)
        case .midLeft: minX = min(pt.x, maxX - 10)
        case .midRight: maxX = max(pt.x, minX + 10)
        case .bottomLeft: minX = min(pt.x, maxX - 10); minY = min(pt.y, maxY - 10)
        case .bottomMid: minY = min(pt.y, maxY - 10)
        case .bottomRight: maxX = max(pt.x, minX + 10); minY = min(pt.y, maxY - 10)
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }



    // MARK: - Key Events
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        if let field = activeTextField {
            if event.keyCode == 36 { // Enter
                commitActiveText()
                return true
            } else if event.keyCode == 53 { // Esc
                field.removeFromSuperview()
                activeTextField = nil
                needsDisplay = true
                return true
            }
            return false
        }

        if event.keyCode == 53 { // Esc
            onCancel?()
            return true
        }

        if event.modifierFlags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased()
            if key == "c" { // ⌘C
                performCopy()
                return true
            } else if key == "s" { // ⌘S
                performSave()
                return true
            } else if key == "z" {
                if event.modifierFlags.contains(.shift) {
                    history.redo()
                } else {
                    history.undo()
                }
                toolbarHosting?.rootView = makeToolbarView()
                needsDisplay = true
                return true
            }
        }

        if event.keyCode == 36 { // Enter
            performCopy()
            return true
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": activeTool = .pen; return true
        case "a": activeTool = .arrow; return true
        case "r": activeTool = .rectangle; return true
        case "h": activeTool = .highlight; return true
        case "t": activeTool = .text; return true
        default: return false
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleKeyEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleKeyEvent(event) {
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Actions
    func performCopy() {
        let sel = selectionRect ?? bounds
        guard sel.width > 5, sel.height > 5 else { return }
        commitActiveText()

        if let result = ScreenshotRenderer.composite(
            sourceImage: capturedImage,
            selectionRect: sel,
            desktopBounds: bounds,
            annotations: history.items,
            screenScale: scaleFactor
        ) {
            onCopy?(result.image, result.pngData)
        }
    }

    func performSave() {
        let sel = selectionRect ?? bounds
        guard sel.width > 5, sel.height > 5 else { return }
        commitActiveText()

        if let result = ScreenshotRenderer.composite(
            sourceImage: capturedImage,
            selectionRect: sel,
            desktopBounds: bounds,
            annotations: history.items,
            screenScale: scaleFactor
        ) {
            onSave?(result.image, result.pngData)
        }
    }
}

// MARK: - Toolbar Hosting View with Pointer Cursor
final class ScreenshotToolbarHostingView: NSHostingView<ScreenshotToolbarView> {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.pointingHand.set()
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

private struct PointingHandHoverModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.set()
                }
            }
    }
}

extension View {
    fileprivate func pointerOnHover() -> some View {
        self.modifier(PointingHandHoverModifier())
    }
}

// MARK: - Frosted Floating Command Toolbar (SwiftUI)
struct ScreenshotToolbarView: View {
    let activeTool: AnnotationTool
    let activeColor: AnnotationColor
    let canUndo: Bool
    let canRedo: Bool
    let onSelectTool: (AnnotationTool) -> Void
    let onSelectColor: (AnnotationColor) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    static var empty: ScreenshotToolbarView {
        ScreenshotToolbarView(activeTool: .pen, activeColor: .red, canUndo: false, canRedo: false,
                              onSelectTool: { _ in }, onSelectColor: { _ in }, onUndo: {}, onRedo: {},
                              onCopy: {}, onSave: {}, onCancel: {})
    }

    private func shortcut(for tool: AnnotationTool) -> String {
        switch tool {
        case .pen: return "P"
        case .arrow: return "A"
        case .rectangle: return "R"
        case .highlight: return "H"
        case .text: return "T"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            // 1. Annotation Tools Group
            HStack(spacing: 3) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button {
                        onSelectTool(tool)
                    } label: {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(activeTool == tool ? Color.white : Color.white.opacity(0.72))
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(activeTool == tool
                                          ? AnyShapeStyle(LinearGradient(colors: [Color(red: 0.15, green: 0.58, blue: 0.98), Color(red: 0.08, green: 0.46, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                                          : AnyShapeStyle(Color.clear)
                                    )
                            )
                            .shadow(color: activeTool == tool ? Color.blue.opacity(0.35) : Color.clear, radius: 4, y: 1)
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                    .help("\(tool.rawValue) (\(shortcut(for: tool)))")
                }
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // 2. Direct 1-Click Color Palette Dots
            HStack(spacing: 5) {
                ForEach(AnnotationColor.allCases) { col in
                    Button {
                        onSelectColor(col)
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color(nsColor: col.nsColor))
                                .frame(width: 15, height: 15)
                                .shadow(color: Color.black.opacity(0.30), radius: 1, y: 1)

                            if activeColor == col {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                                    .frame(width: 21, height: 21)
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .pointerOnHover()
                    .help(col.rawValue)
                }
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // 3. Undo / Redo
            HStack(spacing: 3) {
                Button { onUndo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(canUndo ? Color.white.opacity(0.90) : Color.white.opacity(0.30))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canUndo ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canUndo)
                .pointerOnHover()
                .help("Undo (⌘Z)")

                Button { onRedo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(canRedo ? Color.white.opacity(0.90) : Color.white.opacity(0.30))
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(canRedo ? Color.white.opacity(0.08) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canRedo)
                .pointerOnHover()
                .help("Redo (⌘⇧Z)")
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // 4. Action Buttons (Cancel, Save, Copy)
            HStack(spacing: 6) {
                Button { onCancel() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .help("Cancel (Esc)")

                Button { onSave() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        Text("Save")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.95))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.white.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .help("Save to ~/Screenshots (⌘S)")

                // Primary Hero Action: Copy (⌘C)
                Button { onCopy() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Copy")
                            .font(.system(size: 12, weight: .bold))
                        Text("⌘C")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(0.22)))
                    }
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(LinearGradient(colors: [Color(red: 0.15, green: 0.58, blue: 0.98), Color(red: 0.05, green: 0.45, blue: 0.90)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: Color.blue.opacity(0.40), radius: 6, y: 2)
                    )
                }
                .buttonStyle(.plain)
                .pointerOnHover()
                .help("Copy to Clipboard (⌘C / Enter)")
            }
        }
        .pointerOnHover()
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.45), radius: 16, y: 6)
        )
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
