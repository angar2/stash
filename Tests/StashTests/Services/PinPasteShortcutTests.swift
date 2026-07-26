// Pin 직접 paste 단축키 + 핀 명칭/값 편집 — 순수 계층 + 저장 계층 단위 테스트 (TASK-098)
//
// **본 스위트 통과 = 기능 동작 아님.** 전역 hotkey 등록 · 다른 앱 대상 붙여넣기 · 화면 표시는
// 단위 테스트로 검증할 수 없다 (task Test Plan #15~#28 실기 검수가 유일한 근거).
// 여기서 지키는 것은 *순번 변환 · 기본 조합 · 대상 판정 · 표시 문자열 · 입력 정규화 · 저장 규칙* 뿐이다.
import Testing
import Foundation
import AppKit
@testable import stash

@Suite("Pin 직접 paste 단축키 순수 계층 (TASK-098)")
struct PinPasteShortcutResolverTests {

    // MARK: - 순번 변환 (Test Plan #1)

    /// 순번을 배열 index 로 바꾸는 helper(`pinIndex`)는 검수 정정에서 폐기했다 — 순번은 *자리 번호* 라
    /// 배열 위치와 무관하기 때문이다. 여기서는 식별자 ↔ 순번 규약만 지킨다.
    @Test("식별자 → Pin 순번 (Pin 항목이 아니면 nil)")
    func pinOrdinalMapping() {
        #expect(PopoverShortcutID.pinPaste1.pinOrdinal == 1)
        #expect(PopoverShortcutID.pinPaste2.pinOrdinal == 2)
        #expect(PopoverShortcutID.pinPaste10.pinOrdinal == 10)
        // Pin 직접 paste 가 아닌 식별자는 nil
        #expect(PopoverShortcutID.copy.pinOrdinal == nil)
        #expect(PopoverShortcutID.popoverOpen.pinOrdinal == nil)
    }

    @Test("순번 → 식별자 (범위 밖은 nil)")
    func shortcutIDForOrdinal() {
        #expect(PinPasteShortcutResolver.shortcutID(forPinOrdinal: 1) == .pinPaste1)
        #expect(PinPasteShortcutResolver.shortcutID(forPinOrdinal: 10) == .pinPaste10)
        #expect(PinPasteShortcutResolver.shortcutID(forPinOrdinal: 0) == nil)
        #expect(PinPasteShortcutResolver.shortcutID(forPinOrdinal: 11) == nil)
    }

    @Test("pinPasteIDs 는 순번 오름차순 10종")
    func pinPasteIDsOrdered() {
        let ids = PopoverShortcutID.pinPasteIDs
        #expect(ids.count == Constants.maxPinnedClips)
        #expect(ids.map(\.pinOrdinal) == Array(1...Constants.maxPinnedClips))
    }

    // MARK: - 기본 조합 (Test Plan #2)

    @Test("기본 조합 = ⌥⌘ + 숫자, keyCode 표 정확 일치")
    func defaultShortcutTable() {
        // 숫자 keyCode 는 순차가 아니다 — 5·6 이 23·22 로 뒤집혀 있고 7·8·9 는 26·28·25.
        // `18 + n` 산술로 만들면 5·6 번이 서로 바뀌므로 표 자체를 고정 검증한다.
        let expected: [Int: UInt16] = [1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25, 10: 29]
        for (ordinal, keyCode) in expected {
            let shortcut = PinPasteShortcutResolver.defaultShortcut(forPinOrdinal: ordinal)
            #expect(shortcut?.keyCode == keyCode, "Pin \(ordinal)번 keyCode 불일치")
            #expect(shortcut?.modifiers == [.command, .option], "Pin \(ordinal)번 modifier 는 ⌥⌘ 여야 함")
        }
        #expect(PinPasteShortcutResolver.defaultShortcut(forPinOrdinal: 11) == nil)
    }

    @Test("기본값이 ⌘+숫자가 아니다 — 다른 앱 숫자 단축키 보호")
    func defaultsAvoidPlainCommandDigits() {
        for ordinal in 1...Constants.maxPinnedClips {
            let mods = PinPasteShortcutResolver.defaultShortcut(forPinOrdinal: ordinal)?.modifiers
            #expect(mods?.contains(.option) == true, "Pin \(ordinal)번 기본값에 ⌥ 가 빠지면 ⌘+숫자가 되어 Xcode·브라우저·Finder 단축키를 가로챈다")
        }
    }

    @Test("PopoverShortcutStore.defaults 에 Pin 10종이 모두 등록됨")
    func storeDefaultsContainPinEntries() {
        for id in PopoverShortcutID.pinPasteIDs {
            let def = PopoverShortcutStore.defaults[id]
            #expect(def != nil, "\(id.rawValue) default 누락")
            #expect(def?.modifiers == [.command, .option])
        }
    }

    @Test("Pin 10종은 전역 등록 대상 — 매 실행 강제 초기화 루프에서 제외된다")
    func pinShortcutsUseGlobalRegistration() {
        for id in PopoverShortcutID.pinPasteIDs {
            #expect(id.globalName != nil, "\(id.rawValue) 가 전역 등록 대상이 아니면 어디서나 동작하지 않는다")
        }
        // 강제 초기화 루프 조건(`globalName == nil`)에 걸리는 것은 popover 안 6종뿐이어야 한다.
        let resetTargets = PopoverShortcutID.allCases.filter { $0.globalName == nil }
        #expect(resetTargets.count == 6)
        #expect(resetTargets.allSatisfy { $0.pinOrdinal == nil })
    }

    // MARK: - 대상 판정 (Test Plan #3)

    @Test("빈 자리 순번은 대상 없음")
    func resolveTargetOutOfRange() {
        // 1·2·3번 자리가 찬 상태에서 7번은 빈 자리 → 무동작.
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 7, slots: [1, 2, 3]) == nil)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 1, slots: []) == nil)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 11, slots: [1, 2, 3]) == nil)
        // **핵심 회귀 방어** — 2번을 해제해 자리가 빈 상태(1·3·4)에서 2번 조합은 아무 것도 붙이지 않는다.
        // 이전 구조(`ordinal - 1` 을 배열 index 로 사용)에서는 3번 핀이 붙어버렸다.
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 2, slots: [1, 3, 4]) == nil)
    }

    @Test("찬 자리 순번은 그 자리 핀의 배열 index 반환 — 앞자리가 비어도 대상이 바뀌지 않는다")
    func resolveTargetInRange() {
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 3, slots: [1, 2, 3]) == 2)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 1, slots: [1]) == 0)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 10, slots: Array(1...10)) == 9)
        // 2번 자리가 빈 목록(1·3·4)에서 3번 조합은 *배열 index 1* 의 항목 = 3번 자리 핀.
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 3, slots: [1, 3, 4]) == 1)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 4, slots: [1, 3, 4]) == 2)
        // 1·2번만 남기고 앞을 비운 경우 (3·7번 자리만 사용)
        #expect(PinPasteShortcutResolver.resolvePinTargetIndex(ordinal: 7, slots: [3, 7]) == 1)
    }

    @Test("새 핀 자리 배정 — 가장 낮은 빈 자리 / 꽉 차면 없음")
    func lowestFreeSlotAssignment() {
        #expect(PinPasteShortcutResolver.lowestFreeSlot(occupied: []) == 1)
        #expect(PinPasteShortcutResolver.lowestFreeSlot(occupied: [1, 2, 3]) == 4)
        // 중간이 빈 상태면 **그 빈 자리를 먼저 채운다** (뒤에 붙이지 않는다).
        #expect(PinPasteShortcutResolver.lowestFreeSlot(occupied: [1, 3, 4]) == 2)
        #expect(PinPasteShortcutResolver.lowestFreeSlot(occupied: Array(1...Constants.maxPinnedClips)) == nil)
        // 자리 없는 옛 데이터(nil)는 점유로 치지 않는다.
        #expect(PinPasteShortcutResolver.lowestFreeSlot(occupied: [nil, nil]) == 1)
    }

    // MARK: - 표시 문자열 (Test Plan #4·#5)

    @Test("키캡 문자열 — 지정 조합 없으면 nil")
    func keycapText() {
        // 표시 순서는 macOS 표준 `⌃⌥⇧⌘` — [.command, .shift] 는 "⇧⌘K" 로 렌더된다 (기존 displayText 규약).
        let custom = PopoverShortcut(keyCode: 40, modifiers: [.command, .shift])
        #expect(PinPasteShortcutResolver.keycapText(for: custom) == "⇧⌘K")
        #expect(PinPasteShortcutResolver.keycapText(for: nil) == nil)
        // Pin 3번 기본 조합은 ⌥⌘3
        #expect(PinPasteShortcutResolver.keycapText(for: PinPasteShortcutResolver.defaultShortcut(forPinOrdinal: 3)) == "⌥⌘3")
    }

    @Test("사용자 변경 조합 판정 — 키캡 색 분기 기준")
    func customizedDetection() {
        let def3 = PinPasteShortcutResolver.defaultShortcut(forPinOrdinal: 3)
        #expect(PinPasteShortcutResolver.isCustomized(shortcut: def3, pinOrdinal: 3) == false)
        let custom = PopoverShortcut(keyCode: 40, modifiers: [.command, .shift])
        #expect(PinPasteShortcutResolver.isCustomized(shortcut: custom, pinOrdinal: 3) == true)
        #expect(PinPasteShortcutResolver.isCustomized(shortcut: nil, pinOrdinal: 3) == false)
    }

    // 명칭 우선 표시(`displayTitle`)는 폐기 — 화면이 *명칭이냐 값이냐* 에 따라 서체·색을 달리 그리므로
    // 문자열 하나로 합치는 helper 를 쓰지 않는다. 그 분기 근거인 `normalizeAlias` 는 바로 아래에서 검증한다.

    // MARK: - 입력 정규화 (Test Plan #6·#8)

    @Test("명칭 정규화 — 공백만·빈 문자는 해제, 상한 초과는 절단")
    func normalizeAlias() {
        #expect(PinPasteShortcutResolver.normalizeAlias("  ") == nil)
        #expect(PinPasteShortcutResolver.normalizeAlias("") == nil)
        #expect(PinPasteShortcutResolver.normalizeAlias(nil) == nil)
        #expect(PinPasteShortcutResolver.normalizeAlias("  회의록 템플릿  ") == "회의록 템플릿")

        let over = String(repeating: "가", count: Constants.pinAliasMaxLength + 1)
        #expect(PinPasteShortcutResolver.normalizeAlias(over)?.count == Constants.pinAliasMaxLength)

        let exact = String(repeating: "나", count: Constants.pinAliasMaxLength)
        #expect(PinPasteShortcutResolver.normalizeAlias(exact) == exact)
    }

    @Test("값 편집 허용 — 텍스트만")
    func valueEditableByType() {
        #expect(PinPasteShortcutResolver.isValueEditable(type: .text) == true)
        #expect(PinPasteShortcutResolver.isValueEditable(type: .image) == false)
        #expect(PinPasteShortcutResolver.isValueEditable(type: .file) == false)
    }

    @Test("값 정규화 — 빈 값 거부 / 통과분은 원문 보존 (앞뒤 공백·개행 유지)")
    func normalizeValue() {
        #expect(PinPasteShortcutResolver.normalizeValue("") == nil)
        #expect(PinPasteShortcutResolver.normalizeValue("   ") == nil)
        #expect(PinPasteShortcutResolver.normalizeValue("\n\n") == nil)
        #expect(PinPasteShortcutResolver.normalizeValue(nil) == nil)
        // 들여쓰기·개행이 의미를 갖는 본문이 많아 절단·trim 하지 않는다.
        let raw = "  1. 버전 bump\n  2. 서명 검증\n"
        #expect(PinPasteShortcutResolver.normalizeValue(raw) == raw)
    }

    // MARK: - 검증 단계 회귀 방어 (2026-07-27)

    @Test("설정 PIN 행 타입 아이콘 — 이미지가 텍스트 아이콘으로 새지 않는다")
    func typeSymbolCoversEveryType() {
        // 이 분기를 빼먹으면 이미지 핀이 `text.alignleft` (텍스트 아이콘)으로 표시된다 — 검증에서 실제로 발견된 결함.
        #expect(PinPasteShortcutResolver.typeSymbol(type: .image, isMultiFile: false) == "photo")
        #expect(PinPasteShortcutResolver.typeSymbol(type: .text, isMultiFile: false) == "text.alignleft")
        #expect(PinPasteShortcutResolver.typeSymbol(type: .file, isMultiFile: false) == "doc")
        #expect(PinPasteShortcutResolver.typeSymbol(type: .file, isMultiFile: true) == "doc.on.doc")
        // 타입별로 서로 다른 심볼이어야 구분이 성립한다.
        let symbols = Set([
            PinPasteShortcutResolver.typeSymbol(type: .image, isMultiFile: false),
            PinPasteShortcutResolver.typeSymbol(type: .text, isMultiFile: false),
            PinPasteShortcutResolver.typeSymbol(type: .file, isMultiFile: false)
        ])
        #expect(symbols.count == 3)
    }

    @Test("중복 조합 안내 라벨 — Pin 항목은 순번까지 알려준다")
    func conflictLabelIncludesPinOrdinal() {
        // Pin 10종은 `labelKey` 가 모두 같아서 순번이 없으면 어느 번호와 겹쳤는지 알 수 없다.
        let base = L10n("shortcuts.pinPaste")
        #expect(PopoverShortcutID.pinPaste3.conflictLabel == "\(base) 3")
        #expect(PopoverShortcutID.pinPaste10.conflictLabel == "\(base) 10")
        // 기본 7종은 라벨 그대로 (순번 없음).
        #expect(PopoverShortcutID.copy.conflictLabel == L10n("shortcuts.copy"))
        // 10종 라벨이 서로 전부 달라야 구분이 성립한다.
        #expect(Set(PopoverShortcutID.pinPasteIDs.map(\.conflictLabel)).count == Constants.maxPinnedClips)
    }
}

// MARK: - 클립 표시 라벨 단일 소스 (검증 단계 2026-07-27)

@MainActor
@Suite("클립 표시 라벨 — 목록·설정 공통 규칙 (TASK-098)")
struct ClipDisplayLabelTests {

    private func clip(type: ClipType, body: String?, originalPath: String? = nil, filePath: String? = nil, filePathsJson: String? = nil) -> Clip {
        Clip(
            id: UUID(), type: type, body: body,
            filePath: filePath, isFileExternal: false, fileOriginalPath: originalPath,
            fileBookmark: nil, sourceAppBundleId: nil, isPinned: true,
            createdAt: Date(), lastUsedAt: Date(), pinnedAt: Date(),
            filePathsJson: filePathsJson
        )
    }

    @Test("이미지 클립 — 내부 저장 파일명이 노출되지 않는다")
    func imageLabelNeverLeaksInternalFileName() {
        // 설정 PIN 행이 자체 구현을 갖고 있을 때 스크린샷 핀에 `A1B2-….png` 같은 내부 UUID 파일명이 나왔다.
        let screenshot = clip(type: .image, body: nil, filePath: "/tmp/stash/9E7C4F21-0AAB.png")
        #expect(ClipRowView.displayLabel(for: screenshot) == L10n("clip.row.image"))
        // Finder 이미지는 원본 파일명 (TASK-023 규칙 유지).
        let fromFinder = clip(type: .image, body: nil, originalPath: "/Users/me/Pictures/logo.png", filePath: "/tmp/stash/x.png")
        #expect(ClipRowView.displayLabel(for: fromFinder) == "logo.png")
    }

    @Test("다중 파일 묶음 — 첫 파일명이 아니라 묶음 라벨")
    func multiFileLabel() {
        let multi = clip(
            type: .file, body: nil,
            filePathsJson: #"[{"path":"/a/one.txt","originalPath":"/a/one.txt"},{"path":"/a/two.txt","originalPath":"/a/two.txt"}]"#
        )
        #expect(multi.isMultiFile)
        #expect(ClipRowView.displayLabel(for: multi) == L10n("clip.row.multiFile.label"))
    }

    @Test("단일 파일 / 텍스트 — 파일명과 본문 원문")
    func fileAndTextLabel() {
        let file = clip(type: .file, body: nil, originalPath: "/Users/me/Desktop/report.pdf", filePath: "/tmp/stash/y.pdf")
        #expect(ClipRowView.displayLabel(for: file) == "report.pdf")
        // 텍스트는 *원문 그대로* 반환하고 줄 처리는 호출처가 한다 (행=첫 줄 / 설정 행=개행 접기).
        let text = clip(type: .text, body: "첫 줄\n둘째 줄")
        #expect(ClipRowView.displayLabel(for: text) == "첫 줄\n둘째 줄")
    }
}

// MARK: - 핀 순번 안정화 + 명칭/값 저장 (Test Plan #3-b·#10·#11)

@MainActor
@Suite("핀 순번 정렬 + 명칭/값 저장 (TASK-098)", .serialized)
struct PinAliasAndOrderTests {

    private func makeClip(body: String, pinned: Bool, pinnedAt: Date?, type: ClipType = .text, slot: Int? = nil) -> Clip {
        Clip(
            id: UUID(),
            type: type,
            body: body,
            filePath: type == .text ? nil : "/tmp/x.png",
            isFileExternal: false,
            fileOriginalPath: nil,
            fileBookmark: nil,
            sourceAppBundleId: nil,
            isPinned: pinned,
            createdAt: Date(timeIntervalSince1970: 0),
            lastUsedAt: Date(timeIntervalSince1970: 0),
            pinnedAt: pinnedAt,
            pinSlot: pinned ? slot : nil
        )
    }

    /// 자리(`pin_slot`)가 지정되지 않은 핀 픽스처에 **V7 마이그레이션과 같은 규칙**으로 1..N 을 배정한다
    /// (표시 순서 = `pinned_at` 오름차순, NULL 은 `created_at`). 실제 앱에는 자리 없는 핀이 존재하지 않으므로
    /// 픽스처도 마이그레이션 이후 상태를 재현해야 한다.
    private func backfillSlots(_ clips: [Clip]) -> [Clip] {
        let pinnedOrder = clips.filter(\.isPinned)
            .sorted { ($0.pinnedAt ?? $0.createdAt) < ($1.pinnedAt ?? $1.createdAt) }
        var taken = Set(pinnedOrder.compactMap(\.pinSlot))
        var assigned: [UUID: Int] = [:]
        var cursor = 1
        for clip in pinnedOrder where clip.pinSlot == nil {
            while taken.contains(cursor) { cursor += 1 }
            assigned[clip.id] = cursor
            taken.insert(cursor)
        }
        return clips.map { clip in
            guard let slot = assigned[clip.id] else { return clip }
            var copy = clip
            copy.pinSlot = slot
            return copy
        }
    }

    private func makeViewModel(prefilled: [Clip]) async -> (ClipsViewModel, InMemoryClipRepository) {
        let repo = InMemoryClipRepository()
        for clip in backfillSlots(prefilled) { _ = try? await repo.insert(clip) }
        let checker = MockPermissionChecker()
        checker.trusted = true
        let permSvc = PermissionService(checker: checker)
        let pasteSvc = PasteService(
            synthesizer: MockPasteSynthesizer(),
            pasteboard: MockPasteboard(),
            repository: repo,
            permissionService: permSvc
        )
        let vm = ClipsViewModel(repository: repo, pasteService: pasteSvc, fileClipService: MockFileClipService())
        await vm.reload()
        return (vm, repo)
    }

    @Test("핀 목록 정렬 = 먼저 핀한 것이 1번 (pinned_at 오름차순)")
    func pinnedClipsAscending() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let first = makeClip(body: "먼저", pinned: true, pinnedAt: t0)
        let second = makeClip(body: "나중", pinned: true, pinnedAt: t0.addingTimeInterval(60))
        let third = makeClip(body: "제일 나중", pinned: true, pinnedAt: t0.addingTimeInterval(120))
        let (vm, _) = await makeViewModel(prefilled: [third, first, second])

        #expect(vm.pinnedClips.map(\.body) == ["먼저", "나중", "제일 나중"])
    }

    @Test("새로 핀해도 기존 순번이 밀리지 않는다 — 맨 아래에 추가")
    func newPinAppendsToEnd() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = makeClip(body: "A", pinned: true, pinnedAt: t0)
        let b = makeClip(body: "B", pinned: true, pinnedAt: t0.addingTimeInterval(60))
        let fresh = makeClip(body: "새 항목", pinned: false, pinnedAt: nil)
        let (vm, _) = await makeViewModel(prefilled: [a, b, fresh])

        let before = vm.pinnedClips.map(\.body)
        #expect(before == ["A", "B"])

        await vm.togglePin(id: fresh.id)

        // 1·2번이 가리키는 대상이 그대로여야 조합을 외울 수 있다.
        #expect(vm.pinnedClips.map(\.body) == ["A", "B", "새 항목"])
        #expect(vm.pinnedClips.first?.body == "A")
    }

    @Test("pinnedAt 이 nil 인 옛 행도 같은 방향(오름차순)으로 정렬")
    func nilPinnedAtFallsBackAscending() async {
        var old = makeClip(body: "옛 핀", pinned: true, pinnedAt: nil)
        old = Clip(
            id: old.id, type: .text, body: "옛 핀", filePath: nil, isFileExternal: false,
            fileOriginalPath: nil, fileBookmark: nil, sourceAppBundleId: nil, isPinned: true,
            createdAt: Date(timeIntervalSince1970: 500), lastUsedAt: Date(timeIntervalSince1970: 500),
            pinnedAt: nil
        )
        let newer = makeClip(body: "새 핀", pinned: true, pinnedAt: Date(timeIntervalSince1970: 2_000))
        let (vm, _) = await makeViewModel(prefilled: [newer, old])

        #expect(vm.pinnedClips.map(\.body) == ["옛 핀", "새 핀"])
    }

    @Test("명칭 저장 → 조회 → 빈 문자로 해제")
    func aliasSetAndClear() async {
        let clip = makeClip(body: "Bearer abc", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1))
        let (vm, _) = await makeViewModel(prefilled: [clip])

        await vm.setPinAlias(id: clip.id, rawAlias: "  인증 헤더 ")
        #expect(vm.pinnedClips.first?.pinAlias == "인증 헤더")

        await vm.setPinAlias(id: clip.id, rawAlias: "   ")
        #expect(vm.pinnedClips.first?.pinAlias == nil)
    }

    /// 검수 정정(2026-07-27) — 이전 정책은 *해제 후에도 명칭 보존* 이었다. 사용자 결정으로 **해제 시 초기화** 로 뒤집었다.
    /// 사유: 명칭은 핀에만 있는 개념이라, 남겨두면 한참 뒤 재고정 시 잊고 있던 옛 이름이 되살아난다.
    @Test("명칭은 핀 해제 시 초기화된다 — 재고정해도 되살아나지 않는다")
    func aliasClearedOnUnpin() async {
        let clip = makeClip(body: "템플릿", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1))
        let (vm, _) = await makeViewModel(prefilled: [clip])
        await vm.setPinAlias(id: clip.id, rawAlias: "회의록 템플릿")
        #expect(vm.pinnedClips.first?.pinAlias == "회의록 템플릿")

        await vm.togglePin(id: clip.id)   // unpin — 여기서 명칭이 지워진다
        #expect(vm.clips.first { $0.id == clip.id }?.pinAlias == nil)

        await vm.togglePin(id: clip.id)   // 재고정 — 빈 명칭으로 시작
        #expect(vm.pinnedClips.first?.pinAlias == nil)
        // 값(body)은 핀 상태와 무관하게 유지된다 — 초기화 대상은 명칭뿐이다.
        #expect(vm.pinnedClips.first?.body == "템플릿")
    }

    @Test("값 수정 — 텍스트만 반영 / last_used_at 미변경")
    func updateBodyTextOnly() async {
        let clip = makeClip(body: "before", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1))
        let (vm, _) = await makeViewModel(prefilled: [clip])
        let before = vm.pinnedClips.first?.lastUsedAt

        let applied = await vm.updateClipBody(id: clip.id, rawBody: "after\n두 번째 줄")
        #expect(applied == true)
        #expect(vm.pinnedClips.first?.body == "after\n두 번째 줄")
        // 수정은 사용이 아니다 — 히스토리 최근사용순 정렬이 흔들리면 안 된다.
        #expect(vm.pinnedClips.first?.lastUsedAt == before)
    }

    /// **검증 회귀 방어** — 값만 고쳤는데 *자리와 명칭이 날아가면* 그 핀의 번호·조합이 통째로 바뀐다.
    /// 프로덕션은 `UPDATE clips SET body = ?` 단일 컬럼이라 구조적으로 안전하지만,
    /// 다른 컬럼을 함께 쓰는 구현으로 되돌아가는 순간 조용히 깨지는 자리라 값으로 못 박는다.
    @Test("값 수정 — 자리·명칭·핀 상태는 그대로 유지된다")
    func updateBodyKeepsSlotAndAlias() async {
        let a = makeClip(body: "A", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1_000), slot: 1)
        let b = makeClip(body: "B", pinned: true, pinnedAt: Date(timeIntervalSince1970: 2_000), slot: 3)
        let (vm, _) = await makeViewModel(prefilled: [a, b])
        await vm.setPinAlias(id: b.id, rawAlias: "세 번째")

        #expect(await vm.updateClipBody(id: b.id, rawBody: "B 수정본") == true)

        let after = vm.pinnedClips.first { $0.id == b.id }
        #expect(after?.body == "B 수정본")
        #expect(after?.pinSlot == 3)          // 자리 유지 — 조합 `⌥⌘3` 이 계속 이 항목을 가리킨다
        #expect(after?.pinAlias == "세 번째")  // 명칭 유지 (초기화는 *핀 해제* 때만)
        #expect(after?.isPinned == true)
        #expect(vm.pinnedClips.map(\.pinSlot) == [1, 3])
    }

    // MARK: - 빈 순번에서 새 핀 만들기 (fix-3)

    @Test("빈 순번에 값 입력 → **클릭한 그 자리**에 새 핀 생성 (명칭 함께 저장)")
    func createPinnedClipFromEmptySlot() async {
        let existing = makeClip(body: "A", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1_000))
        let (vm, _) = await makeViewModel(prefilled: [existing])
        #expect(vm.pinnedClips.count == 1)

        // 사용자가 **5번 행** 을 클릭해 만들었으면 5번 자리에 꽂힌다 (검수 정정 — 자리 개념 도입으로 해소).
        let created = await vm.createPinnedClip(body: "새 핀 본문", alias: "  내 템플릿 ", slot: 5)
        #expect(created == true)
        #expect(vm.pinnedClips.count == 2)
        #expect(vm.pinnedClip(atSlot: 5)?.body == "새 핀 본문")
        #expect(vm.pinnedClip(atSlot: 5)?.pinAlias == "내 템플릿")
        // 사이드바는 빈 자리를 건너뛰어 나열한다 — 1 다음에 5.
        #expect(vm.pinnedClips.map(\.pinSlot) == [1, 5])
        #expect(vm.pinnedClip(atSlot: 2) == nil)
    }

    /// **검증 회귀 방어** — 수집 dedup 정책(V2)상 같은 본문은 한 row 뿐이라, 이미 고정된 내용을 다른 번호에
    /// 또 만들 수는 없다. 이때 조용히 성공을 반환하면 *요청한 자리는 빈 채로 남는데 다른 자리 핀의 명칭만* 바뀐다.
    @Test("같은 본문이 이미 다른 자리에 고정돼 있으면 새 핀을 만들지 않는다 (그 핀의 명칭도 건드리지 않음)")
    func createPinnedClipRejectsAlreadyPinnedBody() async {
        let existing = makeClip(body: "공용 서명", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1_000), slot: 2)
        let (vm, _) = await makeViewModel(prefilled: [existing])
        await vm.setPinAlias(id: existing.id, rawAlias: "서명")

        #expect(await vm.createPinnedClip(body: "공용 서명", alias: "다른 이름", slot: 7) == false)

        #expect(vm.pinnedClips.count == 1)
        #expect(vm.pinnedClip(atSlot: 7) == nil)               // 요청 자리는 비어 있다
        #expect(vm.pinnedClip(atSlot: 2)?.pinAlias == "서명")   // 기존 핀의 명칭이 덮이지 않는다
    }

    @Test("이미 찬 자리를 요청하면 가장 낮은 빈 자리로 대체된다")
    func createPinnedClipFallsBackWhenSlotTaken() async {
        let existing = makeClip(body: "A", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1_000), slot: 3)
        let (vm, _) = await makeViewModel(prefilled: [existing])

        #expect(await vm.createPinnedClip(body: "새 핀", alias: nil, slot: 3) == true)
        // 3번은 A 가 쓰고 있으므로 새 핀은 1번(가장 낮은 빈 자리)으로.
        #expect(vm.pinnedClip(atSlot: 3)?.body == "A")
        #expect(vm.pinnedClip(atSlot: 1)?.body == "새 핀")
    }

    @Test("빈 값으로는 새 핀이 만들어지지 않는다")
    func createPinnedClipRejectsEmpty() async {
        let (vm, _) = await makeViewModel(prefilled: [])
        #expect(await vm.createPinnedClip(body: "   ", alias: "이름만") == false)
        #expect(await vm.createPinnedClip(body: "", alias: nil) == false)
        #expect(vm.pinnedClips.isEmpty)
    }

    @Test("이미 히스토리에 있는 본문이면 그 행이 핀 처리된다 (dedup 정책 수습)")
    func createPinnedClipReusesExistingBody() async {
        // 핀 아닌 기존 클립과 같은 본문 — 수집 dedup 상 새 row 가 생기지 않는 케이스.
        let unpinned = makeClip(body: "중복 본문", pinned: false, pinnedAt: nil)
        let (vm, _) = await makeViewModel(prefilled: [unpinned])

        let created = await vm.createPinnedClip(body: "중복 본문", alias: "재사용")
        #expect(created == true)
        #expect(vm.pinnedClips.count == 1)
        #expect(vm.pinnedClips.first?.id == unpinned.id)   // 새 row 가 아니라 기존 row
        #expect(vm.pinnedClips.first?.pinAlias == "재사용")
    }

    @Test("핀 한도(10) 도달 시 새 핀 생성 거부")
    func createPinnedClipRespectsLimit() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let full = (0..<Constants.maxPinnedClips).map {
            makeClip(body: "pin-\($0)", pinned: true, pinnedAt: t0.addingTimeInterval(Double($0)))
        }
        let (vm, _) = await makeViewModel(prefilled: full)
        #expect(vm.pinnedClips.count == Constants.maxPinnedClips)

        #expect(await vm.createPinnedClip(body: "11번째", alias: nil) == false)
        #expect(vm.pinnedClips.count == Constants.maxPinnedClips)
    }

    // MARK: - 설정에서 핀 해제 (Phase 9)

    /// **검수 정정 회귀 방어** — 이전 구조(배열 위치 = 번호)에서는 2번을 해제하면 3·4번이 2·3번으로 당겨지고
    /// 조합까지 바뀌었다. 자리(`pin_slot`)를 데이터로 가진 뒤로는 *해제한 자리만* 빈다.
    @Test("핀 해제 — 뒤 순번이 당겨지지 않는다. 해제한 자리만 빈다")
    func unpinKeepsFollowingSlots() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = makeClip(body: "A", pinned: true, pinnedAt: t0)
        let b = makeClip(body: "B", pinned: true, pinnedAt: t0.addingTimeInterval(60))
        let c = makeClip(body: "C", pinned: true, pinnedAt: t0.addingTimeInterval(120))
        let d = makeClip(body: "D", pinned: true, pinnedAt: t0.addingTimeInterval(180))
        let (vm, _) = await makeViewModel(prefilled: [a, b, c, d])
        #expect(vm.pinnedClips.map(\.pinSlot) == [1, 2, 3, 4])

        await vm.unpinFromSettings(id: b.id)

        // 목록에서는 2번이 빠지지만 **C·D 는 자기 번호(3·4)를 그대로 유지**한다.
        #expect(vm.pinnedClips.map(\.body) == ["A", "C", "D"])
        #expect(vm.pinnedClips.map(\.pinSlot) == [1, 3, 4])
        // 2번 자리는 비어 있다 → 그 조합은 무동작.
        #expect(vm.pinnedClip(atSlot: 2) == nil)
        #expect(vm.pinnedClip(atSlot: 3)?.body == "C")
        // 클립 자체는 지우지 않는다 — 히스토리에 남고 자리만 비운다.
        #expect(vm.clips.contains { $0.id == b.id })
        #expect(vm.clips.first { $0.id == b.id }?.isPinned == false)
        #expect(vm.clips.first { $0.id == b.id }?.pinSlot == nil)
    }

    @Test("빈 자리는 다음 핀이 채운다 — 뒤에 붙지 않는다")
    func newPinFillsTheGap() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = makeClip(body: "A", pinned: true, pinnedAt: t0)
        let b = makeClip(body: "B", pinned: true, pinnedAt: t0.addingTimeInterval(60))
        let c = makeClip(body: "C", pinned: true, pinnedAt: t0.addingTimeInterval(120))
        let fresh = makeClip(body: "새 항목", pinned: false, pinnedAt: nil)
        let (vm, _) = await makeViewModel(prefilled: [a, b, c, fresh])

        await vm.unpinFromSettings(id: b.id)   // 2번 자리를 비운다
        await vm.togglePin(id: fresh.id)       // 새 핀 → 가장 낮은 빈 자리 = 2번

        #expect(vm.pinnedClip(atSlot: 2)?.body == "새 항목")
        #expect(vm.pinnedClip(atSlot: 3)?.body == "C")   // C 는 여전히 3번
        #expect(vm.pinnedClips.map(\.pinSlot) == [1, 2, 3])
    }

    @Test("설정에서 핀 해제 — 명칭이 초기화되고 값은 유지된다")
    func unpinFromSettingsClearsAlias() async {
        let clip = makeClip(body: "Bearer abc", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1_000))
        let (vm, _) = await makeViewModel(prefilled: [clip])
        await vm.setPinAlias(id: clip.id, rawAlias: "인증 헤더")
        #expect(vm.pinnedClips.first?.pinAlias == "인증 헤더")

        await vm.unpinFromSettings(id: clip.id)
        #expect(vm.pinnedClips.isEmpty)
        // 클립은 히스토리에 남지만 **명칭은 지워진다** (검수 정정 — 재고정 시 옛 이름 부활 방지).
        let after = vm.clips.first { $0.id == clip.id }
        #expect(after?.pinAlias == nil)
        #expect(after?.body == "Bearer abc")

        // 다시 고정해도 명칭은 빈 상태로 시작한다.
        await vm.togglePin(id: clip.id)
        #expect(vm.pinnedClips.first?.pinAlias == nil)
    }

    @Test("설정에서 마지막 핀을 해제하면 popover 사이드바가 닫힌다")
    func unpinFromSettingsClosesSidebarOnLastPin() async {
        let t0 = Date(timeIntervalSince1970: 1_000)
        let a = makeClip(body: "A", pinned: true, pinnedAt: t0)
        let b = makeClip(body: "B", pinned: true, pinnedAt: t0.addingTimeInterval(60))
        let (vm, _) = await makeViewModel(prefilled: [a, b])
        vm.pinSidebarOpen = true
        vm.pinSelectedIdx = 1

        // 아직 핀이 남아 있으면 사이드바는 열린 채 선택 idx 만 clamp.
        await vm.unpinFromSettings(id: b.id)
        #expect(vm.pinSidebarOpen == true)
        #expect(vm.pinSelectedIdx == 0)

        // 마지막 핀을 설정에서 해제해도 사이드바가 빈 채로 남으면 안 된다.
        await vm.unpinFromSettings(id: a.id)
        #expect(vm.pinnedClips.isEmpty)
        #expect(vm.pinSidebarOpen == false)
    }

    @Test("값 수정 거부 — 빈 값 / 텍스트 아닌 타입")
    func updateBodyRejected() async {
        let text = makeClip(body: "keep", pinned: true, pinnedAt: Date(timeIntervalSince1970: 1))
        let image = makeClip(body: nil ?? "", pinned: true, pinnedAt: Date(timeIntervalSince1970: 2), type: .image)
        let (vm, _) = await makeViewModel(prefilled: [text, image])

        let emptyResult = await vm.updateClipBody(id: text.id, rawBody: "   ")
        #expect(emptyResult == false)
        #expect(vm.pinnedClips.first(where: { $0.id == text.id })?.body == "keep")

        let imageResult = await vm.updateClipBody(id: image.id, rawBody: "새 값")
        #expect(imageResult == false)
    }
}
