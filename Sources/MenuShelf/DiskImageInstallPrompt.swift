import AppKit

@MainActor
enum DiskImageInstallPrompt {
    private static let installedLaunchArgument = "--cherry-open-installed"

    static func offer(
        for bundle: Bundle = .main,
        applications: URL? = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first,
        continueLaunching: @escaping () -> Void
    ) {
        let source = bundle.bundleURL
        let volume = try? source.resourceValues(forKeys: [.volumeIsReadOnlyKey, .volumeIsLocalKey])
        guard let applications, let bundleIdentifier = bundle.bundleIdentifier,
              !ProcessInfo.processInfo.arguments.contains(installedLaunchArgument),
              DiskImageInstall.shouldOffer(
                  bundleURL: source,
                  applications: [applications] + FileManager.default.urls(for: .applicationDirectory, in: [.userDomainMask, .systemDomainMask]),
                  localReadOnlyVolume: volume?.volumeIsReadOnly == true && volume?.volumeIsLocal == true
              ) else {
            continueLaunching()
            return
        }

        switch DiskImageInstall.destination(bundleIdentifier: bundleIdentifier, in: applications) {
        case .vacant(let destination):
            guard confirm(
                title: "Cherry를 응용 프로그램으로 이동할까요?",
                detail: "응용 프로그램 폴더에 Cherry를 복사하고 그곳에서 엽니다.",
                button: "응용 프로그램으로 이동"
            ) else {
                continueLaunching()
                return
            }
            do {
                try DiskImageInstall.copy(source, to: destination)
                openInstalled(destination, in: applications, continueLaunching: continueLaunching)
            } catch {
                showInFinder(applications, message: "Cherry를 응용 프로그램 폴더에 복사하지 못했어요.")
                continueLaunching()
            }
        case .installed(let destination):
            if confirm(
                title: "응용 프로그램 폴더에 Cherry가 있어요",
                detail: "설치된 Cherry를 열거나, 이 DMG 안의 Cherry를 응용 프로그램 폴더에 끌어다 놓아 교체할 수 있어요.",
                button: "설치된 Cherry 열기"
            ) {
                openInstalled(destination, in: applications, continueLaunching: continueLaunching)
            } else {
                continueLaunching()
            }
        case .occupied:
            showInFinder(applications, message: "응용 프로그램 폴더에 이름이 같은 항목이 있어요.")
            continueLaunching()
        }
    }

    private static func openInstalled(_ destination: URL, in applications: URL, continueLaunching: @escaping () -> Void) {
        let workspace = NSWorkspace.shared
        let config = NSWorkspace.OpenConfiguration()
        let installedPath = destination.resolvingSymlinksInPath().path
        config.createsNewApplicationInstance = !workspace.runningApplications.contains {
            $0.bundleURL?.resolvingSymlinksInPath().path == installedPath
        }
        config.allowsRunningApplicationSubstitution = false
        config.arguments = [installedLaunchArgument]
        workspace.openApplication(at: destination, configuration: config) { app, error in
            Task { @MainActor in
                if error == nil, let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    NSApp.terminate(nil)
                } else {
                    showInFinder(applications, message: "응용 프로그램 폴더의 Cherry를 열지 못했어요.")
                    continueLaunching()
                }
            }
        }
    }

    private static func showInFinder(_ applications: URL, message: String) {
        if confirm(
            title: message,
            detail: "Finder에서 응용 프로그램 폴더를 열어 설치를 확인할 수 있어요.",
            button: "응용 프로그램 폴더 열기"
        ) {
            NSWorkspace.shared.open(applications)
        }
    }

    private static func confirm(title: String, detail: String, button: String) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = detail
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "현재 위치에서 열기").keyEquivalent = "\u{1b}"
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
