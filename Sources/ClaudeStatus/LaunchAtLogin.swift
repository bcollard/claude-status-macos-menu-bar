import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var lastError: String?

    private init() {
        self.isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func refresh() {
        isEnabled = (SMAppService.mainApp.status == .enabled)
    }

    func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = "\(error.localizedDescription)"
        }
        refresh()
    }
}
