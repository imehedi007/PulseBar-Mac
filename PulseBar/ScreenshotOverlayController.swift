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

    private var currentAnnotation: AnnotationItem?
    private var dragStart: CGPoint = .zero
    private var isSelecting = false
    private var isDrawing = false
    private var isMovingSelection = false
    private var resizingHandle: HandleType?
    private var dragOffset: CGPoint = .zero
    private var activeTextField: NSTextField?

    private var toolbarHosting: NSHostingView<ScreenshotToolbarView>?

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
            options: [.activeAlways, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Toolbar Setup
    private func setupToolbar() {
        let hosting = NSHostingView(rootView: makeToolbarView())
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
            return
        }

        toolbar.rootView = makeToolbarView()
        let idealSize = toolbar.fittingSize
        toolbar.frame.size = idealSize
        toolbar.isHidden = false

        // Position: prefer below selection, right aligned
        var originX = sel.maxX - idealSize.width
        var originY = sel.minY - idealSize.height - 10

        // Clamp horizontally
        originX = max(10, min(bounds.width - idealSize.width - 10, originX))

        // If not enough room below, place above selection
        if originY < 10 {
            originY = sel.maxY + 10
        }
        // If still offscreen at top, place inside bottom of selection
        if originY + idealSize.height > bounds.height - 10 {
            originY = sel.minY + 10
        }

        toolbar.frame.origin = CGPoint(x: originX, y: originY)
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

            // 3. Draw border around selection
            let strokeColor = NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
            strokeColor.setStroke()
            let borderPath = NSBezierPath(rect: sel)
            borderPath.lineWidth = 1.5
            borderPath.stroke()

            // 4. Draw 8 resize handles
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
            drawInstructionPill()
        }
    }

    private func drawHandles(for rect: CGRect) {
        let handleSize: CGFloat = 8.0
        let strokeColor = NSColor(calibratedRed: 0.25, green: 0.65, blue: 1.0, alpha: 1.0)
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

        for pt in points {
            let handleRect = CGRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
            let path = NSBezierPath(rect: handleRect)
            fillColor.setFill()
            path.fill()
            strokeColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawDimensionsPill(for rect: CGRect) {
        let widthPx = Int(round(rect.width * scaleFactor))
        let heightPx = Int(round(rect.height * scaleFactor))
        let text = "\(widthPx) × \(heightPx) px"

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let size = attrText.size()

        let pillWidth = size.width + 12
        let pillHeight = size.height + 6
        var pillY = rect.maxY + 6
        if pillY + pillHeight > bounds.height - 10 {
            pillY = rect.minY - pillHeight - 6
        }
        let pillRect = CGRect(x: max(10, min(bounds.width - pillWidth - 10, rect.minX)), y: pillY, width: pillWidth, height: pillHeight)

        let bg = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)
        NSColor.black.withAlphaComponent(0.75).setFill()
        bg.fill()

        attrText.draw(at: CGPoint(x: pillRect.origin.x + 6, y: pillRect.origin.y + 3))
    }

    private func drawInstructionPill() {
        let text = "Click and drag to select capture area • Esc to cancel"
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let size = attrText.size()

        let pillRect = CGRect(
            x: (bounds.width - size.width - 24) / 2,
            y: (bounds.height - size.height - 14) / 2,
            width: size.width + 24,
            height: size.height + 14
        )

        let bg = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.70).setFill()
        bg.fill()

        attrText.draw(at: CGPoint(x: pillRect.origin.x + 12, y: pillRect.origin.y + 7))
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

    private func updateCursor() {
        if selectionRect == nil {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
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

// MARK: - Frosted Floating Toolbar (SwiftUI)
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

    var body: some View {
        HStack(spacing: 6) {
            // Tools
            ForEach(AnnotationTool.allCases) { tool in
                Button {
                    onSelectTool(tool)
                } label: {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(activeTool == tool ? Color.white : Color.white.opacity(0.70))
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(activeTool == tool ? Color.white.opacity(0.24) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help("\(tool.rawValue) tool")
            }

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // Colors
            Menu {
                ForEach(AnnotationColor.allCases) { col in
                    Button {
                        onSelectColor(col)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(nsColor: col.nsColor))
                                .frame(width: 10, height: 10)
                            Text(col.rawValue)
                        }
                    }
                }
            } label: {
                Circle()
                    .fill(Color(nsColor: activeColor.nsColor))
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(Color.white.opacity(0.60), lineWidth: 1.5))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Color palette")

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // Undo / Redo
            Button { onUndo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canUndo ? Color.white.opacity(0.85) : Color.white.opacity(0.30))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canUndo)
            .help("Undo (⌘Z)")

            Button { onRedo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(canRedo ? Color.white.opacity(0.85) : Color.white.opacity(0.30))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!canRedo)
            .help("Redo (⌘⇧Z)")

            Divider()
                .frame(height: 18)
                .overlay(Color.white.opacity(0.20))

            // Cancel
            Button { onCancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")

            // Save
            Button { onSave() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                    Text("Save")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .help("Save to Screenshots folder (⌘S)")

            // Copy (Primary Workflow)
            Button { onCopy() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                    Text("Copy")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(red: 0.15, green: 0.52, blue: 0.95))
                )
            }
            .buttonStyle(.plain)
            .help("Copy to Clipboard (⌘C / Enter)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.40), radius: 10, y: 4)
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
