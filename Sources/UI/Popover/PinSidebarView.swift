// Pin 사이드 메뉴 — popover.jsx L539-602 100% 정합 + TASK-019 fix 2차 (ClipRowView 재사용)
// 220 width / Liquid Glass / "핀 목록 · N" UPPERCASE 헤더 + 항목은 본체 클립 행과 동일 ClipRowView 형태
import SwiftUI

struct PinSidebarView: View {
    @Bindable var viewModel: ClipsViewModel
    let mode: PopoverInvocationMode
    /// 핀 항목 *paste* 시 호출 — PopoverWindow.handleClipPaste 흐름과 동일 (dismiss → frontmost 복원 → sleep → paste).
    /// TASK-028 — 핀 행 paste 호출 시 `zone: .pin` 명시 전달. hide() → collapsePinSidebar() → focusZone=.clip 흐름이 paste 대상에 영향 X.
    let handleClipPaste: @MainActor (Int, FocusZone) async -> Void
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 핀 행 body 재평가 트리거 (`.equatable()` 박힌 상태에서 모드 변경 회피 X).
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-073 — 언어 변경 시 body 재평가 → 헤더 "핀 목록" 라벨 등 새 언어 lookup.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    var body: some View {
        let _ = accentColorModeRaw  // TASK-053 SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: DesignTokens.Spacing.rowGap) {
                    ForEach(Array(viewModel.pinnedClips.enumerated()), id: \.element.id) { idx, clip in
                        // TASK-019 fix 2차 — 본체 ClipRowView 컴포넌트 그대로 사용 (타입 아이콘 + 본문 + 핀해제 버튼).
                        // TASK-019 fix 3차 — showTimeLabel: false 박아 시간 영역 제거 (220 너비 안 본문 truncate 완화 — B8).
                        ClipRowView(
                            clip: clip,
                            isSelected: viewModel.pinSelectedIdx == idx,
                            isFocused: viewModel.focusZone == .pin,
                            isFlashing: viewModel.flashedClipId == clip.id,
                            mode: mode,
                            showTimeLabel: false,
                            searchQuery: "",  // TASK-035 — Pin 사이드바는 검색 결과 영역 아님. UX-UI §7-3 적용 범위 제외.
                            onClick: {
                                // 클릭 시 paste 흐름 — focusZone=.pin / pinSelectedIdx 갱신 (사이드바 nav cursor + detail panel hook 동기화).
                                // TASK-028 — paste 대상은 zone=.pin 명시로 결정. focusZone 후속 변경 (hide → collapsePinSidebar) 영향 X.
                                // TASK-060 — `.equatable()` view 재사용 시 closure stale idx 위험. clip.id 로 현재 pinnedClips 에서 idx 다시 찾음.
                                guard let currentIdx = viewModel.pinnedClips.firstIndex(where: { $0.id == clip.id }) else { return }
                                viewModel.focusZone = .pin
                                viewModel.pinSelectedIdx = currentIdx
                                Task { @MainActor in
                                    await handleClipPaste(currentIdx, .pin)
                                }
                            },
                            onHover: {
                                // hover 시 pinSelectedIdx 갱신 — 키보드 nav와 동일 cursor 위치.
                                // TASK-060 — 동일 사유. clip.id 로 현재 idx.
                                guard let currentIdx = viewModel.pinnedClips.firstIndex(where: { $0.id == clip.id }) else { return }
                                viewModel.setPinSelectedIdx(currentIdx)
                            },
                            onTogglePin: {
                                // 핀해제 (파란 압정 아이콘 클릭) — id 기반 unpin 호출.
                                Task { @MainActor in
                                    await viewModel.togglePin(id: clip.id, trackSelection: .pin)
                                }
                            },
                            onDelete: {
                                // 핀 항목 행 우측은 항상 pin.fill 아이콘 분기라 onDelete 호출 X.
                                // (clip.isPinned == true 이므로 ClipRowView 의 X 아이콘 분기 진입 X)
                            },
                            onHoverEnter: { viewModel.hoverEnterRow(id: clip.id) },  // TASK-055 — hover 임계 timer 시작.
                            onHoverExit: { viewModel.hoverExitRow(id: clip.id) }    // TASK-055 — 같은 행 이탈 시 timer cancel.
                        )
                        // TASK-037 fix-15b — Equatable + .equatable() → 호버 응답 빠름.
                        .equatable()
                    }
                    if viewModel.pinnedClips.isEmpty {
                        Text(L10n("pin.sidebar.empty"))
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignTokens.Colors.labelSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                }
                .padding(.horizontal, DesignTokens.Spacing.rowOuterHorzInset)
            }
        }
        .padding(DesignTokens.Spacing.pinSidebarPadding)
        .frame(width: DesignTokens.WindowSize.pinSidebarWidth)
        .background(Color.clear)
        // TASK-027 fix — coordinateSpace + ActiveRowFramePreferenceKey 수신을 PinSidebarView root 에 박음 (ScrollView 박으면 헤더 offset 어긋남).
        .popoverClipDetailHook(viewModel: viewModel, activeZone: .pin)
        .onHover { isHover in
            if isHover {
                viewModel.pinSidebarHoverEnter()
            } else {
                viewModel.pinSidebarHoverExit()
            }
        }
    }

    private var header: some View {
        // TASK-019 fix 3차 — `textCase(.uppercase)` 제거 (B9). "핀 목록 · N" 원형 표시.
        Text(L10n("pin.sidebar.title") + " · \(viewModel.pinnedClips.count)")
            .font(DesignTokens.Typography.pinSidebarHeader)
            .tracking(0.4)
            .foregroundStyle(DesignTokens.Colors.pinSidebarHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DesignTokens.Spacing.pinRowPaddingHorz)
            .padding(.top, DesignTokens.Spacing.pinSidebarHeaderPadTop)
            .padding(.bottom, DesignTokens.Spacing.pinSidebarHeaderPadBottom)
    }
}
