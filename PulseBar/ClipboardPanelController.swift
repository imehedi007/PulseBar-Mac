import AppKit
import SwiftUI
import Observation
import UniformTypeIdentifiers

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
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
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
        win.contentViewController = NSHostingController(rootView: toastView)

        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - 160
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
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 480),
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
        p.contentViewController = hosting
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
        p.center()
        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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

// MARK: - Clipboard History Spotlight View

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
            Divider()
            contentSection
            Divider()
            footerSection
        }
        .frame(width: 700, height: 480)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .background(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .preferredColorScheme(.dark)
        .onAppear {
            isSearchFocused = true
            if controller.selectedItemId == nil {
                controller.selectedItemId = filteredItems.first?.id
            }
        }
    }

    @ViewBuilder
    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Search clipboard history...", text: $controller.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)
                .accessibilityIdentifier("ClipboardSearchField")
                .onChange(of: controller.searchText) { _, _ in
                    let items = controller.filteredItems()
                    if let sel = controller.selectedItemId, items.contains(where: { $0.id == sel }) {
                        // Keep current selection
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
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

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
                        LazyVStack(spacing: 4) {
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
                        .padding(8)
                    }
                    .frame(width: 420)
                    .accessibilityIdentifier("ClipboardHistoryList")
                    .onChange(of: controller.selectedItemId) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.1)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }

                Divider()

                // Right Column: Detail Inspector
                detailInspector
                    .frame(width: 280)
            }
        }
    }

    @ViewBuilder
    private var detailInspector: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 14) {
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
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "sidebar.right")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Select an item to view preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func imageDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Image Preview")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let url = clipboard.imageURL(for: item),
               let image = ImageCache.shared.image(for: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 248, maxHeight: 180)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.purple.opacity(0.15))
                    .frame(height: 140)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.purple)
                    }
            }

            VStack(alignment: .leading, spacing: 5) {
                if let dim = item.imageDimensions {
                    HStack {
                        Text("Dimensions:").font(.caption2).foregroundStyle(.secondary)
                        Text(dim + " px").font(.caption2).fontWeight(.medium)
                    }
                }
                if let sub = item.previewSubtitle {
                    HStack {
                        Text("File Size:").font(.caption2).foregroundStyle(.secondary)
                        Text(sub).font(.caption2).fontWeight(.medium)
                    }
                }
                HStack {
                    Text("Captured:").font(.caption2).foregroundStyle(.secondary)
                    Text(item.timestamp.formatted(date: .abbreviated, time: .shortened)).font(.caption2)
                }
            }
            .monospacedDigit()
        }
    }

    @ViewBuilder
    private func fileDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("File Reference")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if let first = item.filePaths?.first {
                    Image(nsImage: fileIcon(for: first))
                        .resizable()
                        .frame(width: 48, height: 48)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.previewTitle)
                        .font(.headline)
                        .lineLimit(2)
                    if let first = item.filePaths?.first {
                        Text((first as NSString).deletingLastPathComponent)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            if let paths = item.filePaths, paths.count > 1 {
                Text("\(paths.count) files selected")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            if let first = item.filePaths?.first, FileManager.default.fileExists(atPath: first) {
                Button("Reveal in Finder") {
                    NSWorkspace.shared.selectFile(first, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func urlDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Web Link")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.previewTitle)
                    .font(.headline)
                    .lineLimit(2)

                if let urlString = item.urlString {
                    Text(urlString)
                        .font(.caption)
                        .foregroundStyle(.cyan)
                        .lineLimit(4)
                        .textSelection(.enabled)

                    Button("Open in Default Browser") {
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private func textDetailView(item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Text Snippet")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            ScrollView {
                Text(item.textValue ?? "")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 180)
            .padding(8)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let subtitle = item.previewSubtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func primaryActionButton(for item: ClipboardItem) -> some View {
        let hasA11y = AXIsProcessTrusted()
        let targetName = controller.targetAppName
        let title = (hasA11y && targetName != nil) ? "Paste into \(targetName ?? "App")" : "Copy to Clipboard (\u{2318}V)"
        let icon = (hasA11y && targetName != nil) ? "arrow.turn.up.left" : "doc.on.clipboard"

        return Button {
            controller.restoreAndPaste(item: item)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text("\u{21b5}")
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.white.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var footerSection: some View {
        HStack {
            Text("\(filteredItems.count) of \(clipboard.items.count) item\(clipboard.items.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if AXIsProcessTrusted() {
                if let name = controller.targetAppName {
                    Label("Direct paste: \(name)", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    Label("Direct paste ready", systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("Accessibility required for auto-paste", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }

            Spacer()

            HStack(spacing: 8) {
                Text("\u{2191}\u{2193} Navigate")
                Text("\u{2022}")
                Text("\u{21b5} Paste")
                Text("\u{2022}")
                Text("esc Close")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Spacer()

            Button("Clear All") {
                showingClearConfirmation = true
                controller.isShowingConfirmation = true
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(clipboard.items.isEmpty ? Color.secondary.opacity(0.5) : Color.red)
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

    private var emptyHistoryView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Clipboard History")
                .font(.headline)
            Text("Copied text, links, images, and files will automatically appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.secondary)
            Text("No Results Found")
                .font(.headline)
            Text("No clipboard entries match \"\(controller.searchText)\".")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Clipboard Row View

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let clipboard: ClipboardManager
    let onSelect: () -> Void
    let onItemClick: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            typeBadgeOrThumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let subtitle = item.previewSubtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(relativeTimeString(from: item.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    onSelect()
                } label: {
                    Image(systemName: "arrow.turn.up.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Restore to clipboard & paste (Enter)")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Delete from history")
            }
            .opacity(isHovered || isSelected ? 1.0 : 0.4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, item.type == .image ? 6 : 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.24) : (isHovered ? Color.white.opacity(0.06) : Color.clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onItemClick()
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
                    .scaledToFit()
                    .frame(width: 115, height: 68)
                    .background(Color.black.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.purple.opacity(0.2))
                    Image(systemName: "photo")
                        .foregroundStyle(Color.purple)
                        .font(.system(size: 20))
                }
                .frame(width: 115, height: 68)
            }
        case .file:
            if let first = item.filePaths?.first {
                Image(nsImage: fileIcon(for: first))
                    .resizable()
                    .frame(width: 36, height: 36)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.orange.opacity(0.2))
                    Image(systemName: "doc.fill")
                        .foregroundStyle(Color.orange)
                        .font(.system(size: 18))
                }
                .frame(width: 36, height: 36)
            }
        case .text:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.blue.opacity(0.2))
                Image(systemName: "doc.text")
                    .foregroundStyle(Color.blue)
                    .font(.system(size: 18))
            }
            .frame(width: 36, height: 36)
        case .url:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.cyan.opacity(0.2))
                Image(systemName: "link")
                    .foregroundStyle(Color.cyan)
                    .font(.system(size: 18))
            }
            .frame(width: 36, height: 36)
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
