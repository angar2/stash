// Onboarding 3단계 상태 머신 (UX-UI §3 정합)
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
            // statusPublisher Combine 구독은 .receive(on:) 메인 — 별도 task
        }
        // status 변경 추적 — 매 1초 recheck (시스템 환경설정에서 권한 부여 시 PermissionService.subject 갱신)
        pollingTask = Task { @MainActor in
            for _ in 0..<120 {  // 최대 2분 polling
                if Task.isCancelled { return }
                await permissionService.recheck()
                if await permissionService.currentStatus() == .granted {
                    permissionGrantedSnapshot = true
                    try? await Task.sleep(for: .milliseconds(600))  // onboarding-toast.jsx L78-83 정합 (granted 후 600ms 후 step 3)
                    advanceToTutorial()
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
