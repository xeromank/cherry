@testable import MenuShelf
import ServiceManagement
import XCTest

final class LaunchAtLoginTests: XCTestCase {
    private enum TestError: Error { case unavailable }

    func testRegistersAndUnregistersAgainstCurrentStatus() async {
        await MainActor.run {
            var status = SMAppService.Status.notRegistered
            var registrations = 0
            var removals = 0
            let login = LaunchAtLogin(
                readStatus: { status },
                register: {
                    registrations += 1
                    status = .enabled
                },
                unregister: {
                    removals += 1
                    status = .notRegistered
                }
            )

            XCTAssertFalse(login.isRegistered)
            login.setEnabled(true)
            login.setEnabled(true)
            XCTAssertTrue(login.isRegistered)
            XCTAssertTrue(login.isEnabled)
            XCTAssertEqual(registrations, 1)

            login.setEnabled(false)
            XCTAssertFalse(login.isRegistered)
            XCTAssertEqual(removals, 1)
            XCTAssertNil(login.errorMessage)
        }
    }

    func testPendingApprovalIsRegisteredAndCanBeDisabled() async {
        await MainActor.run {
            var status = SMAppService.Status.notRegistered
            let login = LaunchAtLogin(
                readStatus: { status },
                register: {
                    status = .requiresApproval
                    throw TestError.unavailable
                },
                unregister: { status = .notRegistered }
            )

            login.setEnabled(true)
            XCTAssertTrue(login.isRegistered)
            XCTAssertFalse(login.isEnabled)
            XCTAssertTrue(login.requiresApproval)
            XCTAssertNil(login.errorMessage)

            login.setEnabled(false)
            XCTAssertFalse(login.isRegistered)
            XCTAssertFalse(login.requiresApproval)
        }
    }

    func testFailuresKeepActualStatusAndRefreshUpdatesExternalChanges() async {
        await MainActor.run {
            var status = SMAppService.Status.notRegistered
            let login = LaunchAtLogin(
                readStatus: { status },
                register: { throw TestError.unavailable },
                unregister: { throw TestError.unavailable }
            )

            login.setEnabled(true)
            XCTAssertFalse(login.isRegistered)
            XCTAssertNotNil(login.errorMessage)

            status = .enabled
            login.refresh()
            XCTAssertTrue(login.isEnabled)
            XCTAssertNil(login.errorMessage)

            login.setEnabled(false)
            XCTAssertTrue(login.isRegistered)
            XCTAssertNotNil(login.errorMessage)
        }
    }
}
