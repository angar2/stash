// LoginItemRegistrar protocol 준수 — SMAppService.mainApp thin wrapper
import ServiceManagement

struct SMLoginItemRegistrar: LoginItemRegistrar {
    var isRegistered: Bool {
        get throws {
            SMAppService.mainApp.status == .enabled
        }
    }

    func register() throws {
        try SMAppService.mainApp.register()
    }

    func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}
