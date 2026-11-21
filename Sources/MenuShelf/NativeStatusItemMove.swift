import AppKit
import CoreGraphics

enum StatusItemPlacement {
    case visible, hidden

    func matches(_ frame: CGRect, divider: CGRect) -> Bool {
        guard abs(frame.midY - divider.midY) <= 2 else { return false }
        switch self {
        case .visible: return frame.minX >= divider.maxX - 1
        case .hidden: return frame.maxX <= divider.minX + 1
        }
    }

    func isAdjacent(_ frame: CGRect, to divider: CGRect) -> Bool {
        guard abs(frame.midY - divider.midY) <= 2 else { return false }
        let gap = self == .visible ? divider.minX - frame.maxX : frame.minX - divider.maxX
        return abs(gap) <= 1
    }
}

@MainActor
enum NativeStatusItemMove {
    enum Side { case left, right }

    struct Window {
        let id: CGWindowID
        let owner: pid_t
        let frame: CGRect
    }

    static var controlCenterPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
    }

    // Tahoe can host another app's status item in Control Center. AppKit may pad the
    // native window differently, so match its center and reject any ambiguity.
    nonisolated static func findWindow(at frame: CGRect, owner: pid_t, hostedBy host: pid_t?, in windows: [Window]) -> Window? {
        let matches = windows.filter {
            ($0.owner == owner || $0.owner == host)
                && abs($0.frame.midX - frame.midX) <= 1 && abs($0.frame.midY - frame.midY) <= 2
        }
        return matches.count == 1 ? matches.first : nil
    }

    static func windows() -> [Window] {
        guard let descriptions = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let statusLayer = Int(CGWindowLevelForKey(.statusWindow))
        let menuLayer = Int(CGWindowLevelForKey(.mainMenuWindow))
        let statusIDs = StatusWindowIDs.menuBarItems()
        return descriptions.compactMap { window in
            guard let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  statusIDs.map({ $0.contains(id) && layer != menuLayer }) ?? (layer == statusLayer),
                  let owner = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return Window(id: id, owner: owner, frame: frame)
        }
    }

    static func move(_ item: Window, to side: Side, of target: Window, owner: pid_t) async -> Bool {
        guard CGPreflightPostEventAccess(), !Task.isCancelled,
              let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let startsLeft = item.frame.midX < target.frame.midX
        let edge = side == .left ? target.frame.minX : target.frame.maxX
        let liftX = startsLeft ? edge : edge + (side == .left ? -1 : 1)
        let liftPoint = CGPoint(x: liftX, y: target.frame.minY)
        let dropPoint = CGPoint(x: startsLeft ? edge - item.frame.width : edge, y: liftPoint.y)
        guard let down = mouseEvent(.leftMouseDown, at: liftPoint, window: item.id, owner: owner, source: source),
              let up = mouseEvent(.leftMouseUp, at: dropPoint, window: target.id, owner: owner, source: source) else {
            return false
        }
        // Field 0x33 in mouseEvent supplies the WindowServer's status item target, even
        // when hit testing would miss it. The pair needs no path through the camera area.
        down.flags = .maskCommand
        post(down, to: owner)
        defer { post(up, to: owner) }
        try? await Task.sleep(for: .milliseconds(75))
        return !Task.isCancelled
    }

    private static func mouseEvent(
        _ type: CGEventType, at point: CGPoint, window: CGWindowID, owner: pid_t, source: CGEventSource
    ) -> CGEvent? {
        guard let windowField = CGEventField(rawValue: 0x33),
              let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        else { return nil }
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        event.setIntegerValueField(windowField, value: Int64(window))
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(owner))
        return event
    }

    private static func post(_ event: CGEvent, to owner: pid_t) {
        event.copy()?.post(tap: .cgSessionEventTap)
        event.postToPid(owner)
    }
}
