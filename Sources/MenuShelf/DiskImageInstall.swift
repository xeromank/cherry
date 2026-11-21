import Darwin
import Foundation

enum DiskImageInstall {
    enum Destination: Equatable {
        case vacant(URL)
        case installed(URL)
        case occupied(URL)
    }

    static func shouldOffer(bundleURL: URL, applications: [URL], localReadOnlyVolume: Bool) -> Bool {
        guard localReadOnlyVolume, bundleURL.isFileURL, bundleURL.pathExtension.lowercased() == "app" else {
            return false
        }
        let path = bundleURL.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        return !applications.contains { directory in
            let base = directory.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            return path.starts(with: base)
        }
    }

    static func destination(bundleIdentifier: String, in applications: URL) -> Destination {
        let url = applications.appendingPathComponent("Cherry.app", isDirectory: false)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                  Bundle(url: url)?.bundleIdentifier == bundleIdentifier else {
                return .occupied(url)
            }
            return .installed(url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .vacant(url)
        } catch {
            return .occupied(url)
        }
    }

    static func copy(_ source: URL, to destination: URL) throws {
        let files = FileManager.default
        let staging = try files.url(
            for: .itemReplacementDirectory, in: .userDomainMask,
            appropriateFor: destination.deletingLastPathComponent(), create: true
        )
        defer { try? files.removeItem(at: staging) }
        var stagedApp = staging.appendingPathComponent(destination.lastPathComponent)
        try files.copyItem(at: source, to: stagedApp)

        // A mounted image can supply quarantine metadata that isn't a direct bundle attribute.
        let quarantine = try source.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
        if let quarantine, try stagedApp.resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties == nil {
            var resources = URLResourceValues()
            resources.quarantineProperties = quarantine
            try stagedApp.setResourceValues(resources)
        }

        // An exclusive rename leaves any item that appeared during the copy intact.
        let failure = stagedApp.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to -> POSIXError? in
                guard let from, let to else { return POSIXError(.EINVAL) }
                guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else {
                    return POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                return nil
            }
        }
        if let failure { throw failure }
    }
}
