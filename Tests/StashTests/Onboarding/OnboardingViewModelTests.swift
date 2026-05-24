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

    @Test("skipPermissionWithCopyBack — autoPasteEnabled false 저장 + tutorial 진행 (TASK-033)")
    func skipPermissionFlow() {
        let vm = makeViewModel()
        // TASK-033 — UserDefaults register default = true. 테스트 격리 위해 직접 false 박기 전 키 정리.
        UserDefaults.standard.removeObject(forKey: "autoPasteEnabled")
        vm.advanceToPermission()
        vm.skipPermissionWithCopyBack()
        #expect(vm.phase == .tutorial)
        #expect(UserDefaults.standard.bool(forKey: "autoPasteEnabled") == false)
    }

    @Test("complete — hasCompletedOnboarding true 저장")
    func completeSetsFlag() {
        let vm = makeViewModel()
        #expect(vm.hasCompleted == false)
        vm.complete()
        #expect(vm.hasCompleted == true)
    }

    @Test("startPermissionPolling — granted 감지 시 phase 유지 (auto-advance 제거 — TASK-070)")
    func grantedDoesNotAutoAdvance() async {
        let vm = makeViewModel(trusted: true)
        vm.advanceToPermission()
        vm.startPermissionPolling()
        // polling loop 가 첫 iteration 에서 granted 감지 + permissionGrantedSnapshot=true 박고 자체 종료.
        // 600ms 대기 (auto-advance 제거 검증 — 기존 정책이라면 600ms 후 advanceToTutorial 자동 호출됨).
        try? await Task.sleep(for: .milliseconds(800))
        #expect(vm.permissionGrantedSnapshot == true)
        #expect(vm.phase == .permission)  // tutorial 로 자동 advance 안 됨 — 사용자가 "다음으로" 버튼 명시 클릭해야 진행
    }

    @Test("advanceToTutorial — 사용자 명시 호출 시 phase 전환 permission → tutorial (TASK-070)")
    func advanceToTutorialExplicit() {
        let vm = makeViewModel()
        vm.advanceToPermission()
        vm.advanceToTutorial()
        #expect(vm.phase == .tutorial)
    }
}
