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
        UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
    }

    private let permissionService: PermissionService
    private var pollingTask: Task<Void, Never>?

    init(permissionService: PermissionService) {
        self.permissionService = permissionService
    }

    /// 권한 감지 폴링 횟수(1초 간격). dmg판은 최대 2분이다.
    /// App Store판은 상한을 두지 않는다 (TASK-113) — 시스템 설정에서 목록을 찾아 켜기까지 2분을 넘기는 일이 실제로 있었고
    /// (사용자 확인 2026-10-06, 켠 뒤에도 화면이 대기 상태로 남음), 권한 단계를 떠나면 `stopPermissionPolling` 이 멈춘다.
    private static var permissionPollingTicks: Int {
        #if APP_STORE
        return Int.max
        #else
        return 120
        #endif
    }

    func startPermissionPolling() {
        pollingTask?.cancel()
        pollingTask = Task { @MainActor in
            await permissionService.startOnboardingPolling()
        }
        // 매 1초 recheck — granted 감지 시 UI 상태만 전환. 다음 페이지 advance 는 사용자가 "다음으로" 버튼 명시 클릭 (TASK-070).
        pollingTask = Task { @MainActor in
            for _ in 0..<Self.permissionPollingTicks {
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
        UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.autoPasteEnabled)
        Logger.ui.info("Onboarding: Accessibility 권한 건너뛰기 — autoPasteEnabled = false")
        advanceToTutorial()
    }

    func advanceToTutorial() {
        stopPermissionPolling()
        phase = .tutorial
    }

    func complete() {
        UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
        Logger.ui.info("Onboarding 완료")
    }

    func openSystemSettingsForAccessibility() {
        #if APP_STORE
        // TASK-113 — 샌드박스판은 요청을 불러야 손쉬운 사용 목록에 앱이 올라온다. 설정 화면을 열기 직전에 부른다.
        AXPermissionChecker.requestPostEventAccess()
        // 온보딩 창은 모든 앱 창 위(.modalPanel)에 떠 있어 방금 연 시스템 설정 창을 덮는다 (사용자 확인 2026-10-06 —
        // 버튼을 눌러도 설정 창이 보이지 않음). 설정을 여는 순간 일반 창 높이로 내려 설정 창이 앞에 올 수 있게 한다.
        for window in NSApp.windows where window is OnboardingNSWindow {
            window.level = .normal
        }
        #endif
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlString) {
            #if APP_STORE
            // 샌드박스 앱의 열기는 시스템 대리자를 거쳐 설정 앱이 앞으로 오지 않을 수 있다. 열린 뒤 직접 앞으로 가져온다.
            NSWorkspace.shared.open(url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                if let error {
                    Logger.ui.error("Onboarding: 시스템 설정 열기 실패 — \(error.localizedDescription, privacy: .public)")
                }
                _ = app?.activate()
            }
            #else
            NSWorkspace.shared.open(url)
            #endif
        }
    }
}
