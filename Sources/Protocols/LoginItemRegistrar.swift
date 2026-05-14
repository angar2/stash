// SMAppService Login Item 등록·해제 추상화 protocol
import ServiceManagement

protocol LoginItemRegistrar: Sendable {
    var isRegistered: Bool { get throws }
    func register() throws
    func unregister() throws
}
