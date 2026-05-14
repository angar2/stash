// SMAppService를 통해 Login Item 등록·해제를 담당하는 서비스
import Foundation

@MainActor
final class LoginItemService {
    private let registrar: LoginItemRegistrar

    init(registrar: LoginItemRegistrar) {
        self.registrar = registrar
    }

    var isEnabled: Bool {
        get throws {
            try registrar.isRegistered
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try registrar.register()
        } else {
            try registrar.unregister()
        }
    }
}
