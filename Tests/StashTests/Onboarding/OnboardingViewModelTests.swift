// OnboardingViewModel 단위 테스트 — phase 전환 + skip copy-back + 완료 (UX-UI §3 정합)
import Testing
import Foundation
@testable import stash

@MainActor
@Suite("OnboardingViewModel")
struct OnboardingViewModelTests {
    private func makeViewModel(trusted: Bool = false) -> OnboardingViewModel {
        let checker = MockPermissionChecker()
        checker.trusted = trusted
        let permSvc = PermissionService(checker: checker)
        // 격리 — 관련 UserDefaults 키 클린
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "pasteMode")
        return OnboardingViewModel(permissionService: permSvc)
    }

    @Test("초기 phase — welcome")
    func initialPhaseIsWelcome() {
        let vm = makeViewModel()
        #expect(vm.phase == .welcome)
    }

    @Test("advanceToPermission — phase 전환 welcome → permission")
    func welcomeToPermission() {
        let vm = makeViewModel()
        vm.advanceToPermission()
        #expect(vm.phase == .permission)
    }

    @Test("skipPermissionWithCopyBack — pasteMode copyBack 저장 + tutorial 진행")
    func skipPermissionFlow() {
        let vm = makeViewModel()
        vm.advanceToPermission()
        vm.skipPermissionWithCopyBack()
        #expect(vm.phase == .tutorial)
        #expect(UserDefaults.standard.string(forKey: "pasteMode") == PasteMode.copyBack.rawValue)
    }

    @Test("complete — hasCompletedOnboarding true 저장")
    func completeSetsFlag() {
        let vm = makeViewModel()
        #expect(vm.hasCompleted == false)
        vm.complete()
        #expect(vm.hasCompleted == true)
    }
}
