// 자동 업데이트 창구 — Sparkle 업데이터를 단독 보유하고 UI 는 이 창구만 사용한다 (TASK-102 / TECH-STACK §3-6)
import Foundation
import Observation
import OSLog
import Sparkle

/// 사용자가 *직접* 누른 확인의 진행·결과. 설정 `정보` 탭이 항목 우측 문구로 표시한다.
///
/// 자동 확인 결과는 여기 담지 않는다 — 사용자가 요청하지 않은 동작의 결과로 방해하지 않는다
/// (UX-UI *자동 업데이트* §설정 항목).
enum ManualUpdateCheckState: Equatable {
    /// 응답 대기 — 항목 비활성 + 회전 표시.
    case checking
    /// 최신 상태.
    case upToDate
    /// 이정표 접근 실패 등.
    case failed
}

@MainActor
@Observable
final class UpdateService {

    /// popover 배너에 띄울 대기 중인 새 버전 표기 (예 `1.3.0`). `nil` = 배너 없음.
    ///
    /// 자동 확인이 새 버전을 찾았고 사용자가 아직 반응하지 않은 상태에서만 값이 있다.
    private(set) var pendingUpdateVersion: String?

    /// 사용자가 직접 누른 확인의 상태. `nil` = 표시할 것 없음.
    private(set) var manualCheckState: ManualUpdateCheckState?

    /// 자동 확인 켜짐 여부. 저장은 Sparkle 이 담당하며(`SUEnableAutomaticChecks`) 본 프로퍼티는 그 거울이다
    /// — 별도 영속 계층을 두지 않는다 (TECH-STACK §3-6).
    private(set) var automaticChecksEnabled: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let eventDelegate: UpdaterEventDelegate
    @ObservationIgnored private let driverDelegate: UpdateDriverDelegate

    /// 사용자가 배너를 닫은 버전. 같은 버전으로는 배너를 다시 띄우지 않는다 — 다음 버전이면 다시 띄운다
    /// (UX-UI *자동 업데이트* §알림 방식). 앱을 다시 켜면 초기화된다 — 영구 차단이 아니다.
    @ObservationIgnored private var bannerDismissedVersion: String?

    /// 결과 문구 자동 소거 — 잠시 뒤 사라진다 (UX-UI *자동 업데이트* §설정 항목).
    @ObservationIgnored private var clearTask: Task<Void, Never>?

    /// 사용자가 직접 누른 확인이 진행 중인지. 자동 확인 콜백이 결과 문구를 건드리지 않도록 가르는 표시.
    @ObservationIgnored private var manualCheckInFlight = false

    /// 수동 확인이 새 버전을 찾아 확인 주기가 끝나면 표준 창을 열어야 하는지.
    /// 발견 콜백 시점에는 조회 세션이 아직 열려 있어 `checkForUpdates` 가 거절된다(BL-35).
    @ObservationIgnored private var presentWindowWhenCycleEnds = false

    /// 결과 문구가 화면에 남아 있는 시간.
    private static let outcomeDisplayDuration: Duration = .seconds(4)

    init() {
        // delegate 를 먼저 만들고 controller 에 넘긴 뒤 back-reference 를 채운다 (상호 참조라 순서 고정).
        let eventDelegate = UpdaterEventDelegate()
        let driverDelegate = UpdateDriverDelegate()
        self.eventDelegate = eventDelegate
        self.driverDelegate = driverDelegate
        // startingUpdater: true — 생성 즉시 업데이터 기동. 다음 runloop 에서 자동 확인 주기가 돈다.
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: eventDelegate,
            userDriverDelegate: driverDelegate
        )
        self.automaticChecksEnabled = controller.updater.automaticallyChecksForUpdates
        eventDelegate.owner = self
        driverDelegate.owner = self
        Logger.update.info(
            "UpdateService 생성 — 자동 확인 \(self.automaticChecksEnabled ? "ON" : "OFF"), 주기 \(self.controller.updater.updateCheckInterval, format: .fixed(precision: 0))초"
        )
    }

    // MARK: - 사용자 조작

    /// 설정 `정보` 탭 *업데이트 확인*.
    ///
    /// UI 를 띄우지 않는 조회(`checkForUpdateInformation`)로 시작한다. 표준 `checkForUpdates` 는
    /// 최신 상태일 때 자체 알림 창을 띄워, 항목 우측 문구로 알리는 승인 설계와 충돌한다.
    /// 새 버전이 *있을 때만* 표준 창을 연다 (`presentUpdateWindow`).
    func checkForUpdatesManually() {
        // 이미 찾아둔 새 버전이 있으면 다시 묻지 않는다 — 사용자가 알고 싶은 답이 이미 나와 있다.
        // 배너를 누른 것과 같게 곧바로 표준 창을 연다.
        if pendingUpdateVersion != nil {
            Logger.update.info("수동 확인 — 대기 중인 새 버전이 있어 창을 바로 연다")
            presentUpdateWindow()
            return
        }
        // 배너를 ×로 닫았어도 **Sparkle 쪽 업데이트 세션은 살아 있다.** 이때 `checkForUpdateInformation` 은
        // 조용히 무시돼(Sparkle 사양) «확인 중…» 에 갇히고, 사용자는 앱 안에서 되돌릴 방법을 잃는다(검수 2026-08-02).
        // `checkForUpdates` 는 진행 중인 업데이트를 *다시 앞으로 불러오므로* 그 경로로 보낸다.
        if controller.updater.sessionInProgress {
            Logger.update.info("수동 확인 — 진행 중인 업데이트가 있어 창을 다시 불러온다")
            presentUpdateWindow()
            return
        }
        guard controller.updater.canCheckForUpdates else {
            Logger.update.info("수동 확인 무시 — 확인 불가 상태")
            return
        }
        clearTask?.cancel()
        manualCheckInFlight = true
        manualCheckState = .checking
        Logger.update.info("수동 확인 시작")
        controller.updater.checkForUpdateInformation()
    }

    /// 설정 `일반` 탭 *업데이트 자동 확인* 토글. 저장 버튼 없이 즉시 반영한다.
    func setAutomaticChecksEnabled(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
        automaticChecksEnabled = enabled
        Logger.update.info("자동 확인 \(enabled ? "ON" : "OFF")")
    }

    /// 표준 업데이트 창을 연다 — 릴리즈 노트 열람·설치·진행·재실행은 이 창이 담당한다.
    /// popover 는 포커스를 잃으면 닫혀 설치 과정을 담을 수 없다 (UX-UI *자동 업데이트* §업데이트 창).
    func presentUpdateWindow() {
        Logger.update.info("표준 업데이트 창 열기")
        controller.updater.checkForUpdates()
    }

    /// popover 배너를 눌렀을 때 — 표준 창을 연다. 배너는 창이 뜬 뒤 라이브러리 콜백으로 사라진다.
    func openUpdateFromBanner() {
        Logger.update.info("배너에서 업데이트 창 열기")
        presentUpdateWindow()
    }

    /// popover 배너의 닫기(`×`) — **해당 버전에 한해** 다시 띄우지 않는다. 다음 버전이면 다시 뜬다.
    func dismissBanner() {
        guard let version = pendingUpdateVersion else { return }
        Logger.update.info("배너 닫기 — \(version, privacy: .public) 은 다시 알리지 않음")
        bannerDismissedVersion = version
        pendingUpdateVersion = nil
        notifyPopoverLayoutChanged()
    }

    // MARK: - delegate 콜백 수신

    /// 조회 결과 새 버전이 있음. 수동 확인이었다면 문구 대신 표준 창을 연다.
    ///
    /// 창은 여기서 열지 않고 확인 주기가 끝난 뒤(`didFinishCheckCycle`) 연다. 이 콜백은 조회 세션 안에서
    /// 불려 `checkForUpdates` 가 `sessionInProgress == YES` 로 거절된다(BL-35, v1.3.1 실기 로그).
    fileprivate func didFindUpdate(version: String) {
        Logger.update.info("새 버전 발견 — \(version, privacy: .public)")
        guard manualCheckInFlight else { return }
        manualCheckInFlight = false
        manualCheckState = nil
        presentWindowWhenCycleEnds = true
    }

    /// 조회 결과 최신 상태.
    fileprivate func didNotFindUpdate() {
        Logger.update.info("최신 상태")
        guard manualCheckInFlight else { return }
        manualCheckInFlight = false
        showOutcome(.upToDate)
    }

    /// 확인 주기 종료. 최신/발견 어느 쪽으로도 귀결되지 않았다면 실패다.
    ///
    /// Sparkle 은 세션을 닫은 뒤(`sessionInProgress = NO`) 이 콜백을 부르므로 여기서는 새 세션을 열 수 있다.
    fileprivate func didFinishCheckCycle(error: Error?) {
        if let error {
            Logger.update.error("확인 실패 — \(error.localizedDescription, privacy: .public)")
        }
        if presentWindowWhenCycleEnds {
            presentWindowWhenCycleEnds = false
            presentUpdateWindow()
            return
        }
        guard manualCheckInFlight else {
            // 자동 확인의 실패는 화면에 아무것도 표시하지 않는다 — 로그로만 남긴다.
            return
        }
        manualCheckInFlight = false
        showOutcome(.failed)
    }

    /// 자동 확인이 찾은 새 버전 — 표준 창은 억제되었고 우리가 배너로 알린다.
    fileprivate func presentBanner(for item: SUAppcastItem) {
        let version = item.displayVersionString
        guard bannerDismissedVersion != version else {
            Logger.update.info("배너 생략 — \(version, privacy: .public) 은 사용자가 닫은 버전")
            return
        }
        Logger.update.info("배너 표시 — \(version, privacy: .public)")
        pendingUpdateVersion = version
        notifyPopoverLayoutChanged()
    }

    /// 업데이트 창에서 사용자가 내린 선택에 따라 배너를 거둘지 정한다.
    ///
    /// **«나중에» 는 배너를 남긴다.** 미루겠다는 뜻이지 됐다는 뜻이 아니다 — 여기서 배너까지 지우면
    /// 다음 확인(24시간) 전까지 popover 에서 업데이트 경로가 사라진다(검수 2026-08-02).
    /// 설치·건너뛰기만 배너를 거둔다.
    fileprivate func userDidMakeChoice(_ choice: SPUUserUpdateChoice) {
        switch choice {
        case .install, .skip:
            guard pendingUpdateVersion != nil else { return }
            Logger.update.info("배너 해제 — 사용자 선택: \(choice == .install ? "설치" : "건너뛰기", privacy: .public)")
            pendingUpdateVersion = nil
            notifyPopoverLayoutChanged()
        case .dismiss:
            Logger.update.info("배너 유지 — 사용자 선택: 나중에")
        @unknown default:
            Logger.update.info("배너 유지 — 알 수 없는 선택")
        }
    }

    /// 배너가 뜨거나 사라지면 popover 높이가 그만큼 달라져야 한다.
    /// SwiftUI body 는 관찰로 즉시 따라오지만 **NSPanel frame 은 따라오지 않는다** — 힌트바 토글과 같은 경로로
    /// `PopoverWindow` 가 fittingSize 를 재측정하도록 알린다. popover 가 닫혀 있으면 아무 일도 일어나지 않는다.
    private func notifyPopoverLayoutChanged() {
        NotificationCenter.default.post(name: ClipsViewModel.displayLayoutDidChange, object: nil)
    }

    // MARK: - 내부

    private func showOutcome(_ state: ManualUpdateCheckState) {
        manualCheckState = state
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: UpdateService.outcomeDisplayDuration)
            guard !Task.isCancelled else { return }
            self?.manualCheckState = nil
        }
    }
}

// MARK: - Sparkle 업데이터 delegate

/// 확인 결과를 `UpdateService` 로 넘기는 얇은 중계. Sparkle 콜백은 메인 스레드에서 오므로
/// `assumeIsolated` 로 받는다 (프로토콜 자체는 격리 표기가 없어 `nonisolated` 필요).
@MainActor
private final class UpdaterEventDelegate: NSObject, SPUUpdaterDelegate {
    weak var owner: UpdateService?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated {
            owner?.didFindUpdate(version: item.displayVersionString)
        }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated {
            owner?.didNotFindUpdate()
        }
    }

    nonisolated func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        MainActor.assumeIsolated {
            owner?.didFinishCheckCycle(error: error)
        }
    }

    /// 설치 / 나중에 / 건너뛰기 — 배너를 거둘지 여기서 판단한다.
    nonisolated func updater(
        _ updater: SPUUpdater,
        userDidMake choice: SPUUserUpdateChoice,
        forUpdate updateItem: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            owner?.userDidMakeChoice(choice)
        }
    }
}

// MARK: - Sparkle 표준 UI delegate (조용한 알림)

/// 자동 확인이 찾은 업데이트의 **표준 창 노출을 억제**하고, 대신 앱이 popover 배너로 알리게 하는 중계.
///
/// `supportsGentleScheduledUpdateReminders` 가 `true` 여야 Sparkle 이 아래 두 콜백으로
/// *창을 띄울지* 를 우리에게 묻는다. 사용자가 직접 요청한 확인에는 이 경로가 적용되지 않는다 —
/// 그때는 표준 창이 곧바로 뜨는 것이 맞다 (UX-UI *자동 업데이트* §업데이트 창).
@MainActor
private final class UpdateDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    weak var owner: UpdateService?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 예약(자동) 확인으로 찾은 업데이트 — 표준 창을 띄우지 않겠다고 답한다.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    /// 표준 창이 뜨지 않는 경우(`handleShowingUpdate == false`) 알리는 책임은 우리에게 있다 → 배너.
    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        MainActor.assumeIsolated {
            guard !handleShowingUpdate else {
                Logger.update.info("표준 창이 직접 표시 — 배너 생략 (사용자 요청 확인)")
                return
            }
            owner?.presentBanner(for: update)
        }
    }

    // `standardUserDriverDidReceiveUserAttentionForUpdate:` / `standardUserDriverWillFinishUpdateSession`
    // 은 구현하지 않는다. 둘 다 *창이 앞으로 나온 시점* 에도 발화해서, 사용자가 «나중에» 를 고를 기회조차
    // 갖기 전에 배너를 지워버린다(검수 2026-08-02). 배너 해제는 실제 선택을 아는
    // `updater:userDidMakeChoice:forUpdate:state:` 에서만 판단한다.
}
