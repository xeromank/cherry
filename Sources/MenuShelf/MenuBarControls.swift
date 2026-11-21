import AppKit

@MainActor
final class MenuBarControls: NSObject {
    enum Layout {
        case collapsed, expanded, arranging
    }

    private static let launcherName = "MenuShelf.Launcher"
    private static let dividerName = "MenuShelf.Divider"
    private let launcher: NSStatusItem
    private let divider: NSStatusItem
    private let open: (CGPoint?) -> Void
    private let settings: () -> Void
    private let quit: () -> Void
    private var layout: Layout = .expanded
    private var layoutCheck: Task<Void, Never>?

    init(open: @escaping (CGPoint?) -> Void, settings: @escaping () -> Void, quit: @escaping () -> Void) {
        self.open = open
        self.settings = settings
        self.quit = quit

        // Preserve the native divider and launcher's saved order across upgrades.
        Self.seedPosition(0, for: Self.launcherName)
        Self.seedPosition(1, for: Self.dividerName)
        launcher = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        launcher.autosaveName = Self.launcherName
        divider = NSStatusBar.system.statusItem(withLength: 1)
        divider.autosaveName = Self.dividerName
        super.init()

        if let button = launcher.button {
            button.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Cherry")
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.toolTip = "Cherry (⌃⇧Space)"
            button.setAccessibilityLabel("Cherry")
            button.target = self
            button.action = #selector(launcherClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        divider.button?.setAccessibilityLabel("Cherry 구분선")
        invalidateLayout()
    }

    private var anchor: CGPoint? {
        guard let button = launcher.button, let window = button.window, window.occlusionState.contains(.visible) else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.contains { $0.frame.contains(center) } ? center : nil
    }

    var dividerFrame: CGRect? {
        guard let frame = divider.button?.window?.frame, let desktopTop = NSScreen.screens.first?.frame.maxY else { return nil }
        return StatusBarGeometry.accessibilityFrame(frame, desktopTop: desktopTop)
    }

    var launcherFrame: CGRect? {
        guard let frame = launcher.button?.window?.frame, let desktopTop = NSScreen.screens.first?.frame.maxY else { return nil }
        return StatusBarGeometry.accessibilityFrame(frame, desktopTop: desktopTop)
    }

    var launcherScreen: NSScreen? {
        guard let anchor else { return nil }
        return NSScreen.screens.first { $0.frame.contains(anchor) }
    }

    func setLayout(_ next: Layout) {
        guard layout != next else { return }
        layout = next
        invalidateLayout()
    }

    func invalidateLayout() {
        layoutCheck?.cancel()
        let arranging = layout == .arranging
        divider.button?.title = arranging ? "|" : ""
        divider.button?.alphaValue = arranging ? 1 : 0
        divider.button?.setAccessibilityHidden(!arranging)

        let width: CGFloat
        switch layout {
        case .arranging:
            width = 19
        case .expanded:
            width = 1
        case .collapsed:
            let displayWidth = NSScreen.screens.map(\.frame.width).max() ?? 1
            width = min(10_000, (displayWidth * 2).rounded(.up))
        }
        if divider.length != width { divider.length = width }
        guard layout == .collapsed else { return }

        layoutCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled, let self, self.layout == .collapsed, self.anchor == nil else { return }
            // Recover if a changed native order puts the launcher behind its own divider.
            self.setLayout(.expanded)
        }
    }

    @objc private func launcherClicked() {
        guard let button = launcher.button else { return }
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Cherry 열기", action: #selector(openFromMenu), keyEquivalent: "").target = self
            menu.addItem(withTitle: "메뉴 막대 정리…", action: #selector(openSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Cherry 종료", action: #selector(quitFromMenu), keyEquivalent: "q").target = self
            menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.minX, y: button.bounds.minY), in: button)
        } else if NSApp.currentEvent?.modifierFlags.contains(.command) != true {
            open(anchor)
        }
    }

    @objc private func openFromMenu() { open(anchor) }
    @objc private func openSettings() { settings() }
    @objc private func quitFromMenu() { quit() }

    private static func seedPosition(_ position: Int, for name: String) {
        let key = "NSStatusItem Preferred Position \(name)"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { defaults.set(position, forKey: key) }
    }
}
