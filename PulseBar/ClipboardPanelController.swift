import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

// MARK: - Native Visual Effect View (Vibrancy & Frosted Glass)

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active
    var isEmphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
        nsView.isEmphasized = isEmphasized
    }
}

// MARK: - Image Cache

final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    init() {
        cache.countLimit = 150
        cache.totalCostLimit = 60 * 1024 * 1024 // 60 MB
    }

    func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func removeImage(for url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }

    func clear() {
        cache.removeAllObjects()
    }
}

// MARK: - Native File Icon Helper

func fileIcon(for path: String) -> NSImage {
    if FileManager.default.fileExists(atPath: path) {
        return NSWorkspace.shared.icon(forFile: path)
    }
    let ext = (path as NSString).pathExtension
    if let uti = UTType(filenameExtension: ext) {
        return NSWorkspace.shared.icon(for: uti)
    }
    return NSWorkspace.shared.icon(for: .item)
}

// MARK: - Clipboard Spotlight Panel Subclass

final class ClipboardPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            switch event.keyCode {
            case 53: // Escape
                onEscape?()
                return
            case 126: // Up Arrow
                onArrowUp?()
                return
            case 125: // Down Arrow
                onArrowDown?()
                return
            case 36, 76: // Enter / Return
                onEnter?()
                return
            default:
                break
            }
        }
        super.sendEvent(event)
    }
}

// MARK: - Clipboard Toast Notification

@MainActor
final class ClipboardToastController {
    static let shared = ClipboardToastController()
    private var toastWindow: NSWindow?
    private var dismissTask: Task<Void, Never>?

    func show(message: String, submessage: String? = nil, icon: String = "doc.on.clipboard") {
        dismissTask?.cancel()
        if toastWindow == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 340, height: 64),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.level = .floating
            win.ignoresMouseEvents = true
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.toastWindow = win
        }

        guard let win = toastWindow else { return }
        let toastView = ClipboardToastView(icon: icon, message: message, submessage: submessage)
        let hosting = NSHostingController(rootView: toastView)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        win.contentViewController = hosting

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 170
            let y = screenRect.minY + 90
            win.setFrameOrigin(NSPoint(x: x, y: y))
        }

        win.orderFront(nil)
        win.animator().alphaValue = 1.0

        dismissTask = Task { @MainActor [weak win] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let w = win else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                w.animator().alphaValue = 0.0
            } completionHandler: {
                w.orderOut(nil)
            }
        }
    }
}

private struct ClipboardToastView: View {
    let icon: String
    let message: String
    let submessage: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                if let sub = submessage {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 10)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Clipboard Panel Controller

@MainActor @Observable
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    @ObservationIgnored let clipboard: ClipboardManager
    @ObservationIgnored private var panel: ClipboardPanel?

    var searchText = ""
    var selectedItemId: UUID?
    var isShowingConfirmation = false
    var targetApp: NSRunningApplication?

    var targetAppName: String? {
        guard let app = targetApp, !app.isTerminated, app.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return nil
        }
        return app.localizedName
    }

    init(clipboard: ClipboardManager) {
        self.clipboard = clipboard
        super.init()
    }

    private func getOrCreatePanel() -> ClipboardPanel {
        if let existing = panel { return existing }
        let p = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 490),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.animationBehavior = .utilityWindow
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self

        p.onEscape = { [weak self] in
            self?.close()
        }
        p.onArrowUp = { [weak self] in
            self?.selectPrevious()
        }
        p.onArrowDown = { [weak self] in
            self?.selectNext()
        }
        p.onEnter = { [weak self] in
            self?.restoreSelected()
        }

        let hosting = NSHostingController(rootView: ClipboardHistoryView(clipboard: clipboard, controller: self))
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        p.contentViewController = hosting
        p.setContentSize(NSSize(width: 720, height: 490))
        self.panel = p
        return p
    }

    func show(targetApp: NSRunningApplication? = nil) {
        if let app = targetApp, app.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.targetApp = app
        } else if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.targetApp = front
        }

        searchText = ""
        let items = filteredItems()
        selectedItemId = items.first?.id
        let p = getOrCreatePanel()
        centerPanel(p)
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func centerPanel(_ p: ClipboardPanel) {
        let size = NSSize(width: 720, height: 490)
        p.setContentSize(size)
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen {
            let visible = screen.visibleFrame
            let x = visible.midX - (size.width / 2)
            let y = visible.minY + (visible.height - size.height) * 0.62
            p.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        } else {
            p.center()
        }
    }

    func close() {
        panel?.orderOut(nil)
    }

    func filteredItems() -> [ClipboardItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return clipboard.items }
        return clipboard.items.filter { item in
            if item.previewTitle.localizedCaseInsensitiveContains(query) { return true }
            if let sub = item.previewSubtitle, sub.localizedCaseInsensitiveContains(query) { return true }
            if let text = item.textValue, text.localizedCaseInsensitiveContains(query) { return true }
            if let url = item.urlString, url.localizedCaseInsensitiveContains(query) { return true }
            if let files = item.filePaths, files.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
            return false
        }
    }

    func selectNext() {
        let items = filteredItems()
        guard !items.isEmpty else { return }
        guard let currentId = selectedItemId, let currentIndex = items.firstIndex(where: { $0.id == currentId }) else {
            selectedItemId = items.first?.id
            return
        }
        let nextIndex = min(currentIndex + 1, items.count - 1)
        selectedItemId = items[nextIndex].id
    }

    func selectPrevious() {
        let items = filteredItems()
        guard !items.isEmpty else { return }
        guard let currentId = selectedItemId, let currentIndex = items.firstIndex(where: { $0.id == currentId }) else {
            selectedItemId = items.first?.id
            return
        }
        let prevIndex = max(currentIndex - 1, 0)
        selectedItemId = items[prevIndex].id
    }

    func restoreSelected() {
        let items = filteredItems()
        guard !items.isEmpty else { return }
        let itemToRestore = selectedItemId.flatMap { id in items.first(where: { $0.id == id }) } ?? items.first
        if let item = itemToRestore {
            restoreAndPaste(item: item)
        }
    }

    func restoreAndPaste(item: ClipboardItem) {
        clipboard.restore(item)

        let hasA11y = AXIsProcessTrusted()
        let appToPaste = targetApp
        let canDirectPaste = hasA11y && appToPaste != nil && !(appToPaste?.isTerminated ?? true) && appToPaste?.bundleIdentifier != Bundle.main.bundleIdentifier

        close()

        if canDirectPaste, let app = appToPaste {
            app.activate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                let pid = app.processIdentifier
                let src = CGEventSource(stateID: .hidSystemState)
                let vKey: CGKeyCode = 9 // kVK_ANSI_V
                let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
                let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
                down?.flags = .maskCommand
                up?.flags = .maskCommand
                down?.postToPid(pid)
                up?.postToPid(pid)
            }

            ClipboardToastController.shared.show(
                message: "Pasted into \(app.localizedName ?? "App")",
                submessage: item.previewTitle,
                icon: "arrow.turn.up.left"
            )
        } else {
            ClipboardToastController.shared.show(
                message: "Copied to clipboard",
                submessage: "Press \u{2318}V to paste",
                icon: "doc.on.clipboard"
            )
        }
    }

    func deleteItem(_ item: ClipboardItem) {
        let currentFiltered = filteredItems()
        let currentIndex = currentFiltered.firstIndex(where: { $0.id == item.id })

        if let url = clipboard.imageURL(for: item) {
            ImageCache.shared.removeImage(for: url)
        }
        clipboard.deleteItem(item)

        let newFiltered = filteredItems()
        if newFiltered.isEmpty {
            selectedItemId = nil
        } else if let idx = currentIndex {
            let nextIdx = min(idx, newFiltered.count - 1)
            selectedItemId = newFiltered[nextIdx].id
        } else {
            selectedItemId = newFiltered.first?.id
        }
    }

    func clearAll() {
        ImageCache.shared.clear()
        clipboard.clearAll()
        selectedItemId = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if !isShowingConfirmation {
            close()
        }
    }
}

// MARK: - Clipboard History Spotlight View (Apple Liquid Glass)

struct ClipboardHistoryView: View {
    let clipboard: ClipboardManager
    @Bindable var controller: ClipboardPanelController

    @State private var showingClearConfirmation = false
    @FocusState private var isSearchFocused: Bool

    private var filteredItems: [ClipboardItem] {
        controller.filteredItems()
    }

    private var selectedItem: ClipboardItem? {
        if let id = controller.selectedItemId {
            return filteredItems.first(where: { $0.id == id })
        }
        return filteredItems.first
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            headerSeparator
            contentSection
            footerSeparator
            footerSection
        }
        .frame(width: 720, height: 490)
        .background {
            ZStack {
                // Live macOS wallpaper vibrancy & frost blur
                VisualEffectView(material: .popover, blendingMode: .behindWindow)
                // Subtle ambient gradient tint to preserve deep contrast and vibrancy
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.48)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                // Specular top-lit glass edge highlight
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.35),
                                Color.white.opacity(0.12),
                                Color.white.opacity(0.04),
                                Color.white.opacity(0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.5), radius: 32, x: 0, y: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear {
            isSearchFocused = true
            if controller.selectedItemId == nil {
                controller.selectedItemId = filteredItems.first?.id
            }
        }
    }

    private var headerSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.12), Color.white.opacity(0.04), Color.white.opacity(0.12)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    private var footerSeparator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.03), Color.white.opacity(0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 1)
    }

    // MARK: - Search Header

    @ViewBuilder
    private var searchHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.9))

                TextField("Search clipboard history...", text: $controller.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(.primary)
                    .focused($isSearchFocused)
                    .accessibilityIdentifier("ClipboardSearchField")
                    .onChange(of: controller.searchText) { _, _ in
                        let items = controller.filteredItems()
                        if let sel = controller.selectedItemId, items.contains(where: { $0.id == sel }) {
                            // Keep selection
                        } else {
                            controller.selectedItemId = items.first?.id
                        }
                    }

                if !controller.searchText.isEmpty {
                    Button {
                        controller.searchText = ""
                        controller.selectedItemId = clipboard.items.first?.id
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if clipboard.items.isEmpty {
            emptyHistoryView
        } else if filteredItems.isEmpty {
            noSearchResultsView
        } else {
            HStack(spacing: 0) {
                // Left Column: Item List
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 5) {
                            ForEach(filteredItems) { item in
                                ClipboardRowView(
                                    item: item,
                                    isSelected: item.id == (controller.selectedItemId ?? filteredItems.first?.id),
                                    clipboard: clipboard,
                                    onSelect: {
                                        controller.selectedItemId = item.id
                                        controller.restoreAndPaste(item: item)
                                    },
                                    onItemClick: {
                                        controller.selectedItemId = item.id
                                    },
                                    onDelete: {
                                        controller.deleteItem(item)
                                    }
                                )
                                .id(item.id)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(width: 430)
                    .accessibilityIdentifier("ClipboardHistoryList")
                    .onChange(of: controller.selectedItemId) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.12)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 1)

                // Right Column: Detail Inspector
                detailInspector
                    .frame(width: 290)
            }
        }
    }

    // MARK: - Detail Inspector (Right Column)

    @ViewBuilder
    private var detailInspector: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 14) {
                // Category Header Badge
                inspectorHeaderBadge(for: item)

                // Main Preview Card
                switch item.type {
                case .image:
                    imageDetailView(item: item)
                case .text:
                    textDetailView(item: item)
                case .url:
                    urlDetailView(item: item)
                case .file:
                    fileDetailView(item: item)
                }

                Spacer()

                primaryActionButton(for: item)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Spacer()
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 60, height: 60)
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                Text("Select an item to view preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func inspectorHeaderBadge(for item: ClipboardItem) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName(for: item.type))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor(for: item.type))
            Text(categoryTitle(for: item.type))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            Capsule()
                .fill(Color.white.opacity(0.05))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }

    private func iconName(for type: ClipboardContentType) -> String {
        switch type {
        case .image: return "photo.fill"
        case .text: return "doc.text.fill"
        case .url: return "link"
        case .file: return "folder.fill"
        }
    }

    private func iconColor(for type: ClipboardContentType) -> Color {
        switch type {
        case .image: return .purple
        case .text: return .blue
        case .url: return .cyan
        case .file: return .orange
        }
    }

    private func categoryTitle(for type: ClipboardContentType) -> String {
        switch type {
        case .image: return "Image Preview"
        case .text: return "Text Snippet"
        case .url: return "Web Link"
        case .file: return "File Reference"
        }
    }

    // MARK: - Inspector Detail Views

    @ViewBuilder
    private func imageDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = clipboard.imageURL(for: item),
               let image = ImageCache.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 258, maxHeight: 175)
                    .background(Color.black.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.purple.opacity(0.12))
                    .frame(height: 140)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.purple)
                    }
            }

            VStack(spacing: 6) {
                if let dim = item.imageDimensions {
                    metaChip(title: "Dimensions", value: "\(dim) px", icon: "arrow.up.left.and.arrow.down.right")
                }
                if let sub = item.previewSubtitle {
                    metaChip(title: "File Size", value: sub, icon: "internaldrive")
                }
                metaChip(title: "Captured", value: item.timestamp.formatted(date: .abbreviated, time: .shortened), icon: "clock")
            }
        }
    }

    @ViewBuilder
    private func metaChip(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func fileDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let first = item.filePaths?.first {
                    Image(nsImage: fileIcon(for: first))
                        .resizable()
                        .frame(width: 46, height: 46)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.previewTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                    if let first = item.filePaths?.first {
                        Text((first as NSString).deletingLastPathComponent)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }

            if let paths = item.filePaths, paths.count > 1 {
                Text("\(paths.count) files referenced in this item")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let first = item.filePaths?.first, FileManager.default.fileExists(atPath: first) {
                Button {
                    NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Reveal in Finder")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func urlDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(item.previewTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                if let urlString = item.urlString {
                    Text(urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.cyan)
                        .lineLimit(4)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.cyan.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.cyan.opacity(0.18), lineWidth: 0.5)
                                )
                        }

                    Button {
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "safari")
                            Text("Open in Default Browser")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.cyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func textDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                Text(item.textValue ?? "")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
            .padding(10)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                    )
            }

            if let subtitle = item.previewSubtitle {
                HStack(spacing: 5) {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Primary Action Button (Liquid Glass Style)

    private func primaryActionButton(for item: ClipboardItem) -> some View {
        let hasA11y = AXIsProcessTrusted()
        let targetName = controller.targetAppName
        let title = (hasA11y && targetName != nil) ? "Paste into \(targetName ?? "App")" : "Copy to Clipboard (\u{2318}V)"
        let icon = (hasA11y && targetName != nil) ? "arrow.turn.up.left" : "doc.on.clipboard"

        return Button {
            controller.restoreAndPaste(item: item)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\u{21b5}")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.85)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    LinearGradient(
                        colors: [Color.white.opacity(0.32), Color.clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 3)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer Section

    @ViewBuilder
    private var footerSection: some View {
        HStack(spacing: 12) {
            // Item Count Capsule
            Text("\(filteredItems.count) of \(clipboard.items.count) items")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.05))
                .clipShape(Capsule())

            Spacer()

            // Direct Paste Status Capsule
            if AXIsProcessTrusted() {
                if let name = controller.targetAppName {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .shadow(color: .green.opacity(0.6), radius: 3)
                        Text("Direct paste: \(name)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.25), lineWidth: 0.5))
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 5, height: 5)
                        Text("Direct paste ready")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .clipShape(Capsule())
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("Accessibility required for auto-paste")
                        .font(.system(size: 11))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(Color.yellow.opacity(0.25), lineWidth: 0.5))
            }

            Spacer()

            // Apple Style Keycap Legend
            HStack(spacing: 6) {
                keycap("\u{2191}\u{2193}")
                Text("Navigate").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("\u{2022}").font(.system(size: 8)).foregroundStyle(.tertiary)
                keycap("\u{21b5}")
                Text("Paste").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("\u{2022}").font(.system(size: 8)).foregroundStyle(.tertiary)
                keycap("esc")
                Text("Close").font(.system(size: 10)).foregroundStyle(.tertiary)
            }

            Spacer()

            // Clear All Button
            Button {
                showingClearConfirmation = true
                controller.isShowingConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                    Text("Clear All")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(clipboard.items.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(clipboard.items.isEmpty ? Color.clear : Color.red.opacity(0.10))
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(clipboard.items.isEmpty ? Color.clear : Color.red.opacity(0.20), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .disabled(clipboard.items.isEmpty)
            .accessibilityIdentifier("ClipboardClearAll")
            .confirmationDialog(
                "Clear Clipboard History?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    controller.clearAll()
                    showingClearConfirmation = false
                    controller.isShowingConfirmation = false
                }
                Button("Cancel", role: .cancel) {
                    showingClearConfirmation = false
                    controller.isShowingConfirmation = false
                }
            } message: {
                Text("Are you sure you want to delete all \(clipboard.items.count) items? This cannot be undone.")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func keycap(_ key: String) -> some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
            )
    }

    // MARK: - Empty States

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 76, height: 76)
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("No Clipboard History")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Copied text, links, images, and files will automatically appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 70, height: 70)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text("No Results Found")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("No clipboard entries match \"\(controller.searchText)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clipboard Row View (Apple Liquid Glass Item)

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let clipboard: ClipboardManager
    let onSelect: () -> Void
    let onItemClick: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 11) {
            if isSelected {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 32)
                    .shadow(color: Color.accentColor.opacity(0.6), radius: 4)
            }

            typeBadgeOrThumbnail

            rowTexts

            Spacer()

            rowActions
        }
        .padding(.leading, isSelected ? 6 : 10)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onItemClick()
        }
    }

    @ViewBuilder
    private var rowTexts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.previewTitle)
                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                .lineLimit(2)
                .foregroundStyle(.primary)

            HStack(spacing: 6) {
                if let subtitle = item.previewSubtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(relativeTimeString(from: item.timestamp))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        HStack(spacing: 6) {
            Button {
                onSelect()
            } label: {
                Image(systemName: "arrow.turn.up.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(isSelected ? 0.20 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Restore to clipboard & paste (Enter)")

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(isSelected ? 0.15 : 0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Delete from history")
        }
        .opacity(isHovered || isSelected ? 1.0 : 0.0)
    }

    @ViewBuilder
    private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        if isSelected {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.20)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.4)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                )
                .shadow(color: Color.accentColor.opacity(0.25), radius: 8, x: 0, y: 2)
        } else if isHovered {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.025), Color.white.opacity(0.015)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    shape.strokeBorder(Color.white.opacity(0.04), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var typeBadgeOrThumbnail: some View {
        switch item.type {
        case .image:
            if let url = clipboard.imageURL(for: item),
               let image = ImageCache.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.85), Color.indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "photo.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                }
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
            }
        case .file:
            if let first = item.filePaths?.first {
                Image(nsImage: fileIcon(for: first))
                    .resizable()
                    .frame(width: 36, height: 36)
                    .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 1.5)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.orange.opacity(0.85), Color.yellow.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.white)
                        .font(.system(size: 16))
                }
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
                )
            }
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "doc.text.fill")
                    .foregroundStyle(.white)
                    .font(.system(size: 16))
            }
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        case .url:
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.teal.opacity(0.85), Color.cyan.opacity(0.9)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "link")
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .bold))
            }
            .frame(width: 36, height: 36)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = -date.timeIntervalSinceNow
        if seconds < 5 { return "Just now" }
        if seconds < 60 { return "\(Int(seconds))s ago" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(minutes / 60)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(hours / 24)
        return "\(days)d ago"
    }
}
