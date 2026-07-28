// 다중 선택 붙여넣기의 *순수 계층* (TASK-099).
//
// 선택 상태·페이스트보드 쓰기·⌘V 합성은 화면과 시스템에 묶여 단위 테스트로 검증할 수 없다.
// 그래서 화면·시스템에 의존하지 않는 판정(계열 구분 / 연결자 해석 / 연결 / 프리뷰 문자열 / 파일 URL 수집)만
// 여기로 분리해 테스트 가능하게 둔다 (`PinPasteShortcutResolver` 선례).
// 반대로 *여기 통과 = 기능 동작* 은 아니다 — 실제 붙여넣기·화면은 실기 검수가 유일한 근거다.
import Foundation

/// 선택한 클립들의 계열. 페이스트보드가 *순서 개념 없는 단일 상태* 라는 시스템 제약에서 갈리는 구분이다.
enum MultiPasteCategory: Equatable, Sendable {
    /// 선택 전부가 텍스트 — 연결자로 이어붙여 단일 문자열로 기록한다.
    case text
    /// 선택 전부가 이미지·파일·폴더 — 파일 URL 배열로 한 번에 기록한다.
    case files
    /// 텍스트와 파일이 섞임 — 한 번의 클립보드 상태로 표현할 수 없어 선택 순서대로 연속 합성한다.
    case mixed
}

/// 프리뷰 바 우측 라벨이 무엇을 말해야 하는지. **문자열이 아니라 값** 으로 돌려주는 이유는
/// 이 계층이 `L10n` 을 타면 단위 테스트에서 번들이 달라 결과가 흔들리기 때문이다 — 번역은 화면이 한다.
enum MultiPasteMode: Equatable, Sendable {
    case textJoin
    /// 실제로 붙는 *파일 개수*. 다중 파일 클립 하나가 여러 개로 펼쳐지므로 선택 개수와 다를 수 있다.
    case fileBundle(fileCount: Int)
    /// 혼합 — 텍스트는 이어져 한 덩어리로 붙으므로 개수를 말할 것은 *파일 쪽* 뿐이다.
    case sequential(fileCount: Int)
}

/// 프리뷰 바가 그려야 할 내용 일체.
///
/// 화면은 조각 하나를 **칩 하나** 로 그리고 구분 표기는 칩 *밖* 에 둔다 — 이어붙일 문자가 내용과 섞여 읽히지 않게.
struct MultiPastePreview: Equatable, Sendable {
    /// 칩 하나. 계열을 함께 들고 다니는 이유는 **색이 갈리기** 때문이다 —
    /// 텍스트는 강조 색, 파일·이미지는 키캡과 같은 회색 톤(검수 결정: 붙는 성격이 다른 것을 색으로 구분).
    struct Segment: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case text
            case file
        }
        let text: String
        let kind: Kind
    }

    let category: MultiPasteCategory
    /// 선택한 *클립* 개수 (상단 좌측 `N개 선택`).
    let selectionCount: Int
    let mode: MultiPasteMode
    /// 칩으로 그릴 조각 — **실행 순서 그대로**.
    let segments: [Segment]
    /// 조각 *사이* 구분 표기. 길이는 `max(0, segments.count - 1)` 이며 `separators[i]` 가
    /// `segments[i]` 와 `segments[i+1]` 사이에 놓인다. 빈 문자열이면 아무것도 그리지 않는다
    /// (파일 배열처럼 *이어붙이는 개념이 아닌* 자리, 그리고 연결자를 비워둔 경우).
    let separators: [String]

    /// 조각 본문만 — 검증·로그에서 계열 없이 내용만 볼 때.
    var segmentTexts: [String] {
        segments.map(\.text)
    }

    /// 평문 프리뷰 (조각을 구분 표기로 이은 것) — 로그·테스트용.
    var body: String {
        guard let first = segments.first else { return "" }
        var out = first.text
        for (idx, segment) in segments.dropFirst().enumerated() {
            if separators.indices.contains(idx) { out += separators[idx] }
            out += segment.text
        }
        return out
    }
}

enum MultiPasteComposer {

    // MARK: - 계열 판정

    /// 선택한 클립들의 계열. **빈 선택은 nil** (= 묶음 실행 대상 아님).
    static func category(of clips: [Clip]) -> MultiPasteCategory? {
        guard !clips.isEmpty else { return nil }
        var hasText = false
        var hasFile = false
        for clip in clips {
            if clip.type == .text { hasText = true } else { hasFile = true }
        }
        if hasText && hasFile { return .mixed }
        return hasText ? .text : .files
    }

    // MARK: - 연결자

    /// 설정에 입력된 원문을 실제 연결자로 해석한다. `\n`·`\t` 두 글자 표기만 제어문자로 바꾸고 나머지는 원문 그대로다.
    /// 빈 문자열은 *구분 없이 잇는다* 는 뜻이며 유효한 값이다.
    static func resolveSeparator(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
    }

    /// 연결자의 *시각 표기*. 줄바꿈·탭처럼 눈에 안 보이는 값이 기본값이라, 프리뷰에서 보이지 않으면
    /// 사용자가 무엇으로 이어지는지 확인할 수 없다.
    static func separatorDisplay(_ raw: String) -> String {
        resolveSeparator(raw)
            .replacingOccurrences(of: "\n", with: "⏎")
            .replacingOccurrences(of: "\t", with: "⇥")
    }

    // MARK: - 연결

    /// 텍스트 계열 묶음 결과. 입력 배열 순서가 곧 **선택 순서** 이므로 여기서 재정렬하지 않는다.
    /// - Parameter separator: `resolveSeparator` 를 통과한 *실제* 연결자.
    static func joinedText(clips: [Clip], separator: String) -> String {
        clips.map { $0.body ?? "" }.joined(separator: separator)
    }

    // MARK: - 혼합 실행 순서

    /// 혼합 선택의 **실행 순서** — 파일·이미지를 앞으로 모으고 텍스트를 뒤로 보낸다.
    /// 각 묶음 안에서는 선택 순서를 그대로 지킨다.
    ///
    /// 선택 순서를 그대로 따르지 않는 이유는 *안정성* 이다. 계열이 번갈아 나오면 항목 수만큼 연속 합성해야 하는데
    /// (`이미지 → 텍스트 → 이미지` = 3회), 매 합성마다 붙는 앱이 앞 항목을 처리했기를 기대해야 해서 뒤쪽이 잘 누락된다.
    /// 계열별로 모으면 **파일은 배열 한 번 · 텍스트는 연결해 한 번**, 합성이 2회로 줄어 실패 지점 자체가 줄어든다.
    static func sequentialGroups(clips: [Clip]) -> (files: [Clip], texts: [Clip]) {
        (clips.filter { $0.type != .text }, clips.filter { $0.type == .text })
    }

    // MARK: - 파일 수집

    /// 묶음 붙여넣기에 쓸 파일 URL — **선택 순서** 대로, 다중 파일 클립은 항목 단위로 펼친다.
    /// 경로 우선순위는 `PasteService` 의 단일 클립 규칙과 같다 (원본이 있으면 원본, 없으면 보관 카피본).
    static func fileURLs(clips: [Clip]) -> [URL] {
        clips.flatMap { filePaths(of: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// 한 클립이 품고 있는 파일 경로들. 텍스트 클립은 빈 배열.
    static func filePaths(of clip: Clip) -> [String] {
        guard clip.type != .text else { return [] }
        if clip.isMultiFile, let entries = clip.fileEntries {
            return entries.map { $0.originalPath.isEmpty ? $0.filePath : $0.originalPath }
        }
        guard let path = clip.fileOriginalPath ?? clip.filePath else { return [] }
        return [path]
    }

    /// 파일 계열 클립의 표시용 파일명들 (경로의 마지막 구성요소).
    static func fileNames(of clip: Clip) -> [String] {
        let names = filePaths(of: clip).map { ($0 as NSString).lastPathComponent }
        // 경로가 하나도 없는 비정상 클립(마이그레이션 잔재 등)에서 조각이 통째로 사라지면
        // 프리뷰의 선택 개수와 나열 개수가 어긋난다 — 본문으로라도 한 자리를 채운다.
        return names.isEmpty ? [clip.body ?? ""] : names
    }

    // MARK: - 프리뷰

    /// 프리뷰 바 내용 일체. 빈 선택이면 nil (= 프리뷰 바 미표시).
    /// - Parameter separatorRaw: 설정에 저장된 연결자 **원문** (해석은 내부에서).
    static func preview(clips: [Clip], separatorRaw: String) -> MultiPastePreview? {
        guard let category = category(of: clips) else { return nil }
        switch category {
        case .text:
            let segments = clips.map { MultiPastePreview.Segment(text: $0.body ?? "", kind: .text) }
            return MultiPastePreview(
                category: .text,
                selectionCount: clips.count,
                mode: .textJoin,
                segments: segments,
                // 칩 사이마다 연결자. 연결자를 비워두면 빈 문자열이 되어 칩이 바로 붙는다
                // (= *구분 없이 연결* 이 시각으로 그대로 읽힌다).
                separators: Array(repeating: separatorDisplay(separatorRaw), count: max(0, segments.count - 1))
            )
        case .files:
            let names = clips.flatMap { fileNames(of: $0) }
            return MultiPastePreview(
                category: .files,
                selectionCount: clips.count,
                mode: .fileBundle(fileCount: names.count),
                segments: names.map { MultiPastePreview.Segment(text: $0, kind: .file) },
                // 파일은 배열 하나로 한 번에 붙는다 — *이어붙이는* 개념이 아니라 구분 표기를 두지 않는다.
                separators: Array(repeating: "", count: max(0, names.count - 1))
            )
        case .mixed:
            // 프리뷰는 **실제 실행 순서** 를 보여야 한다 — 선택 순서 그대로 그리면
            // 화면에 보인 것과 다른 순서로 붙어 사용자가 결과를 예측할 수 없다.
            let groups = sequentialGroups(clips: clips)
            let fileNamesInOrder = groups.files.flatMap { fileNames(of: $0) }
            let textBodies = groups.texts.map { $0.body ?? "" }

            var separators = Array(repeating: "", count: max(0, fileNamesInOrder.count - 1))
            if !fileNamesInOrder.isEmpty, !textBodies.isEmpty {
                // 두 묶음이 나뉘어 따로 붙는다는 사실을 경계 기호로 보여준다.
                separators.append(Self.groupBoundaryDisplay)
            }
            separators += Array(repeating: separatorDisplay(separatorRaw), count: max(0, textBodies.count - 1))

            return MultiPastePreview(
                category: .mixed,
                selectionCount: clips.count,
                mode: .sequential(fileCount: fileNamesInOrder.count),
                segments: fileNamesInOrder.map { MultiPastePreview.Segment(text: $0, kind: .file) }
                    + textBodies.map { MultiPastePreview.Segment(text: $0, kind: .text) },
                separators: separators
            )
        }
    }

    /// 혼합에서 *파일 묶음 → 텍스트* 경계 표기.
    static let groupBoundaryDisplay = "→"
}
