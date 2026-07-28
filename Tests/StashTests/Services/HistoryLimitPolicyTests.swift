// 보관 한도 판정 — 순수 계층 단위 테스트 (TASK-100, Test Plan #1~#7)
//
// **본 스위트 통과 = 기능 동작 아님.** 입력란 표시 · 증감 버튼 클릭 · 토스트 발화 · 설정 영속은
// 단위 테스트로 검증할 수 없다 (task Test Plan #10~#15 실기 검수가 유일한 근거).
// 여기서 지키는 것은 *확정 입력 판정 · 증감 clamp · 첫 실행 초기값 · 저장값 → 한도 변환* 뿐이다.
//
// 본 스위트는 UserDefaults 를 읽지도 쓰지도 않는다 — 같은 키를 보는 다른 스위트와 병렬 실행에서
// 서로 간섭하지 않게 하려는 의도적 설계다 (`Constants.maxUnpinnedClips` 는 여기 `storedLimit` 을 부른다).
import Testing
import Foundation
@testable import stash

@Suite("보관 한도 판정 (TASK-100)")
struct HistoryLimitPolicyTests {

    // MARK: - 확정 입력 판정 (Test Plan #1~#5)

    /// 현재 보관 개수보다 작은 값은 거부한다. 되돌릴 값으로 *현재 개수* 를 함께 돌려줘야
    /// 호출부가 입력란을 그 값으로 복원할 수 있다.
    @Test("현재 개수 미만 입력은 거부 + 현재 개수를 되돌릴 값으로 반환")
    func rejectsBelowCurrentCount() {
        #expect(HistoryLimitPolicy.resolve(input: "40", currentUnpinnedCount: 51) == .belowCurrentCount(51))
    }

    @Test("현재 개수보다 큰 값은 수용")
    func acceptsAboveCurrentCount() {
        #expect(HistoryLimitPolicy.resolve(input: "60", currentUnpinnedCount: 51) == .accepted(60))
    }

    /// 경계 — *같은 값* 은 미달이 아니다. 한도와 보관 개수가 같은 상태는 정상이며(가득 찬 상태),
    /// 여기서 거부하면 사용자가 자기 현재 개수로도 못 맞춘다.
    @Test("현재 개수와 같은 값은 수용 (미달 아님)")
    func acceptsExactCurrentCount() {
        #expect(HistoryLimitPolicy.resolve(input: "51", currentUnpinnedCount: 51) == .accepted(51))
    }

    /// 상한 초과는 경고 없이 상한으로 맞춘다 — 미달과 달리 클립이 사라질 위험이 없다.
    @Test("상한 초과 입력은 조용히 500 으로 조정")
    func capsAboveMaximum() {
        #expect(HistoryLimitPolicy.resolve(input: "501", currentUnpinnedCount: 0) == .accepted(500))
        #expect(HistoryLimitPolicy.resolve(input: "9999", currentUnpinnedCount: 0) == .accepted(500))
    }

    /// 자릿수가 많아 `Int` 범위를 넘는 값도 *잘못 친 값* 이 아니라 *너무 큰 값* 이다.
    /// 무효로 되돌리면 20자리를 친 사용자만 상한 조정을 못 받는 앞뒤 안 맞는 동작이 된다.
    @Test("Int 범위를 넘는 숫자 문자열도 상한으로 조정")
    func capsOverflowingNumericInput() {
        #expect(HistoryLimitPolicy.resolve(input: "99999999999999999999", currentUnpinnedCount: 0) == .accepted(500))
    }

    /// 무효 입력은 *토스트 없이* 직전 값 복원이라 되돌릴 값을 싣지 않는다.
    /// (`99999999999999999999abc` 처럼 숫자가 아닌 글자가 섞이면 위 상한 조정 대상이 아니다.)
    @Test("0 · 음수 · 문자 · 빈 값 · 소수는 무효")
    func rejectsInvalidInput() {
        for raw in ["0", "-3", "abc", "", "   ", "3.5", "99999999999999999999abc"] {
            #expect(
                HistoryLimitPolicy.resolve(input: raw, currentUnpinnedCount: 10) == .invalid,
                "무효로 판정돼야 함: \(raw)"
            )
        }
    }

    /// 앞뒤 공백은 사용자가 입력란에서 흔히 남기는 흔적이라 값으로 취급하지 않는다.
    @Test("앞뒤 공백은 무시하고 숫자로 판정")
    func trimsSurroundingWhitespace() {
        #expect(HistoryLimitPolicy.resolve(input: "  120  ", currentUnpinnedCount: 10) == .accepted(120))
    }

    // MARK: - 첫 실행 초기값 (Test Plan #6)

    /// 한도가 200 고정이던 시절의 사용자가 업데이트만으로 클립을 잃지 않게 하는 지점이다.
    /// 보관 개수가 기본값보다 많으면 *보관 개수* 가 초기값이 된다.
    @Test("첫 실행 초기값 = max(기본 50, 현재 보관 개수)")
    func initialValueProtectsExistingClips() {
        #expect(HistoryLimitPolicy.initialValue(currentUnpinnedCount: 200) == 200)
        #expect(HistoryLimitPolicy.initialValue(currentUnpinnedCount: 12) == 50)
        #expect(HistoryLimitPolicy.initialValue(currentUnpinnedCount: 0) == 50)
        #expect(HistoryLimitPolicy.initialValue(currentUnpinnedCount: 50) == 50)
    }

    /// 상한을 넘는 보관 개수(직접 편집 등 비정상 경로)라도 초기값이 상한을 넘지는 않는다.
    @Test("보관 개수가 상한을 넘어도 초기값은 500 이하")
    func initialValueNeverExceedsMaximum() {
        #expect(HistoryLimitPolicy.initialValue(currentUnpinnedCount: 700) == 500)
    }

    // MARK: - 저장값 → 한도 변환 (Test Plan #7)

    /// 키 부재·비정수는 `UserDefaults.integer(forKey:)` 가 모두 0 으로 주므로 *미설정* 으로 읽어야 한다.
    @Test("저장값 변환 — 범위 안은 그대로, 범위 밖은 clamp, 0 은 기본값")
    func storedLimitConversion() {
        #expect(HistoryLimitPolicy.storedLimit(raw: 300) == 300)
        #expect(HistoryLimitPolicy.storedLimit(raw: 9999) == 500)
        #expect(HistoryLimitPolicy.storedLimit(raw: 0) == 50)
        #expect(HistoryLimitPolicy.storedLimit(raw: -1) == 50)
        #expect(HistoryLimitPolicy.storedLimit(raw: 1) == 1)
        #expect(HistoryLimitPolicy.storedLimit(raw: 500) == 500)
    }

    // MARK: - 증감 버튼

    /// 증감은 허용 범위 밖으로 나가지 않는다. 경계에서 *막혔다는 신호를 내지 않는* 것이 의도다 —
    /// 연타하면 같은 토스트가 그대로 쌓인다.
    @Test("증감은 1씩 이동하고 경계에서 멈춤")
    func stepClampsAtBounds() {
        #expect(HistoryLimitPolicy.step(from: 60, delta: 1, currentUnpinnedCount: 51) == 61)
        #expect(HistoryLimitPolicy.step(from: 60, delta: -1, currentUnpinnedCount: 51) == 59)
        // 하한 = 현재 보관 개수
        #expect(HistoryLimitPolicy.step(from: 51, delta: -1, currentUnpinnedCount: 51) == 51)
        // 상한 = 500
        #expect(HistoryLimitPolicy.step(from: 500, delta: 1, currentUnpinnedCount: 51) == 500)
        // 보관 개수가 0 이면 하한은 1
        #expect(HistoryLimitPolicy.step(from: 1, delta: -1, currentUnpinnedCount: 0) == 1)
    }
}
