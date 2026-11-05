import AppDomain
import ServiceManagement

/// Opens the app at login, as a login item of the app itself.
@MainActor
package final class MainAppLoginItem: LoginItem {
    package init() {}

    package var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    package func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
