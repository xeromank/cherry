import Combine
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    private let readStatus: () -> SMAppService.Status
    private let register: () throws -> Void
    private let unregister: () throws -> Void
    private let showSettings: () -> Void

    @Published private var status: SMAppService.Status
    @Published private(set) var errorMessage: String?

    init(
        readStatus: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
        showSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.readStatus = readStatus
        self.register = register
        self.unregister = unregister
        self.showSettings = showSettings
        status = readStatus()
    }

    var isRegistered: Bool { isEnabled || requiresApproval }
    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    func refresh() {
        let current = readStatus()
        guard current != status else { return }
        status = current
        errorMessage = nil
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        refresh()
        guard isRegistered != enabled else { return }

        let change = enabled ? register : unregister
        do {
            try change()
            refresh()
        } catch {
            refresh()
            if isRegistered != enabled {
                errorMessage = enabled ? "로그인 시 실행을 켜지 못했어요." : "로그인 시 실행을 끄지 못했어요."
            }
        }
    }

    func openSystemSettings() {
        showSettings()
    }
}
