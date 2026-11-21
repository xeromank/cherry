import AppKit
import ApplicationServices

@MainActor
final class NativeMenuLifetime {
    private let ownerPID: pid_t
    private let statusHosts: Set<pid_t>
    private let displayFrames: [CGRect]
    private let baselineWindows: Set<CGWindowID>
    private let initialActivePID: pid_t?
    private var closed: ((Bool) -> Void)?
    private var observer: AXObserver?
    private var registrationTask: Task<Void, Never>?
    private var timer: Timer?
    private var openMenus: [AXUIElement] = []
    private var lastMenuOpenedAt: ContinuousClock.Instant?
    private var lastMenuClosedAt: ContinuousClock.Instant?
    private var lastPopupSeenAt: ContinuousClock.Instant?
    private var fallbackDeadline = ContinuousClock.now + .seconds(5)
    private var activationReported = false

    init(ownerPID: pid_t, closed: @escaping (Bool) -> Void) {
        self.ownerPID = ownerPID
        self.closed = closed
        initialActivePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        statusHosts = Set(NSWorkspace.shared.runningApplications.compactMap { app in
            guard let bundleID = app.bundleIdentifier,
                  Self.statusHostBundleIDs.contains(bundleID) else { return nil }
            return app.processIdentifier
        })
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        displayFrames = NSScreen.screens.map { screen in
            CGRect(x: screen.frame.minX, y: primaryTop - screen.frame.maxY,
                   width: screen.frame.width, height: screen.frame.height)
        }
        baselineWindows = Self.windowIDs(in: Self.onScreenWindows())
        registrationTask = Task { [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.observeMenus()
        }

        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.update()
            }
        }
        timer.tolerance = 0.04
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func activationFinished(_ accepted: Bool) {
        guard closed != nil, !activationReported else { return }
        activationReported = true
        fallbackDeadline = .now + (accepted ? .seconds(2) : .milliseconds(300))
        update()
    }

    func cancel() {
        closed = nil
        registrationTask?.cancel()
        registrationTask = nil
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            self.observer = nil
        }
        openMenus.removeAll()
    }

    private func observeMenus() {
        guard ownerPID > 0, AXIsProcessTrusted() else { return }
        var result: AXObserver?
        let error = AXObserverCreate(ownerPID, { _, element, notification, context in
            guard let context else { return }
            let lifetime = Unmanaged<NativeMenuLifetime>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { lifetime.received(notification as String, for: element) }
        }, &result)
        guard error == .success, let result else { return }

        let app = AXUIElementCreateApplication(ownerPID)
        AXUIElementSetMessagingTimeout(app, 0.12)
        let context = Unmanaged.passUnretained(self).toOpaque()
        let registrations = [kAXMenuOpenedNotification, kAXMenuClosedNotification].map { notification in
            AXObserverAddNotification(result, app, notification as CFString, context)
        }
        guard registrations.contains(.success) else { return }
        observer = result
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
    }

    private func received(_ notification: String, for element: AXUIElement) {
        guard closed != nil else { return }
        if notification == kAXMenuOpenedNotification {
            if !openMenus.contains(where: { CFEqual($0, element) }) {
                openMenus.append(element)
            }
            lastMenuOpenedAt = .now
        } else if notification == kAXMenuClosedNotification,
                  let index = openMenus.firstIndex(where: { CFEqual($0, element) }) {
            openMenus.remove(at: index)
            if openMenus.isEmpty { lastMenuClosedAt = .now }
        }
    }

    private func update() {
        guard closed != nil else { return }
        let now = ContinuousClock.now
        if Self.onScreenWindows().contains(where: isNewPopup) {
            lastPopupSeenAt = now
            return
        }

        // A submenu replacement can temporarily remove its predecessor from the window list.
        if let lastPopupSeenAt, now - lastPopupSeenAt < .milliseconds(500) { return }
        if let lastMenuOpenedAt, !openMenus.isEmpty, lastPopupSeenAt == nil,
           now - lastMenuOpenedAt < .seconds(30) {
            return
        }
        if let lastMenuClosedAt, now - lastMenuClosedAt < .milliseconds(200) { return }

        let observedInterface = lastPopupSeenAt != nil || lastMenuOpenedAt != nil
        guard now >= fallbackDeadline || (activationReported && observedInterface) else { return }
        let activatedApp = initialActivePID != ownerPID
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID
        let callback = closed
        cancel()
        callback?(observedInterface || activatedApp)
    }

    private func isNewPopup(_ window: [String: Any]) -> Bool {
        guard let id = window[kCGWindowNumber as String] as? CGWindowID, !baselineWindows.contains(id),
              let pid = window[kCGWindowOwnerPID as String] as? pid_t,
              let layer = window[kCGWindowLayer as String] as? Int,
              pid == ownerPID || statusHosts.contains(pid),
              let dictionary = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
              bounds.width >= 22, bounds.height >= 22,
              (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return false }

        guard let display = displayFrames.first(where: { $0.intersects(bounds) }) else { return false }
        if Self.popupLayers.contains(layer) {
            return pid == ownerPID || bounds.minY < display.minY + 160
        }
        return pid == ownerPID && Self.popoverLayers.contains(layer)
            && bounds.minY >= display.minY && bounds.minY < display.minY + 120
            && bounds.width < display.width * 0.8 && bounds.height < display.height * 0.9
    }

    private static func windowIDs(in windows: [[String: Any]]) -> Set<CGWindowID> {
        Set(windows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })
    }

    private static func onScreenWindows() -> [[String: Any]] {
        CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
    }

    private static let statusHostBundleIDs: Set<String> = [
        "com.apple.controlcenter", "com.apple.systemuiserver", "com.apple.MenuBarAgent"
    ]
    private static let popupLayers = Set([.popUpMenuWindow, .tornOffMenuWindow].map { Int(CGWindowLevelForKey($0)) })
    private static let popoverLayers = Set([.floatingWindow, .modalPanelWindow].map { Int(CGWindowLevelForKey($0)) })
}
