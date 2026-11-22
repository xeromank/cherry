import Foundation
import XCTest
@testable import MenuShelf

final class DiskImageInstallTests: XCTestCase {
    func testOfferIsLimitedToAppBundlesOnReadOnlyVolumesOutsideApplications() {
        let applications = URL(fileURLWithPath: "/Applications")
        let mounted = URL(fileURLWithPath: "/Volumes/Cherry/Cherry.app")
        let installed = applications.appendingPathComponent("Utilities/Cherry.app")
        let backup = URL(fileURLWithPath: "/Applications-Backup/Cherry.app")

        XCTAssertTrue(DiskImageInstall.shouldOffer(bundleURL: mounted, applications: [applications], localReadOnlyVolume: true))
        XCTAssertTrue(DiskImageInstall.shouldOffer(bundleURL: backup, applications: [applications], localReadOnlyVolume: true))
        XCTAssertFalse(DiskImageInstall.shouldOffer(bundleURL: mounted, applications: [applications], localReadOnlyVolume: false))
        XCTAssertFalse(DiskImageInstall.shouldOffer(bundleURL: installed, applications: [applications], localReadOnlyVolume: true))
        XCTAssertFalse(DiskImageInstall.shouldOffer(bundleURL: mounted.deletingPathExtension(), applications: [applications], localReadOnlyVolume: true))
    }

    func testDestinationIdentifiesInstalledCherryAndRejectsOtherOccupants() throws {
        let folder = try makeTemporaryDirectory()
        let target = folder.appendingPathComponent("Cherry.app")
        XCTAssertEqual(DiskImageInstall.destination(bundleIdentifier: "example.cherry", in: folder), .vacant(target))

        try makeBundle(at: target, identifier: "example.cherry")
        XCTAssertEqual(DiskImageInstall.destination(bundleIdentifier: "example.cherry", in: folder), .installed(target))
        XCTAssertEqual(DiskImageInstall.destination(bundleIdentifier: "example.unrelated", in: folder), .occupied(target))

        let alternate = folder.appendingPathComponent("Alternate.app")
        try FileManager.default.moveItem(at: target, to: alternate)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: alternate)
        XCTAssertEqual(DiskImageInstall.destination(bundleIdentifier: "example.cherry", in: folder), .occupied(target))
        try FileManager.default.removeItem(at: alternate)
        XCTAssertEqual(DiskImageInstall.destination(bundleIdentifier: "example.cherry", in: folder), .occupied(target))
    }

    func testCopyKeepsSourceAndDoesNotOverwriteDestination() throws {
        let folder = try makeTemporaryDirectory()
        let source = folder.appendingPathComponent("Source.app")
        let destination = folder.appendingPathComponent("Cherry.app")
        try makeBundle(at: source, identifier: "example.cherry")

        try DiskImageInstall.copy(source, to: destination)
        let sourceInfo = source.appendingPathComponent("Contents/Info.plist")
        let destinationInfo = destination.appendingPathComponent("Contents/Info.plist")
        XCTAssertEqual(try Data(contentsOf: sourceInfo), try Data(contentsOf: destinationInfo))

        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        XCTAssertThrowsError(try DiskImageInstall.copy(source, to: destination))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func makeBundle(at url: URL, identifier: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"],
            format: .xml, options: 0
        )
        try info.write(to: contents.appendingPathComponent("Info.plist"))
    }
}
