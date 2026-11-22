import AppKit
import ApplicationServices
import Carbon
import Combine
import SwiftUI

@main
struct MenuShelfApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MenuShelfController()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { application.run() }
    }
}

enum MenuShelfStartup {
    static func opensPanel(event: NSAppleEventDescriptor?, loginEnabled: Bool) -> Bool {
        guard let event else { return !loginEnabled }
        return event.eventClass != AEEventClass(kCoreEventClass)
            || event.eventID != AEEventID(kAEOpenApplication)
            || event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue != OSType(keyAELaunchedAsLogInItem)
    }
}

private final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private enum ShelfSurface {
    case ribbon, search, settings
}

private struct ShelfContent: View {
    @ObservedObject var model: ShelfModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    let previouslyPinnedIDs: Set<String>
    let surface: ShelfSurface
    let choose: (StatusItem) -> Void
    let setPlacement: (StatusItem, StatusItemPlacement) -> Void
    let settings: () -> Void
    let close: () -> Void
    let refresh: () -> Void
    let openSystemSettings: () -> Void

    var body: some View {
        switch surface {
        case .ribbon:
            ShelfRibbon(
                items: model.items, isScanning: model.isScanning, isPinning: model.isPinning,
                feedback: model.feedback, choose: choose, setPlacement: setPlacement, openSettings: settings, close: close
            )
        case .settings:
            VStack(spacing: 0) {
                HStack {
                    Text("Cherry 설정").font(.headline)
                    Spacer()
                    Button("완료", action: close)
                        .keyboardShortcut(.defaultAction)
                }
                .padding(18)
                Divider()
                loginSettings
                if model.isTrusted {
                    Divider()
                    Text("메뉴 막대 정리")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding([.top, .horizontal], 18)
                    ItemVisibilityView(
                        items: model.items, previouslyPinnedIDs: previouslyPinnedIDs,
                        isScanning: model.isScanning, refresh: refresh, openSystemSettings: openSystemSettings
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        case .search:
            EmptyView()
        }
    }

    private var loginSettings: some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle("로그인 시 열기", isOn: Binding(
                get: { launchAtLogin.isRegistered }, set: { launchAtLogin.setEnabled($0) }
            ))
            .toggleStyle(.switch)
            if launchAtLogin.requiresApproval {
                Text("시스템 설정에서 Cherry를 허용하면 다음 로그인부터 열립니다.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            if let message = launchAtLogin.errorMessage {
                Text(message).foregroundStyle(.secondary).font(.caption)
            }
            if launchAtLogin.requiresApproval || launchAtLogin.errorMessage != nil {
                Button("로그인 항목 설정 열기", action: launchAtLogin.openSystemSettings)
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}

@MainActor
private final class MenuShelfController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = ShelfModel()
    private let catalog = StatusItemCatalog()
    private let launchAtLogin = LaunchAtLogin()
    private let previouslyPinnedIDs = Set(UserDefaults.standard.stringArray(forKey: "allowedStatusItemIDs") ?? [])
    private var menuBar: MenuBarControls?
    private var lifetime: NativeMenuLifetime?
    private var preparedSurface: ShelfSurface?
    private var menuHoldsLayout = false
    private var observers: Set<AnyCancellable> = []
    private var hotKey: ShelfHotKey?
    private var panel: ShelfPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var keyboardMonitor: Any?
    private var permissionTimer: Timer?
    private var scanTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var selectedScreen: NSScreen?
    private var panelAnchor: CGFloat?
    private var settingsWereOpened = false
    private var surface: ShelfSurface = .ribbon
    private var requestedSurface: ShelfSurface = .ribbon

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        DiskImageInstallPrompt.offer { [weak self] in
            self?.start(launchEvent: launchEvent)
        }
    }

    private func start(launchEvent: NSAppleEventDescriptor?) {
        menuBar = MenuBarControls(
            open: { [weak self] anchor in self?.togglePanel(anchor: anchor) },
            settings: { [weak self] in self?.showPanel(surface: .settings) },
            quit: { NSApp.terminate(nil) }
        )
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).sink { [weak self] _ in
            self?.dismissPanel(refreshAfterRestore: false)
            self?.finishActivation()
            self?.menuBar?.invalidateLayout()
        }.store(in: &observers)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .merge(with: workspace.publisher(for: NSWorkspace.didTerminateApplicationNotification))
            .debounce(for: .milliseconds(350), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.panel?.isVisible == true else { return }
                self.refresh()
            }.store(in: &observers)
        hotKey = ShelfHotKey { [weak self] in self?.togglePanel() }
        model.hotKeyAvailable = hotKey != nil
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event)
        }
        if MenuShelfStartup.opensPanel(event: launchEvent, loginEnabled: launchAtLogin.isEnabled) {
            showPanel()
        } else {
            model.isTrusted = AXIsProcessTrusted()
            updateDivider()
            startPermissionMonitor()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if menuBar != nil { showPanel() }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        finishActivation()
        menuBar?.setLayout(.expanded)
        scanTask?.cancel()
        permissionTimer?.invalidate()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    private func togglePanel(anchor: CGPoint? = nil) {
        if panel?.isVisible == true {
            dismissPanel()
        } else {
            showPanel(anchor: anchor)
        }
    }

    private func showPanel(anchor: CGPoint? = nil, surface next: ShelfSurface = .ribbon, reset: Bool = true) {
        if reset { finishActivation() }
        let point = anchor ?? NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let panel = self.panel ?? createPanel()
        selectedScreen = screen
        panelAnchor = anchor?.x
        model.hasNotch = screen.auxiliaryTopLeftArea != nil && screen.auxiliaryTopRightArea != nil
        model.isTrusted = AXIsProcessTrusted()
        requestedSurface = next
        surface = model.isTrusted || next == .settings ? next : .search
        prepare(model.isTrusted && surface != .search ? surface : nil)
        if surface == .settings { launchAtLogin.refresh() }
        if reset {
            model.reset()
        }
        hostingView?.rootView = content(for: surface)
        positionPanel(on: screen)
        panel.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
        if model.isTrusted && reset { refresh() }
        startPermissionMonitor()
    }

    private func positionPanel(on screen: NSScreen) {
        let available = screen.visibleFrame
        let preferredWidth: CGFloat = surface == .ribbon ? max(315, 105 + CGFloat(model.items.count) * 44) : 448
        let preferredHeight: CGFloat
        switch surface {
        case .ribbon: preferredHeight = model.feedback == nil ? 66 : 92
        case .search: preferredHeight = model.isTrusted ? 492 : 280
        case .settings: preferredHeight = model.isTrusted ? 490 : 235
        }
        let width = min(preferredWidth, available.width - 24)
        let height = min(preferredHeight, available.height - 24)
        let center = panelAnchor ?? available.midX
        let x = min(max(center - width / 2, available.minX + 12), available.maxX - width - 12)
        let y = available.maxY - height - 10
        panel?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: false)
    }

    private func createPanel() -> ShelfPanel {
        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 448, height: 492),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.title = "Cherry"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        self.hostingView = hostingView
        self.panel = panel
        return panel
    }

    private func content(for surface: ShelfSurface) -> AnyView {
        if surface != .search {
            return AnyView(ShelfContent(
                model: model,
                launchAtLogin: launchAtLogin,
                previouslyPinnedIDs: previouslyPinnedIDs,
                surface: surface,
                choose: { [weak self] item in self?.activate(item, fromRibbon: surface == .ribbon) },
                setPlacement: { [weak self] item, placement in self?.setPlacement(placement, for: item) },
                settings: { [weak self] in self?.showPanel(surface: .settings) },
                close: { [weak self] in self?.dismissPanel() },
                refresh: { [weak self] in self?.refresh() },
                openSystemSettings: { [weak self] in self?.openMenuBarSettings() }
            ))
        }
        return AnyView(ShelfView(
            model: model,
            close: { [weak self] in self?.dismissPanel() },
            choose: { [weak self] item in self?.activate(item) },
            requestPermission: { [weak self] in self?.requestPermission() },
            openSettings: { [weak self] in self?.openAccessibilitySettings() },
            openPreferences: { [weak self] in self?.showPanel(surface: .settings) },
            openMenuBarSettings: { [weak self] in self?.openMenuBarSettings() },
            refresh: { [weak self] in self?.refresh() },
            quit: { NSApp.terminate(nil) }
        ))
    }

    func windowDidResignKey(_ notification: Notification) {
        if panel?.isVisible == true && !settingsWereOpened && surface != .settings { dismissPanel() }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        settingsWereOpened = false
        if surface == .settings { launchAtLogin.refresh() }
    }

    private func dismissPanel(refreshAfterRestore: Bool = true) {
        settingsWereOpened = false
        let closesPreparedPanel = preparedSurface != nil && !menuHoldsLayout
        prepare(nil)
        panel?.orderOut(nil)
        if closesPreparedPanel && refreshAfterRestore { refresh(afterLayout: true) }
    }

    private func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        model.isScanning = false
    }

    private func refresh(afterLayout: Bool = false) {
        guard let selectedScreen, model.isTrusted, AXIsProcessTrusted(), !model.isScanning, actionTask == nil else { return }
        model.isScanning = true
        model.feedback = nil
        scanTask = Task { [weak self] in
            guard let self else { return }
            if afterLayout { try? await Task.sleep(for: .milliseconds(180)) }
            guard !Task.isCancelled else { return }
            let items = await catalog.scan(on: selectedScreen)
            guard !Task.isCancelled else { return }
            model.items = items.sorted { first, second in
                let order = first.title.localizedStandardCompare(second.title)
                return order == .orderedSame ? first.id < second.id : order == .orderedAscending
            }
            model.isScanning = false
            model.reconcileSelection()
            if panel?.isVisible == true, let screen = self.selectedScreen { positionPanel(on: screen) }
        }
    }

    private func activate(_ item: StatusItem, fromRibbon: Bool = false) {
        guard actionTask == nil else { return }
        let prepared = fromRibbon && preparedSurface == .ribbon
        finishActivation()
        menuHoldsLayout = prepared || item.isHidden
        dismissPanel(refreshAfterRestore: false)
        cancelScan()
        actionTask = Task { [weak self] in
            guard let self else { return }
            if !prepared && item.isHidden {
                // Wait for AppKit to repack the native status strip before resolving the target.
                try? await Task.sleep(for: .milliseconds(220))
            }
            guard !Task.isCancelled else { return }
            lifetime = NativeMenuLifetime(ownerPID: item.ownerPID) { [weak self] observed in
                guard let self else { return }
                self.finishActivation()
                if !observed, self.model.isTrusted {
                    self.model.feedback = "‘\(item.title)’ 메뉴가 열리는 것을 확인하지 못했어요."
                    self.showPanel(surface: .search, reset: false)
                } else if self.model.isTrusted {
                    self.refresh(afterLayout: true)
                }
            }
            let accepted = await catalog.activate(item, refreshElement: item.isHidden && !prepared)
            guard !Task.isCancelled else { return }
            actionTask = nil
            lifetime?.activationFinished(accepted)
        }
    }

    private func finishActivation() {
        actionTask?.cancel()
        actionTask = nil
        model.isPinning = false
        lifetime?.cancel()
        lifetime = nil
        menuHoldsLayout = false
        updateDivider()
    }

    private func setPlacement(_ placement: StatusItemPlacement, for item: StatusItem) {
        guard actionTask == nil, model.isTrusted else { return }
        finishActivation()
        model.isPinning = true
        model.feedback = nil
        menuHoldsLayout = true
        dismissPanel(refreshAfterRestore: false)
        cancelScan()
        actionTask = Task { [weak self] in
            guard let self else { return }
            // Let the context menu stop tracking before sending native status item events.
            try? await Task.sleep(for: .milliseconds(150))
            let failure = await placeOriginal(item, placement: placement)
            guard !Task.isCancelled else { return }
            finishActivation()
            if let failure {
                model.feedback = failure
                showPanel(surface: .ribbon, reset: false)
            } else {
                refresh(afterLayout: true)
            }
        }
    }

    private func placeOriginal(_ item: StatusItem, placement: StatusItemPlacement) async -> String? {
        let unavailable = "‘\(item.title)’의 메뉴 막대 위치를 확인할 수 없어요."
        guard let menuBar, let screen = menuBar.launcherScreen,
              let start = await catalog.position(of: item, on: screen), !Task.isCancelled,
              let divider = menuBar.dividerFrame, let launcher = menuBar.launcherFrame,
              StatusItemPlacement.visible.matches(launcher, divider: divider) else { return unavailable }

        if !placement.matches(start.frame, divider: divider) || (placement == .visible && !start.isOnDisplay) {
            let windows = NativeStatusItemMove.windows()
            let process = ProcessInfo.processInfo.processIdentifier
            let host = NativeStatusItemMove.controlCenterPID
            guard let source = NativeStatusItemMove.findWindow(at: start.frame, owner: item.ownerPID, hostedBy: host, in: windows),
                  abs(source.frame.midX - divider.midX) > 1 else { return unavailable }
            let separator = NativeStatusItemMove.findWindow(at: divider, owner: process, hostedBy: host, in: windows)

            let sent: Bool
            if let separator, placement.isAdjacent(source.frame, to: separator.frame) {
                // Only the selected neighbor changes sides when we move our own divider.
                // Its app never receives a mouse-down, even if it opens a popover on press.
                sent = await NativeStatusItemMove.move(separator, to: placement == .visible ? .left : .right, of: source, owner: process)
            } else {
                let target = placement == .hidden ? separator : NativeStatusItemMove.findWindow(
                    at: launcher, owner: process, hostedBy: host, in: windows
                )
                guard let target, source.id != target.id else { return unavailable }
                sent = await NativeStatusItemMove.move(source, to: .left, of: target, owner: item.ownerPID)
            }
            guard sent else { return unavailable }
            try? await Task.sleep(for: .milliseconds(180))
        }

        guard !Task.isCancelled else { return unavailable }
        menuHoldsLayout = false
        updateDivider()
        for _ in 0..<5 {
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return unavailable }
            if let current = await catalog.position(of: item, on: screen), let divider = menuBar.dividerFrame,
               current.isHidden == (placement == .hidden), placement.matches(current.frame, divider: divider) {
                return nil
            }
        }
        switch placement {
        case .visible: return "‘\(item.title)’ 아이콘을 상단으로 옮기지 못했어요."
        case .hidden: return "‘\(item.title)’ 아이콘을 하단 바로 옮기지 못했어요."
        }
    }

    private func prepare(_ prepared: ShelfSurface?) {
        if preparedSurface != prepared {
            preparedSurface = prepared
            cancelScan()
        }
        updateDivider()
    }

    private func updateDivider() {
        if preparedSurface == .settings {
            menuBar?.setLayout(.arranging)
        } else if !model.isTrusted || preparedSurface == .ribbon || menuHoldsLayout {
            menuBar?.setLayout(.expanded)
        } else {
            menuBar?.setLayout(.collapsed)
        }
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard panel?.isKeyWindow == true else { return event }
        if let editor = panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
        switch event.keyCode {
        case 53:
            dismissPanel()
        case 125 where model.isTrusted && surface == .search:
            model.moveSelection(by: 1)
        case 126 where model.isTrusted && surface == .search:
            model.moveSelection(by: -1)
        case 15 where event.modifierFlags.contains(.command):
            refresh()
        case 3 where event.modifierFlags.contains(.command) && model.isTrusted:
            showPanel(surface: .search)
        case 12 where event.modifierFlags.contains(.command):
            NSApp.terminate(nil)
        default:
            return event
        }
        return nil
    }

    private func requestPermission() {
        settingsWereOpened = true
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(prompt as CFDictionary) { permissionChanged() }
    }

    private func openAccessibilitySettings() {
        settingsWereOpened = true
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openMenuBarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            dismissPanel()
            NSWorkspace.shared.open(url)
        }
    }

    private func startPermissionMonitor() {
        guard permissionTimer == nil else { return }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.permissionChanged()
                if self.surface == .settings && self.panel?.isVisible == true { self.launchAtLogin.refresh() }
            }
        }
    }

    private func permissionChanged() {
        let trusted = AXIsProcessTrusted()
        guard model.isTrusted != trusted else { return }
        let wasVisible = panel?.isVisible == true
        model.isTrusted = trusted
        if !trusted {
            prepare(nil)
            finishActivation()
            cancelScan()
            model.items = []
        } else {
            updateDivider()
        }
        if wasVisible {
            showPanel(surface: requestedSurface)
        } else if trusted {
            refresh()
        }
    }
}
