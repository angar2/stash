// 설정 단축키 탭 — *기본 단축키* 7항목 + *PIN 단축키* 10항목(순번·명칭·값·조합) 두 묶음의 접힘 화면.
// 단축키 모델·저장 계층은 `PopoverShortcutStore.swift`, 조합 입력 Recorder 는 `PopoverShortcutRecorder.swift` 참조 (TASK-098 리팩토링에서 분리).
import SwiftUI
import AppKit
import KeyboardShortcuts
import OSLog

// MARK: - ShortcutsTab

struct ShortcutsTab: View {
    @Bindable var viewModel: SettingsViewModel
    /// TASK-098 — `PIN 단축키` 묶음이 각 핀의 *명칭·값* 을 표시·수정하므로 클립 뷰모델이 필요하다.
    @Bindable var clipsViewModel: ClipsViewModel
    /// TASK-053 — 콘텐츠 색상 모드 변경 시 강조 텍스트 즉시 갱신.
    @AppStorage(AccentColorMode.userDefaultsKey) private var accentColorModeRaw: String = AccentColorMode.default.rawValue
    /// TASK-073 — 앱 언어 변경 시 body 재평가 → 모든 i18n 키 lookup 새 언어.
    @AppStorage(AppLanguage.userDefaultsKey) private var appLanguageRaw: String = AppLanguage.systemDefault.rawValue

    // TASK-098 — 묶음 접힘 상태 영속. 초기값 = 기본 단축키 열림 / PIN 단축키 닫힘
    // (PIN 행이 2줄 구조라 함께 펼치면 탭 진입만으로 스크롤 발생 — UX-UI §4-4).
    @AppStorage(Constants.UserDefaultsKeys.shortcutsBasicGroupExpanded) private var basicExpanded: Bool = true
    @AppStorage(Constants.UserDefaultsKeys.shortcutsPinGroupExpanded) private var pinExpanded: Bool = false

    /// TASK-098 — 인라인 편집 대상. 한 번에 한 행만 활성.
    /// fix-3 — 키를 *클립 id* → **순번** 으로 변경. 클립 id 기준이면 핀이 없는 순번은 편집 자체가 불가능해
    /// (핀 1개 사용자는 1번 행만 열리고 2번 이후는 클릭해도 무반응) 10개 행 전부 열려야 하는 요건을 만족할 수 없다.
    private enum EditField: Hashable {
        case alias(Int)
        case value(Int)
    }
    /// TASK-098 fix-1 — **편집기 렌더 상태는 `@FocusState` 와 분리한다.**
    /// 1차 구현은 `isEditing = focusedField == .alias(id)` 로 존재 여부를 판정했는데,
    /// 탭 시점엔 아직 TextField 가 계층에 없어 SwiftUI 가 focus 요청을 즉시 nil 로 되돌린다
    /// → `isEditing` 이 곧바로 false → **입력창이 아예 뜨지 않고** focus 이탈로 인식돼 빈 draft 저장까지 돌았다.
    ///
    /// TASK-098 fix-2 — 편집 단위를 *필드* 에서 **행** 으로 올렸다. 행을 클릭하면 명칭·값 인풋이 함께 열린다.
    /// TASK-098 fix-3 — 행 식별을 클립 id → **순번** 으로 변경 (핀 없는 순번도 편집 가능해야 하므로).
    /// 렌더는 본 `editingOrdinal` 이, 키보드 focus 는 필드가 생긴 뒤(`onAppear`) `focusedField` 가 담당한다.
    @State private var editingOrdinal: Int?
    /// TASK-098 검증 — 저장 대상 클립을 편집 진입 시점에 고정한다. 확정 시점에 순번으로 다시 조회하면
    /// 편집 중 핀 목록이 바뀐 경우(다른 창에서 핀 해제 등) 같은 순번의 *다른 클립* 에 쓴다.
    @State private var editingClipId: UUID?
    @FocusState private var focusedField: EditField?
    @State private var aliasDraft: String = ""
    @State private var valueDraft: String = ""

    /// 기본 단축키 묶음 = Pin 직접 paste 를 뺀 나머지 (열거형 순서 유지).
    private var basicIDs: [PopoverShortcutID] { PopoverShortcutID.allCases.filter { $0.pinOrdinal == nil } }

    var body: some View {
        let _ = accentColorModeRaw  // SwiftUI 의존성 등록
        let _ = appLanguageRaw      // TASK-073 — 언어 변경 시 body 재평가
        return VStack(spacing: 10) {
            // 묶음 1 — 기본 단축키 (초기 열림)
            settingsCard {
                VStack(spacing: 0) {
                    groupHeader(titleKey: "shortcuts.group.basic", expanded: $basicExpanded)
                    if basicExpanded {
                        Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                        ForEach(Array(basicIDs.enumerated()), id: \.element) { idx, id in
                            popoverShortcutRow(id: id)
                            if idx < basicIDs.count - 1 {
                                Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                            }
                        }
                    }
                }
            }

            // 묶음 2 — PIN 단축키 (초기 닫힘). 행마다 명칭·값 2줄.
            settingsCard {
                VStack(spacing: 0) {
                    groupHeader(titleKey: "shortcuts.group.pin", expanded: $pinExpanded)
                    if pinExpanded {
                        Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                        let pinIDs = PopoverShortcutID.pinPasteIDs
                        // 핀 목록은 **여기서 한 번만** 계산한다. 행마다 `clipsViewModel.pinnedClips` 를 읽으면
                        // filter + sort 가 body 재평가마다 10회 돈다.
                        // TASK-098 검수 정정 — 행↔핀 매칭은 배열 위치가 아니라 **자리 번호**(`pin_slot`).
                        // 2번을 해제하면 2번 행만 비고 3번 행은 그대로 3번 핀을 보여준다.
                        let bySlot = Dictionary(
                            clipsViewModel.pinnedClips.compactMap { clip in clip.pinSlot.map { ($0, clip) } },
                            uniquingKeysWith: { first, _ in first }
                        )
                        ForEach(Array(pinIDs.enumerated()), id: \.element) { idx, id in
                            pinShortcutRow(
                                id: id,
                                ordinal: idx + 1,
                                clip: bySlot[idx + 1]
                            )
                            if idx < pinIDs.count - 1 {
                                Divider().foregroundStyle(DesignTokens.Colors.settingsRowDivider)
                            }
                        }
                    }
                }
            }

            HStack {
                Spacer()
                // TASK-065 — *전체 되돌리기* 카드형 버튼. hover 시 배경 톤.
                HoverFillCardButton(
                    action: { viewModel.resetAllShortcuts() },
                    fill: DesignTokens.Colors.settingsCardBg,
                    fillHover: DesignTokens.Colors.settingsCardBgHover
                ) {
                    Text(L10n("shortcuts.resetAll"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Colors.labelPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }

            Text(L10n("shortcuts.note"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        // TASK-098 fix-5 — **바깥 클릭 자동 저장 폐기.** 확정은 인풋 아래 원형 아이콘 버튼(체크/X)으로만 한다.
        // fix-4 까지는 focus 이탈·바깥 탭 제스처·인풋 소멸 등 암묵 경로로 저장했는데, 저장 시점을 사용자가
        // 통제할 수 없어 불편하다는 검수 결과. 이제 저장은 *명시적 버튼 또는 명칭 필드 Enter* 뿐이다.
        // ESC 는 취소 (편집 중일 때만 가로챈다 — 아니면 창 닫기 등 기본 동작 유지).
        .onExitCommand { if editingOrdinal != nil { cancelRow() } }
        // TASK-098 fix-3 — 콘텐츠를 항상 창 높이 상한까지 채운다.
        // 이전에는 PIN 묶음 접힘 상태 콘텐츠가 상한(480)보다 짧아, 펼칠 때 *창이 조금 길어지다가 그 다음부터 스크롤* 이
        // 되는 두 동작이 섞였다(사용자 검수 지적). 처음부터 상한에 붙여두면 창 높이는 고정되고 펼침은 스크롤만 만든다.
        .frame(
            minHeight: DesignTokens.WindowSize.settingsContentMaxH - DesignTokens.Spacing.settingsContentMargin * 2,
            alignment: .top
        )
    }

    // MARK: - TASK-098 묶음 헤더 (접힘)

    /// 묶음 접힘 헤더 — 제목 + 펼침 표시(▶/▼). **항목 개수는 표기하지 않는다.**
    private func groupHeader(titleKey: String, expanded: Binding<Bool>) -> some View {
        _GroupHeaderButton(titleKey: titleKey, expanded: expanded)
    }

    // MARK: - TASK-098 PIN 단축키 행 (2줄)

    /// PIN 단축키 행. 위줄 = 순번 · 타입 아이콘 · 명칭 · 조합 · 되돌리기 / 아래줄 = 값.
    ///
    /// TASK-098 fix-3 — **핀이 있든 없든 10개 행 모두 클릭하면 인풋이 열린다.**
    /// fix-2 까지는 편집 키가 *클립 id* 여서 핀이 없는 순번(클립 없음)은 편집 자체가 불가능했다
    /// → 핀이 1개인 사용자는 1번 행만 열리고 2번 이후는 클릭해도 반응이 없었다.
    /// 편집 키를 **순번** 으로 바꾸고, 빈 순번에서 값을 입력해 확정하면 새 핀을 만든다.
    private func pinShortcutRow(id: PopoverShortcutID, ordinal: Int, clip: Clip?) -> some View {
        let isEditing = editingOrdinal == ordinal

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                // 순번 · 타입 아이콘 · 명칭을 한 덩어리로 묶어 **행 앞부분 어디를 클릭해도** 편집이 열리게 한다
                // (승인 목업은 행 전체 클릭. 이전에는 명칭·값 *글자* 만 클릭 대상이라 순번·아이콘·여백이 무반응이었다).
                // 조합 입력(Recorder)·되돌리기는 자기 클릭을 가져야 하므로 이 클러스터 밖에 둔다.
                pinRowLeadingCluster(ordinal: ordinal, clip: clip, isEditing: isEditing)

                PopoverShortcutRecorder(id: id) { newShortcut in
                    viewModel.handlePopoverShortcutChange(id: id, newShortcut: newShortcut, allIds: PopoverShortcutID.allCases)
                }
                .frame(width: 100, height: 22)

                _ResetShortcutItemButton(action: { viewModel.resetPopoverShortcut(id: id) })
            }

            Group {
                if isEditing {
                    valueInput(clip: clip, ordinal: ordinal)
                } else {
                    valueDisplay(clip: clip, ordinal: ordinal)
                }
            }
            // 들여쓰기 = 순번(15) + gap(8) + 아이콘(13) + gap(8)
            .padding(.leading, 44)

            // fix-5 — 저장 / 취소 (아이콘 전용 원형 버튼, 좌측 정렬). 인풋 왼쪽선과 같은 들여쓰기.
            if isEditing {
                HStack(spacing: 6) {
                    _CircleIconButton(
                        systemName: "checkmark",
                        tint: DesignTokens.Colors.pinSaveButton,
                        labelKey: "shortcuts.pin.save",
                        disabled: !canSave(clip: clip),
                        action: { saveRow(ordinal: ordinal) }
                    )
                    _CircleIconButton(
                        systemName: "xmark",
                        tint: DesignTokens.Colors.labelSecondary,
                        labelKey: "shortcuts.pin.cancel",
                        disabled: false,
                        action: { cancelRow() }
                    )
                    // 핀 해제 — 설정에서 핀을 *만들 수* 있으니 *없앨 수* 도 있어야 한다(검수 지적).
                    // 편집 중에만 노출한다 — 상시 노출하면 조합 입력 옆에 파괴적 버튼이 놓여 오클릭 위험이 생긴다.
                    // 저장·취소와 시각적으로 떼어놓고(간격 + 경고 톤) 클립 삭제가 아님을 색으로도 구분한다.
                    if let clip {
                        // 아이콘은 popover 클립 행의 핀 버튼과 **같은 글리프·같은 45° 기울기** 를 쓴다
                        // (`pin.slash` 는 사이드바 압정과 형태가 달라 이질감을 준다는 검수 지적).
                        // 사이드바에서도 이 기울어진 압정을 누르는 것이 곧 핀 해제라 동작 대응도 일치한다.
                        _CircleIconButton(
                            systemName: "pin.fill",
                            tint: DesignTokens.Colors.pinUnpinButton,
                            labelKey: "shortcuts.pin.unpin",
                            disabled: false,
                            rotationDegrees: 45,
                            action: { unpinRow(clip: clip) }
                        )
                        .padding(.leading, 10)
                    }
                }
                .padding(.leading, 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// 저장 가능 여부 — 값이 비면 저장 불가(빈 클립 금지). 값 수정이 안 되는 타입(이미지·파일)은 명칭만 저장하므로 항상 가능.
    private func canSave(clip: Clip?) -> Bool {
        let editable = clip.map { PinPasteShortcutResolver.isValueEditable(type: $0.type) } ?? true
        guard editable else { return true }
        return PinPasteShortcutResolver.normalizeValue(valueDraft) != nil
    }

    // MARK: - TASK-098 위줄 좌측 클러스터 (순번 · 타입 아이콘 · 명칭)

    /// 위줄의 순번·아이콘·명칭 묶음. **비편집 상태에서만** 탭 제스처를 붙인다 —
    /// 편집 중에 붙여 두면 명칭 인풋으로 가야 할 클릭을 부모 제스처가 가로챈다.
    @ViewBuilder
    private func pinRowLeadingCluster(ordinal: Int, clip: Clip?, isEditing: Bool) -> some View {
        let cluster = HStack(alignment: .center, spacing: 8) {
            // 순번 — 행의 가장 좌측 (승인된 인터랙션 목업 순서: 순번 → 타입 아이콘).
            Text("\(ordinal)")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .frame(width: 15)

            // 타입 아이콘 — 고정폭이라 핀 없는 행(빈 칸)에서도 정렬이 어긋나지 않는다.
            Group {
                if let clip {
                    Image(systemName: PinPasteShortcutResolver.typeSymbol(type: clip.type, isMultiFile: clip.isMultiFile))
                        .font(.system(size: 11, weight: .regular))
                } else {
                    Color.clear
                }
            }
            .frame(width: 13, height: 13)
            .foregroundStyle(DesignTokens.Colors.labelSecondary)

            if isEditing {
                aliasInput(ordinal: ordinal)
            } else {
                aliasDisplay(clip: clip)
            }
        }

        if isEditing {
            cluster
        } else {
            cluster
                .contentShape(Rectangle())
                .onTapGesture { beginEditing(ordinal: ordinal, clip: clip) }
        }
    }

    // MARK: - TASK-098 명칭 / 값 — 표시 상태

    /// 명칭 표시(비편집). 클릭 판정은 상위 클러스터가 담당한다.
    private func aliasDisplay(clip: Clip?) -> some View {
        let alias = clip.flatMap { PinPasteShortcutResolver.normalizeAlias($0.pinAlias) }
        return Group {
            if let alias {
                Text(alias)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                Text(L10n("shortcuts.pin.aliasEmpty"))
                    .font(.system(size: 12.5, weight: .regular))
                    .italic()
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 값 표시(비편집). 클릭 시 그 행의 명칭·값 인풋이 함께 열린다 (핀 없는 순번도 동일).
    private func valueDisplay(clip: Clip?, ordinal: Int) -> some View {
        let locked = clip.map { !PinPasteShortcutResolver.isValueEditable(type: $0.type) } ?? false
        return HStack(spacing: 6) {
            Text(clip.map { Self.valuePreview(for: $0) } ?? L10n("shortcuts.pin.slotEmpty"))
                .font(.system(size: 11, weight: .regular))
                .italic(clip == nil)
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if locked {
                Text(L10n("shortcuts.pin.valueLocked"))
                    .font(.system(size: 9.5, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { beginEditing(ordinal: ordinal, clip: clip) }
    }

    // MARK: - TASK-098 명칭 / 값 — 편집 인풋 (외형 통일)

    /// 명칭 인풋 — 한 줄. Enter 확정.
    private func aliasInput(ordinal: Int) -> some View {
        HStack(spacing: 6) {
            TextField(
                "",
                text: $aliasDraft,
                prompt: Text(L10n("shortcuts.pin.aliasPlaceholder"))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            )
            .textFieldStyle(.plain)
            .font(Self.inputFont)
            .focused($focusedField, equals: .alias(ordinal))
            // 필드가 계층에 들어온 *뒤* 에 focus 요청 — 순서가 뒤바뀌면 SwiftUI 가 요청을 버린다 (fix-1).
            .onAppear { focusedField = .alias(ordinal) }
            // 명칭은 한 줄이라 Enter 로 저장 (체크 버튼과 동일 경로).
            .onSubmit { saveRow(ordinal: ordinal) }
            // 탭 전환 · 창 닫기 · 묶음 접기로 인풋이 사라지면 **취소**로 처리한다 (fix-5 — 암묵 저장 폐기).
            .onDisappear { if editingOrdinal == ordinal { cancelRow() } }
            .onChange(of: aliasDraft) { _, new in
                if new.count > Constants.pinAliasMaxLength {
                    aliasDraft = String(new.prefix(Constants.pinAliasMaxLength))
                }
            }
            Text("\(aliasDraft.count)/\(Constants.pinAliasMaxLength)")
                .font(.system(size: 9.5, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Colors.labelSecondary)
        }
        .modifier(_InputChrome(isFocused: focusedField == .alias(ordinal)))
        .frame(maxWidth: .infinity)
    }

    /// 값 인풋 — 여러 줄. 최대 높이 초과 시 영역 내부 스크롤.
    /// 이미지·파일 클립은 본문이 없어 편집 대상이 아니므로 표시 상태를 유지한다.
    @ViewBuilder
    private func valueInput(clip: Clip?, ordinal: Int) -> some View {
        let editable = clip.map { PinPasteShortcutResolver.isValueEditable(type: $0.type) } ?? true
        if editable {
            // fix-4 — `TextEditor` 대신 **세로 확장 `TextField`**.
            // TextEditor 는 자체 text container inset 을 갖고(공개 API 로 제거 불가) 텍스트를 위로 붙여 놓기 때문에,
            // 명칭 필드(TextField)와 *좌측 시작점·세로 정렬이 둘 다 어긋났다*(사용자 검수 스크린샷).
            // 같은 컨트롤 계열로 바꾸면 여백·정렬·서체가 자동으로 일치하고 플레이스홀더도 prompt 로 동일하게 처리된다.
            TextField(
                "",
                text: $valueDraft,
                prompt: Text(L10n("shortcuts.pin.valuePlaceholder"))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(Self.inputFont)
            // 한 줄에서 시작해 내용만큼 늘어난다 (상한 6줄 — 넘으면 내부 스크롤).
            .lineLimit(1...6)
            .focused($focusedField, equals: .value(ordinal))
            // 행 진입 시 focus 는 명칭에 준다 — 값은 클릭·Tab 으로 이동.
            // 값은 여러 줄이라 Enter 가 개행 — 저장은 체크 버튼으로만.
            .onDisappear { if editingOrdinal == ordinal { cancelRow() } }
            .modifier(_InputChrome(isFocused: focusedField == .value(ordinal)))
            .frame(maxWidth: .infinity)
        } else {
            valueDisplay(clip: clip, ordinal: ordinal)
        }
    }

    /// 두 인풋 공통 서체 — 외형 통일.
    private static let inputFont: Font = .system(size: 12, weight: .regular)

    // MARK: - TASK-098 편집 진입 / 확정

    /// 행 편집 진입 — 명칭·값 draft 를 현재 값으로 채우고 두 인풋을 함께 띄운다.
    /// 핀이 없는 순번이면 빈 draft 로 시작하고, 값을 입력해 확정하면 새 핀이 만들어진다.
    private func beginEditing(ordinal: Int, clip: Clip?) {
        guard editingOrdinal != ordinal else { return }
        aliasDraft = clip?.pinAlias ?? ""
        valueDraft = clip?.body ?? ""
        // 저장 대상은 **여기서 고정한다.** 확정 시점에 순번으로 다시 조회하면 편집 중 핀 목록이 바뀐 경우
        // (다른 창에서 핀 해제 등) 엉뚱한 클립에 쓴다.
        editingClipId = clip?.id
        editingOrdinal = ordinal
    }

    /// 편집 취소 — 입력을 버리고 표시 상태로 돌아간다 (fix-5. 저장은 오직 `saveRow`).
    private func cancelRow() {
        guard let ordinal = editingOrdinal else { return }
        Logger.ui.info("PIN 행 편집 취소 — ordinal=\(ordinal, privacy: .public) (입력 버림)")
        clearEditing()
    }

    private func clearEditing() {
        editingOrdinal = nil
        editingClipId = nil
        focusedField = nil
        aliasDraft = ""
        valueDraft = ""
    }

    /// 행 확정 — 명칭·값을 함께 저장한다. *변경된 것만* 저장해 불필요한 DB 쓰기·목록 갱신을 피한다.
    /// 핀이 없던 순번에 값이 입력됐으면 새 핀을 만든다.
    /// 저장은 체크 버튼 또는 명칭 필드 Enter 로만 호출된다.
    private func saveRow(ordinal: Int) {
        // 중복 실행 방지 게이트 — 같은 행의 두 번째 호출은 no-op.
        // (draft 를 비우는 방식은 위험 — 두 번째 호출이 *사용자가 명칭을 지웠다* 로 오인해 기존 명칭을 삭제한다.)
        guard editingOrdinal == ordinal else { return }
        let clip = editingClipId.flatMap { id in clipsViewModel.clips.first { $0.id == id } }
        let alias = aliasDraft
        let body = valueDraft

        // ── 거부 경로 — 편집 상태를 유지하고 입력을 버리지 않는다 (승인 목업 정합).
        //    Enter 는 체크 버튼과 같은 경로인데 버튼은 비활성인 상태가 있으므로, 여기서 같은 조건을 한 번 더 막는다.
        //    이 게이트가 없으면 빈 순번에 *명칭만* 넣고 Enter 를 쳤을 때 편집창이 조용히 닫히고 입력이 사라진다.
        guard canSave(clip: clip) else {
            Logger.ui.info("PIN 행 저장 거부 — ordinal=\(ordinal, privacy: .public) 사유: 값 비어 있음 (편집 유지)")
            viewModel.settingsToast.enqueue(.warn, L10n("toast.pin.valueRequired"))
            return
        }
        if clip == nil {
            // 한도 초과는 여기서 먼저 잡는다 — 뷰모델의 토스트는 popover 큐로 나가서 설정 창에서는 보이지 않는다.
            // 빈 자리 유무가 아니라 **개수** 로 판정한다. 클릭한 행이 비어 있다는 건 그 자리가 비었다는 뜻이라
            // 자리 기준으로는 한도에 걸릴 수 없고, 자리 없는 옛 핀이 섞였을 때만 개수가 먼저 찬다.
            guard clipsViewModel.pinnedClips.count < Constants.maxPinnedClips else {
                Logger.ui.info("PIN 행 저장 거부 — ordinal=\(ordinal, privacy: .public) 사유: 핀 한도 초과 (편집 유지)")
                viewModel.settingsToast.enqueue(.warn, String(format: L10n("toast.pin.limit"), Constants.maxPinnedClips))
                return
            }
            // 같은 본문이 이미 다른 번호에 고정돼 있으면 새 핀을 만들 수 없다 (수집 dedup 정책상 같은 본문은 한 row).
            // 안내 없이 진행하면 요청한 자리는 빈 채로 남고 입력만 사라져 *저장이 안 먹은 것* 처럼 보인다.
            if let dup = clipsViewModel.pinnedClips.first(where: { $0.type == .text && $0.body == body }) {
                Logger.ui.info("PIN 행 저장 거부 — ordinal=\(ordinal, privacy: .public) 사유: 같은 본문이 \(dup.pinSlot?.description ?? "?", privacy: .public)번에 이미 고정 (편집 유지)")
                viewModel.settingsToast.enqueue(.warn, String(format: L10n("toast.pin.alreadyPinned"), dup.pinSlot ?? ordinal))
                return
            }
        }

        // ── 확정
        clearEditing()

        guard let clip else {
            Task { @MainActor in
                // 클릭한 **그 번호** 자리에 꽂는다 (TASK-098 검수 정정 — 자리 개념 도입으로 해소된 제약).
                let created = await clipsViewModel.createPinnedClip(body: body, alias: alias, slot: ordinal)
                if !created {
                    viewModel.settingsToast.enqueue(.warn, L10n("toast.pin.createFailed"))
                }
            }
            return
        }

        let normalizedAlias = PinPasteShortcutResolver.normalizeAlias(alias)
        let aliasChanged = normalizedAlias != PinPasteShortcutResolver.normalizeAlias(clip.pinAlias)
        let bodyChanged = PinPasteShortcutResolver.isValueEditable(type: clip.type) && body != (clip.body ?? "")
        guard aliasChanged || bodyChanged else { return }

        let clipId = clip.id
        Task { @MainActor in
            if aliasChanged { await clipsViewModel.setPinAlias(id: clipId, rawAlias: alias) }
            if bodyChanged { await clipsViewModel.updateClipBody(id: clipId, rawBody: body) }
        }
    }

    /// 핀 해제 — 편집을 닫고 `is_pinned` 만 내린다. 항목은 히스토리에 남고 값 수정분도 유지되므로 확인 창을 두지 않는다.
    /// 명칭은 repository `togglePin` 이 함께 초기화한다 (재고정 시 옛 이름 부활 방지).
    /// 해제한 자리만 비고 다른 행의 번호·조합은 그대로다 — 그 결과가 이 화면에서 바로 보인다.
    private func unpinRow(clip: Clip) {
        Logger.ui.info("PIN 행 핀 해제 — clipId=\(clip.id.uuidString, privacy: .public)")
        clearEditing()
        let clipId = clip.id
        Task { @MainActor in
            await clipsViewModel.unpinFromSettings(id: clipId)
            viewModel.settingsToast.enqueue(.info, L10n("toast.pin.unpinned"))
        }
    }

    /// 값 미리보기 — 타입별 표시 라벨(`ClipRowView.displayLabel`)을 한 줄로 접는다.
    /// TASK-098 검증 — 이전에는 본문/파일 경로를 직접 조립해 **이미지 핀에 내부 UUID 파일명**이,
    /// **다중 파일 묶음에 첫 파일명**이 나왔다. 표시 규칙은 클립 행과 한 소스를 본다.
    private static func valuePreview(for clip: Clip) -> String {
        ClipRowView.displayLabel(for: clip).replacingOccurrences(of: "\n", with: " ")
    }

    /// 라벨 옆에 덧붙일 단서의 i18n 키. 없으면 nil.
    private static func labelNoteKey(for id: PopoverShortcutID) -> String? {
        switch id {
        case .deleteAll: return "shortcuts.deleteAll.note"
        case .multiSelectToggle: return "shortcuts.multiSelectToggle.note"
        default: return nil
        }
    }

    private func popoverShortcutRow(id: PopoverShortcutID) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n(id.labelKey))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.labelPrimary)
            // TASK-065 — 라벨 우측 secondary 컬러 부가 설명. 라벨 자체는 단순하게 두고 단서만 분리한다.
            // TASK-099 — *다중 선택* 도 이름만으로는 무엇을 고르는지 알기 어려워 같은 자리를 쓴다.
            if let noteKey = Self.labelNoteKey(for: id) {
                Text(L10n(noteKey))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
            }
            Spacer()
            PopoverShortcutRecorder(id: id) { newShortcut in
                viewModel.handlePopoverShortcutChange(id: id, newShortcut: newShortcut, allIds: PopoverShortcutID.allCases)
            }
            .frame(width: 100, height: 22)
            // TASK-065 — 항목별 *되돌리기* 텍스트 hover 시 accent 진하게.
            _ResetShortcutItemButton(action: { viewModel.resetPopoverShortcut(id: id) })
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

// MARK: - TASK-098 저장 / 취소 원형 아이콘 버튼 (fix-5)

/// 아이콘 전용 원형 버튼. **텍스트를 화면에 노출하지 않고** 라벨은 툴팁 + 접근성 라벨로만 둔다.
@MainActor
private struct _CircleIconButton: View {
    let systemName: String
    let tint: Color
    let labelKey: String
    let disabled: Bool
    /// 글리프 회전(도). 핀 해제 버튼이 popover 압정과 같은 45° 기울기를 쓰기 위한 것. 기본 0 = 회전 없음.
    var rotationDegrees: Double = 0
    let action: () -> Void

    @State private var isHovered = false

    /// fix-6 — 24 → 20pt (사용자 검수: 버튼이 큼). 행 안 보조 동작이라 조합 입력(22pt)보다 작게 둔다.
    private let size: CGFloat = 20

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tint)
                .rotationEffect(.degrees(rotationDegrees))
                .frame(width: size, height: size)
                .background(
                    Circle().fill(
                        isHovered && !disabled
                            ? tint.opacity(0.18)
                            : DesignTokens.Colors.settingsCircleButtonBg
                    )
                )
                .overlay(
                    Circle().stroke(
                        tint.opacity(isHovered && !disabled ? 0.70 : 0.38),
                        lineWidth: 0.5
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1.0)
        .onHover { isHovered = $0 }
        .help(L10n(labelKey))
        .accessibilityLabel(Text(L10n(labelKey)))
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}

// MARK: - TASK-098 인풋 공통 외형

/// 명칭·값 인풋 공통 chrome — **두 인풋의 모양을 같게** 만드는 단일 지점 (fix-2).
/// 1차 구현은 명칭이 테두리 없는 평문, 값은 accent 테두리 박스여서 모양이 달랐다.
private struct _InputChrome: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(DesignTokens.Colors.settingsInputBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isFocused ? DesignTokens.Colors.accent : DesignTokens.Colors.labelSecondary.opacity(0.35),
                        lineWidth: isFocused ? 1 : 0.5
                    )
            )
    }
}

// MARK: - TASK-098 묶음 접힘 헤더

/// 묶음 헤더 — 제목 + 펼침 표시. 마우스 올림 시 배경 톤 (기존 설정 카드 hover 패턴 정합).
@MainActor
private struct _GroupHeaderButton: View {
    let titleKey: String
    @Binding var expanded: Bool
    @State private var isHovered = false

    var body: some View {
        Button(action: { expanded.toggle() }) {
            HStack(spacing: 7) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.labelSecondary)
                    .frame(width: 9)
                Text(L10n(titleKey))
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.labelPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? DesignTokens.Colors.settingsCardBgHover : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - TASK-065 hover-aware sub-views

@MainActor
private struct _ResetShortcutItemButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(L10n("shortcuts.resetItem"))
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.accent.opacity(isHovered ? 1.0 : 0.70))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }
}
