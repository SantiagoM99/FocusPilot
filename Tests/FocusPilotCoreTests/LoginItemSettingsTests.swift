import Testing
@testable import FocusPilotCore

@MainActor
@Suite("Login item settings")
struct LoginItemSettingsTests {
    @Test func turningOnRegistersTheApp() {
        let service = FakeLoginItemService(status: .disabled)
        let settings = LoginItemSettings(service: service)

        settings.setEnabled(true)

        #expect(service.status == .enabled)
        #expect(settings.isEnabled)
    }

    @Test func turningOffUnregistersTheApp() {
        let service = FakeLoginItemService(status: .enabled)
        let settings = LoginItemSettings(service: service)

        settings.setEnabled(false)

        #expect(service.status == .disabled)
        #expect(!settings.isEnabled)
    }

    @Test func failedRegistrationKeepsTheActualStatusAndReportsTheError() {
        let service = FakeLoginItemService(status: .disabled, failure: FakeLoginItemService.Failure())
        let settings = LoginItemSettings(service: service)

        settings.setEnabled(true)

        #expect(!settings.isEnabled)
        #expect(settings.errorMessage != nil)
    }

    @Test func successAfterAFailureClearsTheError() {
        let service = FakeLoginItemService(status: .disabled, failure: FakeLoginItemService.Failure())
        let settings = LoginItemSettings(service: service)
        settings.setEnabled(true)

        service.failure = nil
        settings.setEnabled(true)

        #expect(settings.errorMessage == nil)
    }

    @Test func pendingApprovalCountsAsOnAndIsReported() {
        let service = FakeLoginItemService(status: .disabled, statusAfterRegistering: .requiresApproval)
        let settings = LoginItemSettings(service: service)

        settings.setEnabled(true)

        #expect(settings.isEnabled)
        #expect(settings.needsApproval)
    }
}

@MainActor
final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: LoginItemStatus
    var failure: Failure?
    private let statusAfterRegistering: LoginItemStatus

    init(status: LoginItemStatus, failure: Failure? = nil, statusAfterRegistering: LoginItemStatus = .enabled) {
        self.status = status
        self.failure = failure
        self.statusAfterRegistering = statusAfterRegistering
    }

    func register() throws {
        if let failure { throw failure }
        status = statusAfterRegistering
    }

    func unregister() throws {
        if let failure { throw failure }
        status = .disabled
    }

    func openSystemSettings() {}
}
