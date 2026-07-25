// 1·2·3 호출 방식 통합 popover Window — `mode` 분기로 위치/activate/monitor/resetForOpen 차이 처리 (TASK-018)
// 인스턴스 단일화로 모드 간 중복 노출 *물리적* 차단. 기존 Method1/2/3Window 폐기.
import AppKit
import SwiftUI
import OSLog

@MainActor
final class PopoverWindow: NSObject {
    private let panel: KeyablePanel
    private let visualEffectView: NSVisualEffectView
    private let viewModel: ClipsViewModel
    /// TASK-054 fix-1 — `windowWillResize` 안에서 `setClipsPerPage` 직접 호출 위해 약 reference. Composition Root 가 inject.
    private weak var settingsViewModel: SettingsViewModel?
    private let onOpenSettings: @MainActor () -> Void

    /// 현재 표시 중인 mode. nil = hidden. mode 전환 시 hide → showInternal에서 갱신.
    private var currentMode: PopoverInvocationMode?

    private lazy var outsideClickMonitor = OutsideClickMonitor { [weak self] in
        // TASK-071 Phase 4 — global monitor false positive 차단. `nonactivatingPanel + becomesKeyOnlyIfNeeded=true` + Phase 3 fix (safeAreaRegions=[]) 박은 후 titlebar 영역에 시각상 PopoverHeaderView 박힘 → 사용자 헤더 클릭 시 시스템이 titlebar 영역 클릭으로 인식 → panel 활성화 우회 + 외부 앱 활성화 시도 → global monitor (addGlobalMonitorForEvents — *외부 앱* 클릭만 잡음) 가 false positive 발화 → popover hide 회귀.
        // 가드: NSEvent.mouseLocation 이 panel.frame (+ pinSidebarPanel.frame + detailPanel.frame 합집합) 안이면 false positive 로 간주 + hide skip. 진짜 popover 외부 클릭만 hide 발화.
        guard let self else { return }
        let mouse = NSEvent.mouseLocation
        if self.panel.isVisible && self.panel.frame.contains(mouse) { return }
        if self.pinSidebarPanel.isVisible && self.pinSidebarPanel.frame.contains(mouse) { return }
        if self.detailPanel.isVisible && self.detailPanel.frame.contains(mouse) { return }
        self.hide()
    }
    /// TASK-025 — popover 안 mouseDown 잡아 검색바 외부 click 시 NSTextField first responder *복원* (이전 TASK-016 의 *해제* 방향 반대). 방식 1·2만 설치.
    private var localClickMonitor: Any?
    /// TASK-025 — popover 키 라우팅 monitor (NSTextView consume 전 PopoverHotkey 매칭 + Tab consume). 이전 ESC monitor 의 모든 키 라우팅으로 확장. 방식 1·2만 설치.
    private var popoverKeyMonitor: Any?

    /// Pin 사이드바 별도 floating panel — popover 좌측에 분리 노출 (TASK-019 fix). 단일 인스턴스 재사용.
    private let pinSidebarPanel: KeyablePanel
    private let pinSidebarVisualEffect: NSVisualEffectView

    /// 클립 상세 sub-window 별도 floating panel — popover 또는 PinSidebar 좌측에 다중파일 클립 detail 표시 (TASK-027). 단일 인스턴스 재사용.
    private let detailPanel: KeyablePanel
    private let detailVisualEffect: NSVisualEffectView
    /// 마지막 표시 detail 요청 — PinSidebar 사이즈 변경 시 anchor 재계산용 (TASK-027 Phase 5).
    private var lastShownDetailRequest: ClipDetailRequest?

    /// TASK-037 — 디스플레이 환경설정 / visibleClips 변동 시 NSPanel frame 재계산용 NotificationCenter observer 핸들.
    private var displayLayoutObserver: NSObjectProtocol?

    /// TASK-037 fix-9 — 현재 NSHostingView. fittingSize 측정 위해 보관. rebuildHosting 시 갱신.
    private var currentHosting: NSHostingView<AnyView>?

    /// TASK-054 — 사용자가 popover 본체를 드래그로 옮긴 흔적 추적. 또는 *이전 위치 기억하기 ON* 저장 좌표 진입 케이스.
    /// `true` 시 `refreshFrame` 의 method2/3 분기가 *anchor 별 재계산 무시 + 현재 origin 유지 + 화면 밖 clamp* 로 동작 → 사용자 박은 위치 보존.
    /// `false` (default) — anchor 별 origin 재계산. `showInternal` 진입 마다 reset.
    private var panelMovedByUser: Bool = false

    /// TASK-061 — popover 진입 후 첫 refreshFrame 인지 추적. 사용자 요구 정합 — *첫 anchor 진입* 은 기존 anchor 결과 origin (.bottomRight bottom 고정 등) 보존 / *후속 refresh* 는 anchor 무관 top 고정 + bottom 변동.
    /// `showInternal` 진입 시 reset = false. 첫 `_performRefreshFrame` 호출 시 anchor 결과 origin 박은 후 true.
    private var hasAnchoredOnce: Bool = false

    /// detail panel 총 width — 본문(clipDetailWidth) + 꼭지(clipDetailArrowWidth). NSPanel make / setFrame / originX 계산 모두 본 값 사용 (TASK-027 refactor — 3 곳 중복 계산 통합).
    static var clipDetailTotalWidth: CGFloat {
        DesignTokens.WindowSize.clipDetailWidth + DesignTokens.Spacing.clipDetailArrowWidth
    }

    /// detail 메타 라인 (글자수 / 복사 위치) 표시 여부 — Clip extension 단일 진실 소스 호출 (TASK-076 Phase 4 fix).
    /// `ClipDetailPanelView.contentMaxHeight` 와 동일 정책 — PanelView 의 SwiftUI 컴퓨티드와 PopoverWindow 의 NSPanel height 계산이 *동일 정책* 으로 일치 보장.
    /// TASK-039 시점 `hasCopyLocation` → TASK-076 Phase 4 에서 글자수 라인 추가되며 *메타 라인* 일반화 (이름 유지 — 외부 호출 시그니처 호환).
    static func hasCopyLocation(for clip: Clip) -> Bool {
        clip.hasClipDetailMetaLine
    }

    /// TASK-054 — 설정 *기본 오픈 위치* 조회. UserDefaults raw → PopoverAnchor. 잘못된 값 / 미설정 → `.default` (.topRight, TASK-065) fallback.
    /// 매 popover 오픈 시점 호출 — SettingsViewModel 의존 차단 (PopoverWindow 가 SettingsViewModel 직접 참조 X, UserDefaults 단일 진실 소스).
    static func currentDefaultAnchor() -> PopoverAnchor {
        guard let raw = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.popoverDefaultAnchor),
              let anchor = PopoverAnchor(rawValue: raw) else {
            return .default
        }
        return anchor
    }

    /// TASK-084 Phase 4a — `_performRefreshFrame()` origin 계산 분기 추출. 값 기반 순수 함수 — NSPanel state 의존 0, 단위 테스트 진입점.
    /// 세 분기 (panelMovedByUser / anchorFirstEntry / followUp) × visibleFrame clamp + anchor 별 Y 정책 (bottom 고정 / top 고정 / center 고정).
    enum ComputeOriginMode {
        /// 사용자 드래그 / 저장 좌표 진입 — 현재 origin.x 유지 + top 고정 + 화면 밖 clamp.
        case panelMovedByUser
        /// 첫 anchor 진입 (방식 2·3 + !hasAnchoredOnce) — anchor 결과 origin + anchor 별 Y 정책.
        case anchorFirstEntry(anchor: PopoverAnchor, inset: CGFloat)
        /// 후속 refresh (방식 1 첫 진입 포함) — 현재 origin.x 유지 + top 고정 + 화면 밖 clamp.
        case followUp
    }

    /// TASK-084 Phase 4b — `showClipDetailPanel()` geometry 계산 분기 추출. ClipDetailPanel 의 origin / detailH / direction / arrowOffsetY 단일 산출.
    /// 값 기반 순수 함수 — NSPanel state 의존 0, 단위 테스트 진입점. DesignTokens 상수는 *전역 정적* 이라 nonisolated 안전.
    struct ClipDetailGeometry: Equatable {
        let originX: CGFloat
        let originY: CGFloat
        let detailH: CGFloat
        let direction: ClipDetailDirection
        let arrowOffsetY: CGFloat
    }

    /// `showClipDetailPanel()` 의 zone 분기 + anchor frame 결정 + 좌표 변환 + 화면 경계 clamp + arrow offset 계산을 통합한 순수 함수.
    /// 호출자 책임: mode/panel.isVisible/zone-pinSidebar 가드 + provider preferredHeight 조회 + hasCopyLocation 판정 + side effect (mount / setFrame / maskImage / orderFront / lastShownDetailRequest 갱신).
    nonisolated static func computeClipDetailGeometry(
        zone: FocusZone,
        rowFrameInPopoverMidY: CGFloat,
        anchorFrame: NSRect,
        popoverFrame: NSRect,
        pinSidebarFrame: NSRect?,
        screenVisibleFrame: NSRect,
        rawContentHeight: CGFloat,
        hasCopyLocation: Bool
    ) -> ClipDetailGeometry {
        // detail panel height (TASK-039) — Provider raw + 본문 상하 padding + 메타 footer + (해당 시) 복사 위치 라인.
        let vPad = 2 * DesignTokens.Spacing.clipDetailPadding
        let extraH = vPad
            + DesignTokens.Spacing.clipMetaFooterHeight
            + (hasCopyLocation ? DesignTokens.Spacing.clipMetaLocationBlockHeight : 0)
        let contentMaxH = max(DesignTokens.WindowSize.clipDetailMaxHeight - extraH, 0)
        let contentH = min(rawContentHeight, contentMaxH)
        let detailH = contentH + extraH
        // TASK-027 fix — panel 총 width = 본문 + 꼭지. clipDetailTotalWidth 와 동일 산식.
        let totalW = DesignTokens.WindowSize.clipDetailWidth + DesignTokens.Spacing.clipDetailArrowWidth
        let gap = DesignTokens.Spacing.clipDetailGap
        let safe = DesignTokens.Spacing.clipDetailEdgeSafety

        // TASK-055 — 방향 결정.
        // zone == .pin && pinSidebar 가시 시 — 사이드바 *바깥쪽* 강제. 사이드바가 본체 좌측이면 detail 더 좌측 / 사이드바가 본체 우측 fallback 진입 상태면 detail 더 우측.
        // 그 외 (zone == .clip) — `ClipDetailDirection.resolve` 좌측 default + 좌측 막힘 시 우측 fallback.
        let direction: ClipDetailDirection
        if zone == .pin, let pinFrame = pinSidebarFrame {
            direction = (pinFrame.minX < popoverFrame.minX) ? .left : .right
        } else {
            direction = ClipDetailDirection.resolve(
                anchorFrame: anchorFrame,
                totalWidth: totalW,
                gap: gap,
                safe: safe,
                visibleFrame: screenVisibleFrame
            )
        }
        // originX 계산 + 화면 가장자리 클램프 (양쪽 막힘 케이스 안전망).
        var originX = direction.originX(anchorFrame: anchorFrame, totalWidth: totalW, gap: gap)
        originX = max(screenVisibleFrame.minX + safe, min(originX, screenVisibleFrame.maxX - totalW - safe))

        // SwiftUI top-down ↔ NSPanel bottom-up 좌표 변환.
        let rowCenterY_screen = anchorFrame.origin.y + (anchorFrame.height - rowFrameInPopoverMidY)

        // detail panel originY (screen, bottom-up) — 꼭지가 행 center 가리키도록 기본은 panel 중앙에 꼭지.
        var arrowOffsetY = detailH / 2
        var originY = rowCenterY_screen - (detailH - arrowOffsetY)

        // TASK-039 fix — anchor (PinSidebar) height < detailH 케이스 시각 정합. detail bottom = anchor bottom 정렬 + arrowOffsetY 재계산.
        if zone == .pin, pinSidebarFrame != nil, detailH > anchorFrame.height {
            originY = anchorFrame.origin.y
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        }

        // 화면 상/하단 클램프 — 클램프 발생 시 arrowOffsetY 보정으로 꼭지가 행 center 유지.
        let minY = screenVisibleFrame.minY + safe
        let maxY = screenVisibleFrame.maxY - detailH - safe
        if originY < minY {
            originY = minY
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        } else if originY > maxY {
            originY = maxY
            arrowOffsetY = detailH - (rowCenterY_screen - originY)
        }
        // arrowOffsetY 범위 [arrowH/2, detailH - arrowH/2] 가드.
        let arrowH = DesignTokens.Spacing.clipDetailArrowHeight
        arrowOffsetY = max(arrowH / 2, min(detailH - arrowH / 2, arrowOffsetY))

        return ClipDetailGeometry(
            originX: originX,
            originY: originY,
            detailH: detailH,
            direction: direction,
            arrowOffsetY: arrowOffsetY
        )
    }

    nonisolated static func computeOrigin(
        mode: ComputeOriginMode,
        currentFrame: NSRect,
        fittingHeight: CGFloat,
        preservedWidth: CGFloat,
        visibleFrame: NSRect
    ) -> NSPoint {
        let prevTop = currentFrame.origin.y + currentFrame.height
        let prevMidY = currentFrame.origin.y + currentFrame.height / 2
        switch mode {
        case .panelMovedByUser, .followUp:
            // TASK-061 — 사용자 드래그 후 height 변동도 top 고정 (사용자 요구 정합). 기존 `y = panel.frame.origin.y` (= bottom 고정) → `y = prevTop - h` (= top 고정).
            let h = fittingHeight
            var x = currentFrame.origin.x
            var y = prevTop - h
            x = max(visibleFrame.minX, min(x, visibleFrame.maxX - preservedWidth))
            y = max(visibleFrame.minY, min(y, visibleFrame.maxY - h))
            return NSPoint(x: x, y: y)
        case let .anchorFirstEntry(anchor, inset):
            // TASK-061 — 첫 anchor 진입은 기존 anchor 결과 origin 박음 (시각 진입 anchor 정합 보존). anchor 별 Y 정책: bottom/top/center.
            let panelSize = NSSize(width: preservedWidth, height: fittingHeight)
            let o = anchor.origin(panelSize: panelSize, visibleFrame: visibleFrame, inset: inset)
            let newY: CGFloat
            switch anchor {
            case .bottomRight, .bottomLeft:
                newY = o.y                              // bottom 고정
            case .topLeft, .topRight:
                newY = prevTop - fittingHeight          // top 고정 — height 변경 시 origin.y 보정
            case .center:
                newY = prevMidY - fittingHeight / 2     // center 고정
            }
            return NSPoint(x: o.x, y: newY)
        }
    }

    /// TASK-054 — *이전 위치 기억하기* ON 시 저장 좌표 진입. 화면 밖 fallback 시 false 반환 → 호출자가 anchor fallback.
    /// TASK-054 fix-1 — *width 영속* 항상 적용 — 본 헬퍼는 *위치* (origin) 만 다룸. width 복원은 init 시점 PopoverPanel.make 에서 박힘.
    /// 유효성 검증: (a) 토글 ON / (b) 좌표 UserDefaults 박혀있음 / (c) `PopoverPanel.validateSavedFrame` 통과 (좌표 + 현재 panel size 화면 cap).
    /// 성공 시 `panelMovedByUser = true` 박음 — 후속 `refreshFrame` 의 anchor 재계산 무시 + 사용자 위치 보존.
    /// 저장값은 fallback 진입해도 UserDefaults 에서 제거 X (호환 화면 복귀 시 재사용).
    private func applyRememberedOrigin(anchor: PopoverAnchor) -> Bool {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition) else {
            return false
        }
        guard UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverLastPositionX) != nil,
              UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverLastPositionY) != nil else {
            return false
        }
        let x = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.popoverLastPositionX)
        let y = UserDefaults.standard.double(forKey: Constants.UserDefaultsKeys.popoverLastPositionY)
        let origin = NSPoint(x: x, y: y)
        guard let screen = panel.screen ?? NSScreen.main else { return false }
        let visible = screen.visibleFrame
        guard PopoverPanel.validateSavedFrame(origin: origin, size: panel.frame.size, visibleFrame: visible) else {
            Logger.ui.info("popover saved origin invalid (\(x, privacy: .public),\(y, privacy: .public)) — fallback to anchor \(anchor.rawValue, privacy: .public)")
            return false
        }
        panel.setFrameOrigin(origin)
        panelMovedByUser = true
        Logger.ui.info("popover restored saved origin (\(x, privacy: .public),\(y, privacy: .public))")
        return true
    }

    /// TASK-054 — popover hide 시점 영구 좌표 저장. 방식 2·3 + 토글 ON 시에만 박음.
    /// TASK-054 fix-1 — width 도 함께 저장 (단 *위치 영속 토글 무관* 항상). 위치는 토글 ON 시만 유지. 사용자 결정 *width = 작업 환경 선호 / 위치 = 상황 의존* 정합.
    /// 본체 frame.origin + frame.size.width + screen.localizedName (호환 화면 식별) 저장.
    private func saveLastPositionIfNeeded() {
        guard let mode = currentMode, mode == .method1 || mode == .method2 || mode == .method3 else { return }
        // width 는 항상 영속 — 방식 1·2·3 공유 단일 키.
        UserDefaults.standard.set(Double(panel.frame.size.width), forKey: Constants.UserDefaultsKeys.popoverWidth)
        // 위치는 방식 2·3 + 토글 ON 시만 영속.
        guard mode == .method2 || mode == .method3 else { return }
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.popoverRememberLastPosition) else { return }
        let origin = panel.frame.origin
        UserDefaults.standard.set(Double(origin.x), forKey: Constants.UserDefaultsKeys.popoverLastPositionX)
        UserDefaults.standard.set(Double(origin.y), forKey: Constants.UserDefaultsKeys.popoverLastPositionY)
        if let screenId = panel.screen?.localizedName {
            UserDefaults.standard.set(screenId, forKey: Constants.UserDefaultsKeys.popoverLastPositionScreenId)
        }
        Logger.ui.info("popover saved last origin (\(origin.x, privacy: .public),\(origin.y, privacy: .public)) width=\(self.panel.frame.size.width, privacy: .public)")
    }

    init(
        viewModel: ClipsViewModel,
        settingsViewModel: SettingsViewModel? = nil,
        onOpenSettings: @MainActor @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.settingsViewModel = settingsViewModel
        self.onOpenSettings = onOpenSettings
        // TASK-054 fix-1 — popover width 영속. UserDefaults 저장값 우선 + cap clamp + default fallback.
        let savedWidth = (UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.popoverWidth) as? Double)
            .map { CGFloat($0) } ?? DesignTokens.WindowSize.popoverWidth
        let initialWidth = max(Constants.popoverWidthMin, min(Constants.popoverWidthMax, savedWidth))
        let (p, ve) = PopoverPanel.make(
            width: initialWidth,
            height: DesignTokens.WindowSize.popoverHeight
        )
        self.panel = p
        self.visualEffectView = ve
        // TASK-019 — Pin 사이드바 별도 NSPanel. popover 좌측 floating. height 는 PinSidebarView 의 자연 사이즈를 따르되 popover height 상한.
        // TASK-097 — 초기 너비 = UserDefaults 저장값(clamp) 또는 기본 220.
        let (sp, sve) = PopoverPanel.make(
            width: Self.storedPinSidebarWidth(),
            height: DesignTokens.WindowSize.popoverHeight
        )
        self.pinSidebarPanel = sp
        self.pinSidebarVisualEffect = sve

        // TASK-027 — 클립 상세 sub-window 별도 NSPanel. popover (또는 PinSidebar) 좌측 floating. height 는 Provider.preferredHeight 동적 계산.
        // width = clipDetailWidth (본문) + clipDetailArrowWidth (꼭지 외부 튀어나옴 영역). NSVisualEffectView.maskImage 가 panel 자체를 말풍선 모양으로 잘라냄 (TASK-027 fix).
        // TASK-075 — `make` 의 시스템 .titled chrome 이 panel.frame 직사각형 외곽 (본문 + 꼭지 확장 영역 포함) 에 박혀 꼭지가 outline 안쪽에 갇히는 시각 어색 fix. detailPanel 만 borderless 패턴 `makeBubble` 분리. 메인 popover / 핀 사이드바는 `make` 그대로 유지.
        let (dp, dve) = PopoverPanel.makeBubble(
            width: Self.clipDetailTotalWidth,
            height: DesignTokens.WindowSize.clipDetailMaxHeight
        )
        self.detailPanel = dp
        self.detailVisualEffect = dve

        super.init()

        // TASK-054 — NSWindowDelegate 부합. `windowDidMove` 발화 → 사이드바·상세 sub-window 동반 추종.
        panel.delegate = self
        // TASK-097 — Pin 사이드바 패널도 delegate 부합. windowWillResize(너비 clamp + 높이 고정) + windowDidEndLiveResize(너비 영속) 수신.
        pinSidebarPanel.delegate = self

        // ClipsViewModel.pinSidebarOpen 변경 콜백 등록 — true → show / false → hide.
        viewModel.onPinSidebarOpenChange = { [weak self] isOpen in
            guard let self else { return }
            if isOpen {
                self.showPinSidebar()
            } else {
                self.hidePinSidebar()
            }
        }
        // pinnedClips count 변화 콜백 — 사이드바 열려있으면 panel size 재조정.
        viewModel.onPinnedClipsChange = { [weak self] in
            guard let self, self.viewModel.pinSidebarOpen else { return }
            self.resizePinSidebarPanel()
        }
        // TASK-027 — ClipsViewModel.onShowClipDetailChange 콜백 등록. non-nil → showClipDetailPanel / nil → hide.
        viewModel.onShowClipDetailChange = { [weak self] request in
            guard let self else { return }
            if let request {
                self.showClipDetailPanel(request)
            } else {
                self.hideClipDetailPanel()
            }
        }
        // TASK-062 — pinSidebarHoverExit 가드 closure 등록. NSEvent.mouseLocation + 핀 사이드바 frame + 상세 sub-panel frame 합집합 검사 → true (합집합 안, close 차단) / false (합집합 밖, close 진행). 두 panel 모두 isVisible 시만 frame 포함 — invisible panel frame 검사 X.
        viewModel.shouldRetainPinSidebarOnHoverExit = { [weak self] in
            guard let self else { return false }
            let mouse = NSEvent.mouseLocation
            if self.pinSidebarPanel.isVisible && self.pinSidebarPanel.frame.contains(mouse) { return true }
            if self.detailPanel.isVisible && self.detailPanel.frame.contains(mouse) { return true }
            return false
        }

        // TASK-037 — 디스플레이 환경설정 / visibleClips 변동 알림 구독 → NSPanel frame 동적 재계산.
        displayLayoutObserver = NotificationCenter.default.addObserver(
            forName: ClipsViewModel.displayLayoutDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshFrame()
            }
        }

    }

    /// TASK-037 fix-13 → TASK-056 정정: 기존 `DispatchQueue.main.async` 1 tick 대기가 사용자 *한 템포 늦음* 인지 원인 → 동기 호출로 전환.
    /// `_performRefreshFrame` 안 `hosting.layoutSubtreeIfNeeded()` 가 SwiftUI body 강제 재계산 + 별도 `NSHostingController` 인스턴스의 `sizeThatFits(in:)` 가 *현재 state 기반* 정확 측정 → async 박지 않아도 fittingSize 정확.
    private func refreshFrame() {
        guard panel.isVisible else { return }
        _performRefreshFrame()
    }

    private func _performRefreshFrame() {
        guard panel.isVisible, let hosting = currentHosting else { return }
        // TASK-054 fix-1 — 시스템 라이브 resize 중 origin 변경 skip (windowWillResize 와 충돌 차단). size 는 시스템 책임.
        guard !panel.inLiveResize else { return }
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        let fitting = NSSize(width: panel.frame.size.width, height: measuredFittingHeight(width: panel.frame.size.width, hosting: hosting))

        // TASK-054 fix-2 — width 는 사용자 박은 값 (또는 default `popoverWidth=380`) 보존. fitting.width 는 SwiftUI body `maxWidth: .infinity` 박힌 후 *content intrinsic 최소값* 반환이라 NSPanel width 가 축소됨. 시스템 표준 NSWindow resize 가 width 자체 변경 책임. origin 계산도 본 width 기준.
        let preservedWidth = panel.frame.size.width
        // TASK-084 Phase 4a — origin 계산 분기 helper 추출 (`computeOrigin`). 세 분기 (panelMovedByUser / anchorFirstEntry / followUp) × screen visible frame clamp.
        // TASK-071 정합 — 방식 1 (button anchor) 진입 시 anchor 호출 회피. showInternal 의 positionBelow 가 박은 panel.frame.origin 그대로 보존 + top 고정 (`.followUp` 분기).
        let newOrigin: NSPoint
        if let visible = (panel.screen ?? NSScreen.main)?.visibleFrame {
            if panelMovedByUser {
                newOrigin = Self.computeOrigin(
                    mode: .panelMovedByUser,
                    currentFrame: panel.frame,
                    fittingHeight: fitting.height,
                    preservedWidth: preservedWidth,
                    visibleFrame: visible
                )
            } else if !hasAnchoredOnce && currentMode != .method1 {
                newOrigin = Self.computeOrigin(
                    mode: .anchorFirstEntry(
                        anchor: Self.currentDefaultAnchor(),
                        inset: DesignTokens.WindowSize.popoverInsetBottom
                    ),
                    currentFrame: panel.frame,
                    fittingHeight: fitting.height,
                    preservedWidth: preservedWidth,
                    visibleFrame: visible
                )
                hasAnchoredOnce = true
            } else {
                newOrigin = Self.computeOrigin(
                    mode: .followUp,
                    currentFrame: panel.frame,
                    fittingHeight: fitting.height,
                    preservedWidth: preservedWidth,
                    visibleFrame: visible
                )
                hasAnchoredOnce = true
            }
        } else {
            // screen 미발견 fallback — origin 유지, hasAnchoredOnce 미변경. setFrame 자체는 진행 (동일 frame 박힘 시 아래 동등 비교에서 skip).
            newOrigin = panel.frame.origin
        }

        let newFrame = NSRect(x: newOrigin.x, y: newOrigin.y, width: preservedWidth, height: fitting.height)
        // TASK-061 — 동일 frame setFrame 호출 skip. setFrame → windowDidResize 발화 → refreshFrame 재호출 → loop / measurement race 차단.
        if newFrame == panel.frame {
            return
        }
        // animate:false + display:false → displayIfNeeded — SwiftUI body 재계산 + NSPanel frame transition 충돌 차단.
        panel.setFrame(newFrame, display: false, animate: false)
        panel.displayIfNeeded()
        if pinSidebarPanel.isVisible {
            resizePinSidebarPanel()
        }
        // TASK-044 — refreshFrame async dispatch 종료 직후 first responder 복원 가드. `hosting.invalidateIntrinsicContentSize()` + `layoutSubtreeIfNeeded()` 가 SwiftUI body 재계산 시 NSTextField first responder 상태에 영향 가능 — `trySetSearchFirstResponder` 가 이미 textField 면 no-op, 아니면 복원.
        if let mode = currentMode {
            attemptSearchFirstResponder(mode: mode, reason: "refreshFrame")
        }
        Logger.ui.info("PopoverWindow.refreshFrame — fitting=\(Int(fitting.width), privacy: .public)x\(Int(fitting.height), privacy: .public)")
    }

    /// TASK-056 — SwiftUI body 의 *constrained* fitting height 측정. `hosting.fittingSize` 는 unconstrained proposal (width=∞) 로 측정되어 `FlowLayout` 등 wrap 가능 자식이 1줄 intrinsic 으로 박혀 실제 panel.width 좁을 때 body bottom clipping 발생. 별도 `NSHostingController` 인스턴스 + `sizeThatFits(in:)` 로 panel.width 제약 박은 정확한 측정. (두 호출처 공통 — `_performRefreshFrame` / `windowWillResize`.)
    private func measuredFittingHeight(width: CGFloat, hosting: NSHostingView<AnyView>) -> CGFloat {
        let controller = NSHostingController(rootView: hosting.rootView)
        return controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
    }

    /// TASK-055 — 핀 사이드바 origin + 방향 산출 헬퍼. `showPinSidebar` / `resizePinSidebarPanel` 두 호출처 공통 흐름.
    /// 본체 popover screen 의 visibleFrame 기준 (`panel.screen ?? NSScreen.main`) 으로 `ClipDetailDirection.resolve` 호출 + originX 계산. 사이드바 자체 screen 참조 X (fix-2 정합 — 사이드바가 이전 위치 잔존 screen 반환 차단).
    private func computePinSidebarOrigin(popoverFrame: NSRect, sidebarWidth: CGFloat, gap: CGFloat) -> (originX: CGFloat, direction: ClipDetailDirection) {
        let visibleFrame = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let direction = ClipDetailDirection.resolve(
            anchorFrame: popoverFrame,
            totalWidth: sidebarWidth,
            gap: gap,
            safe: DesignTokens.Spacing.clipDetailEdgeSafety,
            visibleFrame: visibleFrame
        )
        let originX = direction.originX(anchorFrame: popoverFrame, totalWidth: sidebarWidth, gap: gap)
        return (originX, direction)
    }

    /// TASK-019 fix 2차 — pinnedClips count 변화 시 panel size 재조정 (bottom-aligned 유지).
    /// TASK-027 — Pin 사이드바 사이즈 변동 후 detail panel 활성이면 anchor 재계산 (200ms debounce 없이 즉시).
    /// TASK-055 — 사이드바 좌/우 fallback. `computePinSidebarOrigin` 헬퍼로 단일화 (showPinSidebar 정합).
    private func resizePinSidebarPanel() {
        guard pinSidebarPanel.isVisible else { return }
        let popoverFrame = panel.frame
        let gap = DesignTokens.Spacing.pinSidebarGap
        let sidebarWidth = Self.storedPinSidebarWidth()  // TASK-097 — 저장 너비(clamp) 사용. 220 하드코딩 clobber 제거.
        let sidebarHeight = computePinSidebarHeight()
        let (originX, direction) = computePinSidebarOrigin(popoverFrame: popoverFrame, sidebarWidth: sidebarWidth, gap: gap)
        let originY = popoverFrame.origin.y  // bottom-aligned
        pinSidebarPanel.setFrame(
            NSRect(x: originX, y: originY, width: sidebarWidth, height: sidebarHeight),
            display: true,
            animate: false
        )
        Logger.ui.debug("Pin sidebar resize — direction=\(direction.rawValue, privacy: .public) originX=\(originX, privacy: .public)")
        // TASK-027 — detail panel 활성이고 zone == .pin 이면 PinSidebar 새 anchor 로 setFrame 재계산.
        if let last = lastShownDetailRequest, last.zone == .pin, detailPanel.isVisible {
            showClipDetailPanel(last)
        }
    }

    var isVisible: Bool { panel.isVisible }

    /// 방식 1 — 메뉴바 button 아래 anchor.
    func show(below button: NSStatusBarButton) {
        // TASK-058 fix-4 — 유지 모드 ON + 이미 visible 시 *close 차단* + *panel key 활성화 수행*. 트레이 재클릭 = (a) 일반 모드 toggle close 의도 / (b) 잠금 모드 *외부 앱 작업 후 popover 복귀 활성화* 의도 — 후자 진입점 보장 위해 panel.makeKeyAndOrderFront 호출. close 자체는 잠금 정합으로 차단 (showInternal skip).
        if panel.isVisible && viewModel.keepOpenAfterAction {
            Logger.ui.debug("show(below:) — keepOpenAfterAction ON + already visible → activate-only (TASK-058 fix-4)")
            panel.makeKeyAndOrderFront(nil)
            return
        }
        showInternal(mode: .method1, below: button)
    }

    /// 방식 2·3 — 활성 화면 우하단.
    /// - Precondition: `mode != .method1`. 방식 1은 `show(below:)` 사용.
    func show(mode: PopoverInvocationMode) {
        precondition(mode != .method1, "방식 1은 show(below:) 사용. button anchor 필수.")
        // TASK-058 fix-4 — 유지 모드 ON + 이미 visible 시 *close 차단* + *panel key 활성화 수행*. ⌘⇧V 재호출 = (a) 일반 모드 toggle close 의도 / (b) 잠금 모드 *외부 앱에서 텍스트 입력 후 popover 단축키로 활성화* 의도 — 후자 진입점 보장 위해 panel.makeKeyAndOrderFront 호출. close 자체는 잠금 정합으로 차단 (showInternal skip).
        if panel.isVisible && viewModel.keepOpenAfterAction {
            Logger.ui.debug("show(mode:) — keepOpenAfterAction ON + already visible → activate-only (TASK-058 fix-4)")
            panel.makeKeyAndOrderFront(nil)
            return
        }
        showInternal(mode: mode, below: nil)
    }

    /// - Parameter force: true 시 유지 모드 가드 우회 + 자물쇠 상태 유지 (앱 세션 영속). ESC 키 진입점 (TASK-058 fix-6) 에서 `true` 박아 close 만 수행 / 자물쇠 토글 상태는 유지. 외부 클릭 / 트레이 재클릭 / paste·copy 후 hide 등 *간접 close* 진입점은 default `false` — 잠금 ON 시 가드 차단.
    func hide(force: Bool = false) {
        guard let mode = currentMode else {
            // 이미 hidden 상태에서 hide() 호출 — 멱등 안전 (⌘ keyUp 등 외부 트리거 멱등).
            return
        }
        // TASK-058 — 유지 모드 ON 시 *간접 close* 진입점 차단 (완전 잠금 정책 — FEATURES F-011). force=true (ESC 진입) 면 가드 우회 → close 수행하되 자물쇠 상태는 유지 (앱 세션 영속).
        if !force && viewModel.keepOpenAfterAction {
            Logger.ui.debug("hide() blocked — keepOpenAfterAction ON (TASK-058) mode=\(String(describing: mode), privacy: .public)")
            return
        }
        // 방식 1·2 — monitor 정리 (method3 보류는 monitor 미설치).
        if mode != .method3 {
            outsideClickMonitor.remove()
            removeLocalClickMonitor()
            removePopoverKeyMonitor()
        }
        // TASK-027 — Detail sub-window 동반 닫음.
        hideClipDetailPanel()
        // Pin 사이드바도 동반 닫음 (popover 닫히면 사이드바 단독 노출 의미 없음).
        if viewModel.pinSidebarOpen {
            viewModel.collapsePinSidebar()  // didSet → hidePinSidebar()
        } else {
            hidePinSidebar()  // 안전망 — pinSidebarOpen=false 인데 패널만 떠 있는 비정상 상태 정리.
        }
        // TASK-054 — orderOut 직전 영구 좌표 + width 저장 (width 는 항상 / origin 은 방식 2·3 + 토글 ON 시).
        saveLastPositionIfNeeded()
        panel.orderOut(nil)
        // TASK-054 — background 이동 비활성 (안전망 — 다음 showInternal 까지 보호).
        panel.isMovableByWindowBackground = false
        // TASK-058 fix-6 — 유지 모드 *앱 세션 영속*. ESC close (force=true) 흐름이어도 자물쇠 상태 유지 → 다음 popover 진입 시 마지막 자물쇠 상태 복원. 앱 quit 시 viewModel 메모리 회수로 default false 자연 복귀. 명시적 잠금 해제 진입점은 *자물쇠 OFF 클릭* 단일.
        Logger.ui.info("PopoverWindow hidden — mode=\(String(describing: mode), privacy: .public) force=\(force, privacy: .public)")
        currentMode = nil
    }

    // MARK: - Pin 사이드바 별도 패널 (TASK-019 fix)

    private func showPinSidebar() {
        // popover 좌측 외부 — popover.origin.x - gap - sidebar.width. y는 popover.origin.y (bottom-aligned).
        guard panel.isVisible, let mode = currentMode else {
            Logger.ui.warning("showPinSidebar called while popover hidden — skip")
            return
        }
        // hosting rebuild — 매 show마다 fresh SwiftUI tree (pinnedClips 변화 반영). mode + handleClipPaste 전달.
        _ = PopoverPanel.mount(
            PinSidebarView(
                viewModel: viewModel,
                mode: mode,
                handleClipPaste: { [weak self] idx, zone in
                    await self?.handleClipPaste(at: idx, zone: zone)
                }
            ),
            in: pinSidebarVisualEffect
        )

        let popoverFrame = panel.frame
        let gap = DesignTokens.Spacing.pinSidebarGap
        let sidebarWidth = Self.storedPinSidebarWidth()  // TASK-097 — 저장 너비(clamp) 사용. 220 하드코딩 clobber 제거.
        let sidebarHeight = computePinSidebarHeight()
        // TASK-055 — 좌/우 fallback + 본체 popover screen 기준 visibleFrame 흐름은 computePinSidebarOrigin 헬퍼 단일화.
        let (originX, direction) = computePinSidebarOrigin(popoverFrame: popoverFrame, sidebarWidth: sidebarWidth, gap: gap)
        // bottom-aligned — popover 바닥과 사이드바 바닥 일치.
        let originY = popoverFrame.origin.y
        // TASK-019 fix 3차 — display:true + animate:false 박아 panel size 즉시 redraw (B6 — 첫 show 옛 size 잔존 차단).
        pinSidebarPanel.setFrame(
            NSRect(x: originX, y: originY, width: sidebarWidth, height: sidebarHeight),
            display: true,
            animate: false
        )
        pinSidebarPanel.orderFrontRegardless()
        Logger.ui.info("Pin sidebar panel shown — direction=\(direction.rawValue, privacy: .public) origin=(\(originX, privacy: .public),\(originY, privacy: .public)) h=\(sidebarHeight, privacy: .public)")
    }

    /// TASK-019 / TASK-048 — Pin 사이드바 동적 height 계산. pinnedClips count 기반 + 본체 popoverHeight 미만 상한.
    /// 모든 상수는 `DesignTokens.Spacing` 으로 분리 (`pinSidebarHeaderHeight` / `pinSidebarHeightBottomMargin`).
    /// 식: `header + rows*rowMinHeight + (rows-1)*rowGap + pinSidebarPadding*2`. `LazyVStack(spacing: rowGap)` 이 (count-1) gaps 만 박는 실제 레이아웃 정합.
    /// maxPinnedClips=10 하드 캡이라 10 pins 가 ScrollView 진입 없이 정지 상태 fit. 11+ 케이스 발생 X 이나 식 자체 정확성 가드용 clamp 분기 보존.
    private func computePinSidebarHeight() -> CGFloat {
        Self.computePinSidebarHeight(pinnedCount: viewModel.pinnedClips.count)
    }

    /// pure helper — 테스트 진입점. count 만 받아 동일 식 반환.
    static func computePinSidebarHeight(pinnedCount: Int) -> CGFloat {
        let count = max(1, pinnedCount)
        let rowsBlock = CGFloat(count) * DesignTokens.Spacing.rowMinHeight
            + CGFloat(max(0, count - 1)) * DesignTokens.Spacing.rowGap
        let outerPad = DesignTokens.Spacing.pinSidebarPadding * 2
        let contentH = DesignTokens.Spacing.pinSidebarHeaderHeight + rowsBlock + outerPad
        let upperBound = DesignTokens.WindowSize.popoverHeight - DesignTokens.Spacing.pinSidebarHeightBottomMargin
        return min(contentH, upperBound)
    }

    // MARK: - Pin 사이드바 너비 리사이즈 (TASK-097)

    /// TASK-097 — Pin 사이드바 너비 clamp [pinSidebarWidthMin, pinSidebarWidthMax]. pure helper (테스트 진입점).
    static func clampPinSidebarWidth(_ width: CGFloat) -> CGFloat {
        max(Constants.pinSidebarWidthMin, min(Constants.pinSidebarWidthMax, width))
    }

    /// TASK-097 — 저장 raw(Double?) → 표시 너비. 저장값 있으면 clamp, 없으면 기본(pinSidebarWidth=220). pure helper (UserDefaults 미의존 — 테스트 진입점).
    static func resolveStoredPinSidebarWidth(stored: Double?) -> CGFloat {
        guard let stored else { return DesignTokens.WindowSize.pinSidebarWidth }
        return clampPinSidebarWidth(CGFloat(stored))
    }

    /// TASK-097 — UserDefaults 조회 wrapper. pinSidebarPanel make / show / resize 공통 진입점. 220 하드코딩 대체.
    static func storedPinSidebarWidth() -> CGFloat {
        let stored = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.pinSidebarWidth) as? Double
        return resolveStoredPinSidebarWidth(stored: stored)
    }

    /// TASK-097 — 사이드바 라이브 리사이즈 제안 크기 해석: 너비만 clamp, 높이는 현재값 고정(높이 변경 거부). pure helper (테스트 진입점).
    static func resolvePinSidebarResize(proposedWidth: CGFloat, currentHeight: CGFloat) -> NSSize {
        NSSize(width: clampPinSidebarWidth(proposedWidth), height: currentHeight)
    }

    private func hidePinSidebar() {
        if pinSidebarPanel.isVisible {
            pinSidebarPanel.orderOut(nil)
            Logger.ui.info("Pin sidebar panel hidden")
        }
    }

    // MARK: - 클립 상세 sub-window (TASK-027)

    /// `ClipsViewModel.onShowClipDetailChange` 콜백 진입점 (non-nil 케이스). zone 분기 anchor + 화면 좌표 변환 + 클램프 + 꼭지 Y 보정.
    /// FEATURES §3-8 *위치 + 좌표 변환* 정합.
    private func showClipDetailPanel(_ request: ClipDetailRequest) {
        // method3 (⌘ hold) 보류 가드 — detail sub-window 진입 X.
        guard let mode = currentMode, mode != .method3 else {
            hideClipDetailPanel()
            return
        }
        guard panel.isVisible else {
            hideClipDetailPanel()
            return
        }
        // TASK-039 — zone/PinSidebar 정합 가드. zone == .pin 인데 PinSidebar 비가시 시 emit 거부 (잘못된 anchor=popover 박힘 차단, race fix).
        if request.zone == .pin && !pinSidebarPanel.isVisible {
            hideClipDetailPanel()
            return
        }
        // anchor 결정 — zone == .pin && pinSidebar 가시 시 pinSidebar 좌측, 그 외 popover 좌측.
        let anchorFrame: NSRect
        if request.zone == .pin && pinSidebarPanel.isVisible {
            anchorFrame = pinSidebarPanel.frame
        } else {
            anchorFrame = panel.frame
        }
        // detail panel geometry (TASK-039 / TASK-055 / TASK-027) — height / direction / origin / arrowOffsetY 계산.
        // TASK-084 Phase 4b — geometry 계산 helper 추출 (`computeClipDetailGeometry`). 값 기반 순수 함수 단일 산출.
        let provider = ClipDetailRegistry.provider(for: request.clip)
        let rawContentH = provider?.preferredHeight(for: request.clip) ?? DesignTokens.WindowSize.clipDetailMaxHeight
        let hasLocation = Self.hasCopyLocation(for: request.clip)
        let geometry = Self.computeClipDetailGeometry(
            zone: request.zone,
            rowFrameInPopoverMidY: request.rowFrameInPopover.midY,
            anchorFrame: anchorFrame,
            popoverFrame: panel.frame,
            pinSidebarFrame: pinSidebarPanel.isVisible ? pinSidebarPanel.frame : nil,
            screenVisibleFrame: panel.screen?.visibleFrame ?? .zero,
            rawContentHeight: rawContentH,
            hasCopyLocation: hasLocation
        )
        let originX = geometry.originX
        let originY = geometry.originY
        let detailH = geometry.detailH
        let direction = geometry.direction
        let arrowOffsetY = geometry.arrowOffsetY
        let totalW = Self.clipDetailTotalWidth

        // hosting rebuild — 매 show 마다 fresh SwiftUI tree (clip 변화 반영).
        _ = PopoverPanel.mount(
            ClipDetailPanelView(
                clip: request.clip,
                onFileTap: { [weak self] url in
                    self?.handleFileTap(url)
                },
                searchQuery: viewModel.searchQuery,
                direction: direction
            ),
            in: detailVisualEffect
        )
        detailPanel.setFrame(
            NSRect(x: originX, y: originY, width: totalW, height: detailH),
            display: true,
            animate: false
        )
        // TASK-027 fix / TASK-055 — NSVisualEffectView.maskImage 박아 panel 자체를 말풍선 모양으로 잘라냄. direction 분기로 좌/우 flip.
        detailVisualEffect.maskImage = makeBubbleMaskImage(detailH: detailH, arrowOffsetY: arrowOffsetY, direction: direction)
        detailPanel.orderFrontRegardless()
        lastShownDetailRequest = request
        Logger.ui.info("ClipDetailPanel shown — clipId=\(request.clip.id.uuidString, privacy: .public) zone=\(String(describing: request.zone), privacy: .public) direction=\(direction.rawValue, privacy: .public) origin=(\(originX, privacy: .public),\(originY, privacy: .public)) totalW=\(totalW, privacy: .public) h=\(detailH, privacy: .public) arrowY=\(arrowOffsetY, privacy: .public)")
    }

    /// TASK-027 fix / TASK-055 — 말풍선 mask 이미지. `direction == .left` 시 본문 좌측 + 꼭지 우측 / `direction == .right` 시 본문 우측 + 꼭지 좌측 (flip). NSVisualEffectView.maskImage 로 박아 panel 자체가 말풍선 모양으로 잘림.
    /// `arrowOffsetY` 는 SwiftUI top-down 좌표 (panel top 기준 Y). NSImage flipped:false 는 bottom-up 좌표라 변환.
    private func makeBubbleMaskImage(detailH: CGFloat, arrowOffsetY: CGFloat, direction: ClipDetailDirection) -> NSImage {
        let contentW = DesignTokens.WindowSize.clipDetailWidth
        let arrowW = DesignTokens.Spacing.clipDetailArrowWidth
        let arrowH = DesignTokens.Spacing.clipDetailArrowHeight
        let totalW = Self.clipDetailTotalWidth
        let cornerR = DesignTokens.Radius.popoverOuter
        let size = NSSize(width: totalW, height: detailH)

        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            // 본문 직사각형 — direction 분기.
            // .left : 본문 좌측 [0, contentW] / 꼭지 우측 [contentW, contentW + arrowW]
            // .right: 꼭지 좌측 [0, arrowW] / 본문 우측 [arrowW, arrowW + contentW]
            let bodyOriginX: CGFloat = (direction == .left) ? 0 : arrowW
            let arrowBaseX: CGFloat = (direction == .left) ? contentW : arrowW
            let arrowTipX: CGFloat = (direction == .left) ? contentW + arrowW : 0
            let bodyRect = NSRect(x: bodyOriginX, y: 0, width: contentW, height: detailH)
            path.append(NSBezierPath(roundedRect: bodyRect, xRadius: cornerR, yRadius: cornerR))

            // 꼭지 삼각형 — arrowOffsetY 는 SwiftUI top-down. NSImage bottom-up 으로 변환.
            let arrowY_bottomUp = detailH - arrowOffsetY
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: arrowBaseX, y: arrowY_bottomUp - arrowH / 2))
            arrow.line(to: NSPoint(x: arrowTipX, y: arrowY_bottomUp))
            arrow.line(to: NSPoint(x: arrowBaseX, y: arrowY_bottomUp + arrowH / 2))
            arrow.close()
            path.append(arrow)

            NSColor.black.setFill()
            path.fill()
            return true
        }
        // maskImage 는 capInsets 가 stretching 영역 결정. 기본값 (.zero) 은 stretch X — panel size 변동 시 mask redraw 필요.
        image.capInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        image.resizingMode = .stretch
        return image
    }

    private func hideClipDetailPanel() {
        lastShownDetailRequest = nil
        if detailPanel.isVisible {
            detailPanel.orderOut(nil)
            Logger.ui.info("ClipDetailPanel hidden")
        }
    }

    /// 파일 행 클릭 → Finder reveal + popover dismiss. detailPanel 도 동반 hide (PopoverWindow.hide 안에서 처리).
    private func handleFileTap(_ url: URL) {
        Logger.ui.info("ClipDetailPanel handleFileTap → \(url.path, privacy: .public)")
        NSWorkspace.shared.activateFileViewerSelecting([url])
        hide()
    }

    // MARK: - 내부 표시 흐름

    private func showInternal(mode: PopoverInvocationMode, below button: NSStatusBarButton?) {
        // 다른 mode가 이미 떠 있으면 먼저 hide (모드 간 전환 — "마지막 호출 우선" 룰).
        if currentMode != nil {
            hide()
        }

        currentMode = mode
        // TASK-054 — 사용자 드래그 흔적 리셋. applyRememberedOrigin 또는 본체 드래그 진입 시 다시 true.
        panelMovedByUser = false
        // TASK-061 — 새 popover 진입 — 첫 refreshFrame 가 anchor 결과 origin 박도록 reset. 후속 refresh 는 top 고정.
        hasAnchoredOnce = false
        // TASK-071 — isMovableByWindowBackground mode 가드 제거 + 매 진입 시 true 박음. hide() 의 `false` 안전망 라인이 panel 인스턴스 재사용 (showInternal 별 panel 재생성 X) 흐름에서 다음 show 진입 시 false 잔존 → 본체 드래그 차단 회귀 차단.
        panel.isMovableByWindowBackground = true

        // 위치 — 방식 1만 메뉴바 anchor / 방식 2·3은 환경설정 anchor 5종 (TASK-054).
        if let button {
            // TASK-071 — 방식 1 진입 anchor 만 설정. arrow tail offset 반환값 폐기 (시각 잔존 X — HistoryPopover.arrowTail 미호출).
            PopoverPanel.positionBelow(panel: panel, button: button)
        } else {
            // TASK-054 — 방식 2·3 진입 위치:
            // (a) 이전 위치 기억하기 ON + 저장 좌표 유효 → 저장 좌표 진입 (Phase 4 에서 채움).
            // (b) 그 외 → 환경설정 기본 anchor 5종 분기.
            let anchor = Self.currentDefaultAnchor()
            if !applyRememberedOrigin(anchor: anchor) {
                PopoverPanel.positionAtAnchor(panel, anchor: anchor)
            }
        }

        // resetForOpen — 방식 1·2만 (method3 보류는 ⌘ hold 중 매 재진입마다 reset하면 검색 상태 등 끊김 — 기존 동작 보존).
        if mode != .method3 {
            viewModel.resetForOpen()
        }

        // hosting rebuild — 매 show마다 새 SwiftUI tree 박음 (mode 인자 변경 반영).
        rebuildHosting(mode: mode)

        // TASK-044 — SwiftUI NSHostingView 의 lazy layout 강제 동기화. rebuildHosting 직후 NSTextField subview tree 가 박혀있도록 보장 → 직후 호출되는 `findFirstTextField` 가 nil 반환 회귀 차단.
        visualEffectView.layoutSubtreeIfNeeded()

        // TASK-020 — NSApp.activate 호출 제거 (nonactivatingPanel 본질 보존). stash app이 active되지 않으므로 외부 앱이 frontmost 유지 + first responder 보존 + cursor 깜빡임 유지. paste 시점에 CGEvent ⌘V가 외부 앱의 마지막 cursor 위치에 정확히 도달.
        panel.orderFrontRegardless()
        panel.makeKey()

        // TASK-044 — first responder 진입을 헬퍼로 위임. 동기 1회 + async retry 1회. method3 보류는 검색바 isEnabled=false 라 진입 X — 헬퍼 내부에서 가드.
        attemptSearchFirstResponder(mode: mode, reason: "showInternal")

        // monitor 설치 — 방식 1·2만. method3 (보류) 는 ⌘ keyUp 으로만 닫힘.
        if mode != .method3 {
            outsideClickMonitor.install()
            installLocalClickMonitor()
            installPopoverKeyMonitor(mode: mode)
        }

        // 키 이벤트 핸들러 — 모든 mode 설치.
        installKeyDownHandler(mode: mode)

        // TASK-037 — 디스플레이 환경설정 + visibleClips.count 기반 NSPanel frame 동적 갱신 (open 시점 1회).
        refreshFrame()

        Logger.ui.info("PopoverWindow shown — mode=\(String(describing: mode), privacy: .public)")
    }

    private func installKeyDownHandler(mode: PopoverInvocationMode) {
        PopoverPanel.installKeyDownHandler(
            panel: panel,
            viewModel: viewModel,
            mode: mode,
            onDismiss: { [weak self] in self?.hide(force: true) },
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            },
            handleClipCopy: { [weak self] idx, zone in
                await self?.handleClipCopy(at: idx, zone: zone)
            }
        )
    }

    /// TASK-044 — popover open / refreshFrame 후 NSTextField first responder 진입 헬퍼. 동기 1회 + async retry 1회 안전망.
    /// 사유: TASK-025 의 `panel.makeFirstResponder(textField)` 가 SwiftUI NSHostingView 의 lazy layout 시점 이슈로 nil/false 반환 회귀 — 동기 호출이 실패하면 next runloop tick 에서 재시도. 재시도도 실패하면 panel 자체 fallback + warning.
    /// method3 (⌘ hold 보류) 은 검색바 isEnabled=false 라 진입 X — 가드.
    /// `reason` 은 호출 site 식별용 로그 라벨 (showInternal / refreshFrame).
    private func attemptSearchFirstResponder(mode: PopoverInvocationMode, reason: String) {
        guard mode != .method3 else { return }
        if trySetSearchFirstResponder(reason: "\(reason)/sync") {
            return
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.trySetSearchFirstResponder(reason: "\(reason)/async-retry") {
                    return
                }
                Logger.ui.warning("attemptSearchFirstResponder failed after retry — fallback to panel first responder (TASK-044, reason=\(reason, privacy: .public))")
                self.panel.makeFirstResponder(self.panel)
            }
        }
    }

    /// TASK-044 — 1회 진입 시도. 이미 NSTextField 또는 field editor 가 first responder 면 true (no-op). 아니면 `findFirstTextField` 탐색 후 `makeFirstResponder(textField)` 호출 결과 반환.
    @discardableResult
    private func trySetSearchFirstResponder(reason: String) -> Bool {
        guard let textField = PopoverPanel.findFirstTextField(in: panel.contentView) else {
            Logger.ui.debug("trySetSearchFirstResponder: findFirstTextField nil (TASK-044, reason=\(reason, privacy: .public))")
            return false
        }
        if panel.firstResponder === textField || panel.firstResponder === textField.currentEditor() {
            Logger.ui.debug("trySetSearchFirstResponder: already first responder (TASK-044, reason=\(reason, privacy: .public))")
            return true
        }
        let ok = panel.makeFirstResponder(textField)
        Logger.ui.debug("trySetSearchFirstResponder: makeFirstResponder=\(ok, privacy: .public) (TASK-044, reason=\(reason, privacy: .public))")
        return ok
    }

    private func installLocalClickMonitor() {
        removeLocalClickMonitor()
        // TASK-025 — 외부 click 시 NSTextField first responder *복원* 방향.
        localClickMonitor = PopoverPanel.installSearchFirstResponderRestoreMonitor(panel: panel)
    }

    private func removeLocalClickMonitor() {
        if let m = localClickMonitor {
            NSEvent.removeMonitor(m)
            localClickMonitor = nil
        }
    }

    /// TASK-025 — popover 키 라우팅 monitor (이전 escapeKeyMonitor 의 superset).
    private func installPopoverKeyMonitor(mode: PopoverInvocationMode) {
        removePopoverKeyMonitor()
        popoverKeyMonitor = PopoverPanel.installPopoverKeyEventMonitor(
            panel: panel,
            viewModel: viewModel,
            mode: mode,
            onDismiss: { [weak self] in self?.hide(force: true) },
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            },
            handleClipCopy: { [weak self] idx, zone in
                await self?.handleClipCopy(at: idx, zone: zone)
            }
        )
    }

    private func removePopoverKeyMonitor() {
        if let m = popoverKeyMonitor {
            NSEvent.removeMonitor(m)
            popoverKeyMonitor = nil
        }
    }

    /// 클립 paste 흐름 — PopoverPanel.performPasteFlow 헬퍼로 위임.
    /// TASK-028 — `zone` 명시 파라미터화. 호출 site (HistoryPopover 본체 행 / PinSidebarView 핀 행 / dispatch ⌘V) 가 zone snapshot 박아 전달.
    private func handleClipPaste(at idx: Int, zone: FocusZone) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performPasteFlow(
            viewModel: viewModel,
            idx: idx,
            zone: zone,
            sourceLabel: label,
            hide: { [weak self] in self?.hide() }
        )
    }

    /// TASK-024 — 클립 copy 흐름 (⌘+C 단축키). PopoverPanel.performCopyFlow 헬퍼로 위임. performPasteFlow 와 동일 패턴 (mode 만 `.copyBack` 강제).
    /// TASK-028 — `zone` 명시 파라미터화.
    private func handleClipCopy(at idx: Int, zone: FocusZone) async {
        let label = currentMode.map { "PopoverWindow(\(String(describing: $0)))" } ?? "PopoverWindow"
        await PopoverPanel.performCopyFlow(
            viewModel: viewModel,
            idx: idx,
            zone: zone,
            sourceLabel: label,
            hide: { [weak self] in self?.hide() }
        )
    }

    private func rebuildHosting(mode: PopoverInvocationMode) {
        // TASK-071 — anchorOffsetX 인자 제거 (방식 1·2 통일 정합). HistoryPopover.anchorOffsetX 는 arrow tail 시각 단서용이었으나 미호출 dead. default nil 자연 정합.
        let view = HistoryPopover(
            viewModel: viewModel,
            mode: mode,
            onOpenSettings: onOpenSettings,
            onDismiss: { [weak self] in self?.hide(force: true) },
            handleClipPaste: { [weak self] idx, zone in
                await self?.handleClipPaste(at: idx, zone: zone)
            }
        )
        // TASK-037 fix-9 — hosting 보관 (fittingSize 측정용).
        self.currentHosting = PopoverPanel.mount(view, in: visualEffectView)
    }
}

// MARK: - NSWindowDelegate (TASK-054)

extension PopoverWindow: NSWindowDelegate {
    /// TASK-054 — popover 본체 frame 이동 시 사이드바·상세 sub-window 동반 추종 + `panelMovedByUser` 박음.
    /// 발화 트리거: `panel.isMovableByWindowBackground` 자동 드래그 / 시스템 표준 NSWindow resize / 외부 setFrameOrigin 호출 모두 포함.
    /// TASK-071 — mode 가드 제거 (방식 1·2·3 모두 본체 이동 + 사이드바 동반 추종 활성). currentMode 존재만 가드 안전망.
    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        guard currentMode != nil else { return }
        panelMovedByUser = true
        if pinSidebarPanel.isVisible {
            resizePinSidebarPanel()
        }
        if let last = lastShownDetailRequest, detailPanel.isVisible {
            showClipDetailPanel(last)
        }
    }

    /// TASK-054 fix-1 — 시스템 표준 NSWindow resize 흐름 hijack.
    /// 시스템이 사용자 드래그로 *제안한 frameSize* 받아 *width clamp + height 1행 snap* 반환.
    /// height snap 단위 = `rowMinHeight + rowGap = 46pt`. width clamp = `[popoverWidthMin=280, popoverWidthMax=600]`.
    /// height 변경이 1행 임계 도달 시 `SettingsViewModel.setClipsPerPage` 직접 호출 → displayLayoutDidChange 흐름 자동 (TASK-037 인프라).
    /// 방식 1·2·3 모두 활성 (사용자 답 *방식 1·2 모두 허용*).
    /// TASK-077 — 사용자 요구 정확 반영: popover 사이즈 변경은 *언제나 가능*. autoFit ON + 클립 수 기반 추적 높이 *초과* 시도만 차단.
    /// 흐름: autoFit ON/OFF 무관 *동일 흐름* 진입 (1행 snap + clipsPerPage 동기화). 단 autoFit ON 시 proposedHeight 에 cap (= measuredFittingHeight) 미리 적용해 *cap 초과 시도 자동 차단*.
    /// autoFit ON 일 때도 height drag 시 clipsPerPage 동기화 활성 — effectiveClipListHeight 자동 정합 → SwiftUI body 시각 정합 자동 유지.
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // TASK-097 — Pin 사이드바 리사이즈: 너비만 clamp(180~400), 높이는 현재값 고정(높이 변경 거부).
        if sender === pinSidebarPanel {
            return Self.resolvePinSidebarResize(proposedWidth: frameSize.width, currentHeight: pinSidebarPanel.frame.size.height)
        }
        guard sender === panel else { return frameSize }
        // width clamp.
        let clampedWidth = max(Constants.popoverWidthMin, min(Constants.popoverWidthMax, frameSize.width))
        // TASK-077 — autoFit ON 시 cap = *visibleClips.count 행* 기반 height 으로 proposedHeight clamp.
        // measured (= 현재 clipsPerPage 기반 SwiftUI body fitting) 에 추가 행 분량 더해 cap 산출 (computeAutoFitCap).
        // 예시: visibleCount=10, clipsPerPage=6 → measured=6행+overhead, cap=10행+overhead. 사용자가 10행까지 자유 키움 / 10행 초과 차단.
        // autoFit OFF 시는 cap 적용 X (proposedHeight 그대로 통과).
        let autoFit = settingsViewModel?.autoFitClipListHeight ?? false
        let measured: CGFloat? = currentHosting.map { hosting in
            measuredFittingHeight(width: clampedWidth, hosting: hosting)
        }
        let cap: CGFloat?
        if autoFit, let m = measured, let settings = settingsViewModel {
            let visibleCount = viewModel.visibleClips.count
            let hasPinnedForCap = !viewModel.pinnedClips.isEmpty
            let hintBarVisibleForCap: Bool = (UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hintBarVisible) as? Bool) ?? true
            let capRowsForCap = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: hasPinnedForCap, hintBarVisible: hintBarVisibleForCap)
            cap = ClipsViewModel.computeAutoFitCap(
                measured: m,
                visibleCount: visibleCount,
                clipsPerPage: settings.clipsPerPage,
                capRows: capRowsForCap
            )
        } else {
            cap = measured
        }
        let cappedProposedHeight = KeyablePanel.resolveResizeHeight(
            autoFit: autoFit,
            proposedHeight: frameSize.height,
            measuredFittingHeight: cap
        )
        // TASK-054 fix-2 — 화면 가용 height cap. 사용자가 화면 가용 height 초과 드래그 시 *NSPanel 시스템 제안 그대로 박힘 + SwiftUI body 는 화면 cap 도달 후 더 안 자람* → 차이만큼 빈 영역 (검정 background) 발생. cap 적용해 *NSPanel height 자체* 가 화면 안으로 제한.
        let visibleHeight = (panel.screen ?? NSScreen.main)?.visibleFrame.height ?? 1080
        let cappedFrameHeight = min(cappedProposedHeight, visibleHeight)
        // height snap — 현재 frame.height 와 cap 적용 제안 frame.height 의 차이를 1행 단위 round 후 setClipsPerPage 호출.
        let snap = DesignTokens.Spacing.rowMinHeight + DesignTokens.Spacing.rowGap  // 46pt
        let dy = cappedFrameHeight - panel.frame.size.height
        let absSteps = Int(abs(dy) / snap)

        // TASK-056 — width drag (dy < snap) 시 hintBar FlowLayout wrap 1~3 줄 동적 → fitting.height 변동. snap 단위 무시 시 wrap 변동 미반영. `measuredFittingHeight` 헬퍼 (NSHostingController.sizeThatFits) 로 clampedWidth 제약 박은 정확한 fitting 측정 → live resize 중 popover height 즉시 정합.
        if absSteps == 0, let hosting = currentHosting {
            return NSSize(width: clampedWidth, height: measuredFittingHeight(width: clampedWidth, hosting: hosting))
        }

        guard let settingsViewModel else {
            // settingsViewModel 미주입 시 height freeform 으로 통과 (안전망).
            return NSSize(width: clampedWidth, height: cappedFrameHeight)
        }
        let current = settingsViewModel.clipsPerPage
        // 시스템 resize 컨벤션 — proposed height 증가 (dy > 0) = clipsPerPage 증가. dy < 0 = 감소.
        // computeSnapDelta 의 *isTop=true + accumulated < 0 → +1* 컨벤션과 부호 반대 — 직접 계산.
        let signDelta = dy > 0 ? absSteps : -absSteps
        // TASK-057 — raw `clipsPerPage` 가 화면 cap 초과 상태 (예: raw=50 + cap=27) 에서 축소 드래그 시
        // 기존 `setClipsPerPage(current + signDelta)` 박으면 raw 50→49 만 변동 + clipList 영역은 cap 도달 상태 그대로 (effectiveClipListHeight cap 적용) → NSPanel.frame.height 1행 축소 박혔는데 SwiftUI body fittingSize 불변 → 46pt squeeze → 헤더/preferencesRow 잘림.
        // 해결: 분기 결정을 `ClipsViewModel.resolveNewClipsPerPageForResize` 위임. raw>cap 축소 케이스에서는 raw 를 capRows 로 jump 동기화 후 ±1 진행.
        let hasPinned = !viewModel.pinnedClips.isEmpty
        let hintBarVisible: Bool = (UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.hintBarVisible) as? Bool) ?? true
        let capRows = ClipsViewModel.cappedRowsForCurrentScreen(hasPinned: hasPinned, hintBarVisible: hintBarVisible)
        let newRaw = ClipsViewModel.resolveNewClipsPerPageForResize(current: current, signDelta: signDelta, capRows: capRows)
        if newRaw != current {
            Logger.ui.info("PopoverWindow.windowWillResize — clipsPerPage resize sync current=\(current, privacy: .public) signDelta=\(signDelta, privacy: .public) capRows=\(capRows, privacy: .public) newRaw=\(newRaw, privacy: .public)")
            settingsViewModel.setClipsPerPage(newRaw)
        }
        // TASK-078 — estimatedHeight = *visual delta* × snap. `ClipsViewModel.resolveVisualResizeDelta` 위임.
        // TASK-057 의도 (raw>cap 축소 jump 시 1 행 시각 축소) + TASK-071 Phase 7 의도 (min/max cap 도달 시 frame 유지) 동시 정합.
        // 회귀 fix: TASK-071 Phase 7 이 `effectiveDelta = newRaw - current` 박은 후 raw>cap 축소 jump 케이스 (current=50, newRaw=25, signDelta=-1) 에서 estimatedHeight = current_frame + (-25) * 46 = *너무 작은 값* → NSWindow contentMinSize 박혀 frame 안 줄어듦 → 사용자 들썩거림 (raw 50→49→...→26 까지 시각 변화 0, 27 이하부터 1 행씩 줄어듦).
        // 분기: newRaw == current (min/max cap 도달) → 0 / else → signDelta (사용자 인식 ±1 행 단위, raw jump 무관).
        let visualDelta = ClipsViewModel.resolveVisualResizeDelta(current: current, newRaw: newRaw, signDelta: signDelta)
        let estimatedHeight = panel.frame.size.height + CGFloat(visualDelta) * snap
        return NSSize(width: clampedWidth, height: estimatedHeight)
    }

    /// TASK-054 fix-1 — 시스템 resize 종료 시점. 사이드바·상세 sub-window 동반 추종 + 방식 1 width 변경 시 button 중심 anchor 보정.
    /// `windowDidMove` 와 같은 흐름 (멱등 호출 안전).
    /// TASK-061 — `_performRefreshFrame` 의 내부 `setFrame` 도 `windowDidResize` 발화 → 재진입 loop / measurement race 유발. `_performRefreshFrame` 안 newFrame guard 로 동일 frame skip 박혔지만 *측정 결과 미세 변동* 시 loop 가능. 본 함수 자체에서 `panel.inLiveResize` 검사 — 사용자 라이브 resize 종료 시점만 fitting 보정. 내부 setFrame trigger 는 skip.
    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        // TASK-071 — 방식 1 width 변경 시 button 중심 origin.x 강제 재정렬 분기 제거 (사용자 본체 드래그 / 코너 대각선 드래그 결과 origin 강제 보정이 시각 점프 직접 원인).
        // TASK-071 — 사이드바·상세 sub-window 동반 추종 mode 가드 제거 (방식 1·2·3 모두 활성).
        if currentMode != nil {
            if pinSidebarPanel.isVisible {
                resizePinSidebarPanel()
            }
            if let last = lastShownDetailRequest, detailPanel.isVisible {
                showClipDetailPanel(last)
            }
        }
        // TASK-056 — width 변경 후 hintBar FlowLayout wrap 1~3 줄 동적 → SwiftUI body fittingSize.height 동적. `windowWillResize` 는 snap 단위 height 만 갱신해 wrap 변동 미반영 → SwiftUI body 가 NSPanel 안 못 들어가 시각 잘림 (상단 padding 좁아 보임 인지). resize 종료 시점 fittingSize 재측정 + NSPanel.height 자동 정합.
        // TASK-061 — *사용자 라이브 resize 종료* 흐름만 발화 (또는 종료 직후). 내부 setFrame trigger windowDidResize 는 skip — loop / measurement race 차단.
        // (panel.inLiveResize 는 라이브 resize 진행 중 true, 종료 직후 false. 종료 직후 발화 1회 정도는 통과.)
        // 휴리스틱: panel.styleMask 가 .resizable 이고 *최근 windowWillResize 발화* 박혔는지 추적 필요. 단순화 — 그냥 refreshFrame 호출 제거. windowWillResize 흐름이 setClipsPerPage 호출 + displayLayoutDidChange notification 발행 → refreshFrame 자체 호출됨.
        // refreshFrame()  // TASK-061 제거 — windowWillResize → displayLayoutDidChange → refreshFrame 경로로 자연 호출.
    }

    /// TASK-097 — Pin 사이드바 라이브 리사이즈 종료 시점: 조정된 너비를 UserDefaults 에 영속(항상 저장) + origin 재계산(안쪽 엣지 popover 밀착).
    /// 본체 popover 는 별도 처리(windowWillResize → clipsPerPage 동기화)라 여기선 사이드바 패널만 담당.
    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === pinSidebarPanel else { return }
        let newWidth = Self.clampPinSidebarWidth(pinSidebarPanel.frame.size.width)
        UserDefaults.standard.set(Double(newWidth), forKey: Constants.UserDefaultsKeys.pinSidebarWidth)
        Logger.ui.info("Pin sidebar width persisted = \(newWidth, privacy: .public)")
        // 저장 너비 기준으로 프레임 재적용 — 안쪽 엣지를 popover 에 재밀착(방향별 originX 재계산).
        resizePinSidebarPanel()
    }
}
