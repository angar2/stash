// Onboarding 3단계 상태 머신 (UX-UI §3 정합). TASK-070 — 권한 부여 자동 polling 유지 (UI 상태 자동 전환) + 다음 페이지 auto-advance 제거 (사용자 명시 클릭만).
import Foundation
import Observation
import AppKit
import OSLog

enum OnboardingPhase: Sendable {
    case welcome
    case permission
    case tutorial
}

@MainActor
@Observable
final class OnboardingViewModel {
    var phase: OnboardingPhase = .welcome
    var permissionGrantedSnapshot: Bool = false
    var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    private let permissionService: PermissionService
    private var pollingTask: Task<Void, Never>?

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
    }

    func startPermissionPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await permissionService.startOnboardingPolling()
        }
        // 매 1초 recheck — granted 감지 시 UI 상태만 전환. 다음 페이지 advance 는 사용자가 "다음으로" 버튼 명시 클릭 (TASK-070).
        pollingTask = Task { @MainActor in
            for _ in 0..<120 {  // 최대 2분 polling
                if Task.isCancelled { return }
                await permissionService.recheck()
                if await permissionService.currentStatus() == .granted {
                    permissionGrantedSnapshot = true
                    Logger.ui.info("Onboarding: 권한 부여 감지 — UI 상태 전환 (auto-advance 제거됨, 사용자 명시 클릭 대기)")
                    return
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopPermissionPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        Task { @MainActor in
            await permissionService.stopOnboardingPolling()
        }
    }

    func advanceToPermission() {
        phase = .permission
        startPermissionPolling()
    }

    func skipPermissionWithCopyBack() {
        // TASK-033 — UserDefaults 키 갱신. PasteMode enum → autoPasteEnabled boolean. 권한 건너뛰기 = autoPasteEnabled false (copy-back 모드 자연 활성).
        UserDefaults.standard.set(false, forKey: "autoPasteEnabled")
        Logger.ui.info("Onboarding: Accessibility 권한 건너뛰기 — autoPasteEnabled = false")
        advanceToTutorial()
    }

    func advanceToTutorial() {
        stopPermissionPolling()
        phase = .tutorial
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        Logger.ui.info("Onboarding 완료")
    }

    func openSystemSettingsForAccessibility() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
}
