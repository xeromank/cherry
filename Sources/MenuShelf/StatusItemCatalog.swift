import AppKit
import ApplicationServices
import UniformTypeIdentifiers

struct StatusItem: Identifiable {
    let id: String
    let title: String
    let appName: String
    let appIcon: NSImage
    let isHidden: Bool
    let preferenceID: String
    let ownerPID: pid_t
    fileprivate let actionID: UUID

    init(
        id: String, title: String, appName: String, appIcon: NSImage, isHidden: Bool,
        preferenceID: String? = nil, ownerPID: pid_t = 0, actionID: UUID = UUID()
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.appIcon = appIcon
        self.isHidden = isHidden
        self.preferenceID = preferenceID ?? id
        self.ownerPID = ownerPID
        self.actionID = actionID
    }
}

struct StatusBarGeometry: Sendable {
    let displayFrame: CGRect
    let rightBand: CGRect

    static func accessibilityFrame(_ frame: CGRect, desktopTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: desktopTop - frame.maxY, width: frame.width, height: frame.height)
    }

    static func isHidden(_ itemFrame: CGRect?, on displays: [Self], appMenus: [CGRect]) -> Bool {
        guard let itemFrame, !displays.isEmpty else { return false }
        guard let display = displays.first(where: { $0.isOnMenuBar(itemFrame) }) else { return true }
        let menuEndX = appMenus.lazy.filter { display.isOnMenuBar($0) }.map(\.maxX).max()
        return display.isHidden(itemFrame, menuEndX: menuEndX)
    }

    func isHidden(_ itemFrame: CGRect?, menuEndX: CGFloat?) -> Bool {
        guard let itemFrame else { return false }
        let start = max(rightBand.minX, menuEndX ?? rightBand.minX)
        return !isOnMenuBar(itemFrame) || itemFrame.minX < start || itemFrame.maxX > rightBand.maxX
    }

    func isOnMenuBar(_ frame: CGRect) -> Bool {
        frame.midX >= displayFrame.minX && frame.midX < displayFrame.maxX
            && frame.midY >= rightBand.minY && frame.midY <= rightBand.maxY
    }
}

@MainActor
final class StatusItemCatalog {
    private let worker = AccessibilityWorker()

    func scan(on screen: NSScreen?) async -> [StatusItem] {
        let workspace = NSWorkspace.shared
        let thisProcess = ProcessInfo.processInfo.processIdentifier
        let apps = workspace.runningApplications.filter { app in
            app.processIdentifier > 0 && app.processIdentifier != thisProcess && !app.isTerminated
                && Self.shouldScan(bundleIdentifier: app.bundleIdentifier, activationPolicy: app.activationPolicy)
        }
        let sources = apps.map { app in
            ProcessSource(
                pid: app.processIdentifier,
                identity: app.bundleIdentifier ?? app.executableURL?.path ?? String(app.processIdentifier),
                name: app.localizedName ?? app.bundleIdentifier ?? String(app.processIdentifier)
            )
        }
        let duplicateIdentities = Set(Dictionary(grouping: sources, by: \.identity)
            .filter { $0.value.count > 1 }.keys)
        let applications = Dictionary(apps.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        let menuOwner = workspace.menuBarOwningApplication?.processIdentifier
        let entries = await worker.scan(
            sources: sources,
            duplicateIdentities: duplicateIdentities,
            displays: Self.geometries(preferred: screen),
            menuOwner: menuOwner == thisProcess ? nil : menuOwner
        )
        guard !Task.isCancelled else { return [] }

        let genericIcon = workspace.icon(for: .application)
        return entries.map { entry in
            StatusItem(
                id: entry.id,
                title: entry.title,
                appName: entry.owner.name,
                appIcon: applications[entry.owner.pid]?.icon ?? genericIcon,
                isHidden: entry.isHidden,
                preferenceID: entry.preferenceID,
                ownerPID: entry.owner.pid,
                actionID: entry.actionID
            )
        }
    }

    func activate(_ item: StatusItem, refreshElement: Bool) async -> Bool {
        await worker.activate(item.actionID, refreshElement: refreshElement)
    }

    func position(of item: StatusItem, on screen: NSScreen) async -> (frame: CGRect, isOnDisplay: Bool, isHidden: Bool)? {
        guard let display = Self.geometries(preferred: screen).first else { return nil }
        let menuOwner = NSWorkspace.shared.menuBarOwningApplication?.processIdentifier
        return await worker.position(of: item.actionID, display: display, menuOwner: menuOwner)
    }

    static func shouldScan(bundleIdentifier: String?, activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        // The AX source identifies the original app even when Control Center hosts its status window.
        bundleIdentifier != "com.apple.controlcenter"
            && (activationPolicy != .prohibited || systemHosts.contains(bundleIdentifier ?? ""))
    }

    private static func geometries(preferred screen: NSScreen?) -> [StatusBarGeometry] {
        var screens = NSScreen.screens
        guard let desktopTop = screens.first?.frame.maxY else { return [] }
        if let screen, let index = screens.firstIndex(of: screen) {
            screens.remove(at: index)
            screens.insert(screen, at: 0)
        }
        return screens.map { screen in
            let display = screen.frame
            let height = max(NSStatusBar.system.thickness, display.maxY - screen.visibleFrame.maxY)
            let rightBand = screen.auxiliaryTopRightArea ?? CGRect(
                x: display.minX, y: display.maxY - height, width: display.width, height: height
            )
            return StatusBarGeometry(
                displayFrame: StatusBarGeometry.accessibilityFrame(display, desktopTop: desktopTop),
                rightBand: StatusBarGeometry.accessibilityFrame(rightBand, desktopTop: desktopTop)
            )
        }
    }

    private static let systemHosts: Set<String> = [
        "com.apple.systemuiserver", "com.apple.notificationcenterui",
        "com.apple.Spotlight", "com.apple.MenuBarAgent"
    ]
}

private struct ProcessSource: Sendable {
    let pid: pid_t
    let identity: String
    let name: String
}

private struct CatalogEntry: Sendable {
    let id: String
    let title: String
    let owner: ProcessSource
    let isHidden: Bool
    let preferenceID: String
    let actionID = UUID()
}

private actor AccessibilityWorker {
    private struct ActionTarget {
        let element: AXUIElement
        let sourcePID: pid_t
        let identifier: String?
        let title: String?
        let previousFrame: CGRect?
    }

    private enum ActionAttempt {
        case accepted, unsupported, stale, rejected
    }

    private var elements: [UUID: ActionTarget] = [:]
    private var previousElements: [UUID: ActionTarget] = [:]

    func scan(
        sources: [ProcessSource],
        duplicateIdentities: Set<String>,
        displays: [StatusBarGeometry],
        menuOwner: pid_t?
    ) -> [CatalogEntry] {
        guard AXIsProcessTrusted() else {
            elements.removeAll()
            previousElements.removeAll()
            return []
        }

        let appMenus = menuOwner.map { menuFrames(owner: $0) } ?? []
        var entries: [CatalogEntry] = []
        var scannedElements: [UUID: ActionTarget] = [:]

        for source in sources {
            guard !Task.isCancelled else { return [] }
            let app = application(source.pid)
            guard let extras = element(attribute(kAXExtrasMenuBarAttribute, of: app)) else { continue }

            let ownerID = duplicateIdentities.contains(source.identity)
                ? "\(source.identity)@\(source.pid)" : source.identity
            var occurrences: [String: Int] = [:]
            for (index, item) in statusElements(in: extras).enumerated() {
                guard !Task.isCancelled else { return [] }
                let details = attributes(Self.itemAttributes, of: item)
                let title = itemTitle(details)
                let identifier = text(details[kAXIdentifierAttribute])
                let identity = identifier.map { "id:\($0)" }
                    ?? title.map { "label:\($0)" } ?? "unlabeled"
                let ordinal = occurrences[identity, default: 0]
                occurrences[identity] = ordinal + 1
                let itemFrame = frame(details)
                let hidden = details[kAXHiddenAttribute] as? Bool == true
                    || StatusBarGeometry.isHidden(itemFrame, on: displays, appMenus: appMenus)
                let itemPreferenceID = identifier.map { "id:\($0):\(ordinal)" } ?? "index:\(index)"
                let entry = CatalogEntry(
                    id: "\(ownerID.utf8.count):\(ownerID)\(identity):\(ordinal)",
                    title: title ?? source.name,
                    owner: source,
                    isHidden: hidden,
                    preferenceID: "\(source.identity.utf8.count):\(source.identity)\(itemPreferenceID)"
                )
                scannedElements[entry.actionID] = ActionTarget(
                    element: item, sourcePID: source.pid, identifier: identifier, title: title, previousFrame: itemFrame
                )
                entries.append(entry)
            }
        }

        guard !Task.isCancelled else { return [] }
        // A row can still be on screen while a refreshed scan is delivered to the UI.
        previousElements = elements
        elements = scannedElements
        return entries
    }

    func activate(_ actionID: UUID, refreshElement: Bool) async -> Bool {
        guard !Task.isCancelled, AXIsProcessTrusted(), let target = elements[actionID] ?? previousElements[actionID] else {
            return false
        }
        let resolved = refreshElement ? await resolveAfterLayoutChange(target) : target.element
        guard let item = resolved, !Task.isCancelled else { return false }
        let attempt = press(item)
        if attempt == .stale, !refreshElement, let replacement = resolve(target) {
            return activate(replacement, after: press(replacement))
        }
        return activate(item, after: attempt)
    }

    func position(
        of actionID: UUID, display: StatusBarGeometry, menuOwner: pid_t?
    ) -> (frame: CGRect, isOnDisplay: Bool, isHidden: Bool)? {
        guard !Task.isCancelled, AXIsProcessTrusted(), let target = elements[actionID] ?? previousElements[actionID],
              let current = resolve(target) else { return nil }
        let details = attributes(Self.frameAttributes + [kAXHiddenAttribute], of: current)
        guard let itemFrame = frame(details) else { return nil }
        let appMenus = menuOwner.map { menuFrames(owner: $0) } ?? []
        let hidden = details[kAXHiddenAttribute] as? Bool == true
            || StatusBarGeometry.isHidden(itemFrame, on: [display], appMenus: appMenus)
        return (itemFrame, display.isOnMenuBar(itemFrame), hidden)
    }

    private func activate(_ item: AXUIElement, after attempt: ActionAttempt) -> Bool {
        switch attempt {
        case .accepted: return true
        case .stale, .rejected: return false
        case .unsupported:
            // A wrapper may expose its status button as a child. Menu commands are separate AXMenuItems.
            let buttons = children(of: item).filter { child in
                [kAXButtonRole, kAXPopUpButtonRole, kAXMenuBarItemRole].contains(text(attribute(kAXRoleAttribute, of: child)))
                    && actions(of: child)?.contains(where: Self.activationActions.contains) == true
            }
            guard buttons.count == 1, let button = buttons.first else { return false }
            return press(button) == .accepted
        }
    }

    private func resolveAfterLayoutChange(_ target: ActionTarget) async -> AXUIElement? {
        guard let item = resolve(target) else { return nil }
        guard let before = target.previousFrame else { return item }
        var last: CGRect?
        for _ in 0..<6 {
            let current = frame(attributes(Self.frameAttributes, of: item))
            if let current, current != before, current == last { return item }
            last = current
            do {
                try await Task.sleep(for: .milliseconds(60))
            } catch {
                return nil
            }
        }
        return item
    }

    private func resolve(_ target: ActionTarget) -> AXUIElement? {
        let app = application(target.sourcePID)
        guard let extras = element(attribute(kAXExtrasMenuBarAttribute, of: app)) else { return nil }
        let candidates = statusElements(in: extras)
        if let same = candidates.first(where: { CFEqual($0, target.element) }) { return same }
        let matches = candidates.filter { candidate in
            if let identifier = target.identifier {
                return text(attribute(kAXIdentifierAttribute, of: candidate)) == identifier
            }
            guard let title = target.title else { return false }
            return itemTitle(attributes(Self.titleAttributes, of: candidate)) == title
        }
        return matches.count == 1 ? matches.first : nil
    }

    private func press(_ item: AXUIElement) -> ActionAttempt {
        guard !Task.isCancelled else { return .rejected }
        AXUIElementSetMessagingTimeout(item, 1)
        for action in Self.activationActions {
            switch AXUIElementPerformAction(item, action as CFString) {
            case .success, .cannotComplete:
                // Some AppKit apps block their AX reply while the native menu is tracking.
                return .accepted
            case .actionUnsupported:
                continue
            case .invalidUIElement:
                return .stale
            default:
                return .rejected
            }
        }
        return .unsupported
    }

    private func itemTitle(_ values: [String: Any]) -> String? {
        text(values[kAXTitleAttribute]) ?? text(values[kAXDescriptionAttribute]) ?? text(values[kAXHelpAttribute])
    }

    private func application(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }

    private func statusElements(in root: AXUIElement, depth: Int = 0) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(root, 0.15)
        let role = text(attribute(kAXRoleAttribute, of: root))
        if let role, Self.itemRoles.contains(role) { return [root] }
        if role != kAXMenuBarRole, actions(of: root)?.contains(where: Self.activationActions.contains) == true {
            return [root]
        }
        guard depth < 2, role == kAXMenuBarRole || role == kAXGroupRole || role == nil else { return [] }
        return children(of: root).flatMap { statusElements(in: $0, depth: depth + 1) }
    }

    private func menuFrames(owner: pid_t) -> [CGRect] {
        let app = application(owner)
        guard let bar = element(attribute(kAXMenuBarAttribute, of: app)) else { return [] }
        AXUIElementSetMessagingTimeout(bar, 0.15)
        let visibleMenus = (attribute(kAXVisibleChildrenAttribute, of: bar) as? [Any])?
            .compactMap { element($0 as CFTypeRef) } ?? children(of: bar)
        return visibleMenus.compactMap { child in
            AXUIElementSetMessagingTimeout(child, 0.15)
            return frame(attributes(Self.frameAttributes, of: child))
        }
    }

    private func attribute(_ key: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func attributes(_ keys: [String], of element: AXUIElement) -> [String: Any] {
        var values: CFArray?
        let result = AXUIElementCopyMultipleAttributeValues(element, keys as CFArray, [], &values)
        guard result == .success, let values = values as? [Any] else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }

    private func children(of root: AXUIElement) -> [AXUIElement] {
        (attribute(kAXChildrenAttribute, of: root) as? [Any] ?? []).compactMap { element($0 as CFTypeRef) }
    }

    private func actions(of element: AXUIElement) -> [String]? {
        var values: CFArray?
        guard AXUIElementCopyActionNames(element, &values) == .success else { return nil }
        return values as? [String]
    }

    private func element(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func axValue(_ value: Any?) -> AXValue? {
        guard let value, CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else { return nil }
        return ((value as CFTypeRef) as! AXValue)
    }

    private func frame(_ values: [String: Any]) -> CGRect? {
        guard let position = axValue(values[kAXPositionAttribute]), let size = axValue(values[kAXSizeAttribute]) else {
            return nil
        }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent),
              origin.x.isFinite, origin.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    private func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }

    private static let itemRoles: Set<String> = [kAXMenuBarItemRole, kAXMenuItemRole, kAXButtonRole, kAXPopUpButtonRole]
    private static let frameAttributes = [kAXPositionAttribute, kAXSizeAttribute]
    private static let titleAttributes = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
    private static let itemAttributes = frameAttributes + titleAttributes + [kAXIdentifierAttribute, kAXHiddenAttribute]
    private static let activationActions = [kAXPressAction, kAXShowMenuAction]
}
