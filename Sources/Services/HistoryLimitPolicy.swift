// 보관 한도(SERVICE-POLICY §3-1) 값 판정 — 확정 입력 / 증감 / 첫 실행 초기값 (TASK-100)
import Foundation
import OSLog

/// 보관 한도로 쓸 수 있는 값인지 판정한다.
///
/// 판정을 설정 화면이나 UserDefaults 접근부가 아니라 여기에 따로 두는 이유는 **검증 가능성**이다 —
/// 화면 안에 묻히면 경계값(현재 개수와 같은 값 / 상한 초과 / 빈 입력)이 통째로 수동 검수로 넘어간다.
/// 입력과 현재 보관 개수만 받아 결과를 돌려주므로 저장소·화면 없이 그대로 검증된다.
enum HistoryLimitPolicy {

    /// 확정 입력 판정 결과.
    enum Outcome: Equatable {
        /// 이 값으로 저장한다.
        case accepted(Int)
        /// 현재 보관 개수보다 작다 — 안내 토스트 발화 후 이 값(현재 개수)으로 되돌린다.
        case belowCurrentCount(Int)
        /// 숫자가 아니거나 0 이하 — 토스트 없이 직전 값으로 되돌린다.
        case invalid
    }

    /// 입력란에서 확정(Enter · 포커스 이탈)된 문자열을 판정한다.
    ///
    /// 상한 초과는 조용히 상한으로 맞춘다 — 미달과 달리 데이터가 사라질 위험이 없어 경고할 이유가 없다.
    static func resolve(input: String, currentUnpinnedCount: Int) -> Outcome {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        // `Int` 파싱은 소수점·문자·빈 문자열을 전부 nil 로 떨군다. 음수는 파싱되므로 하한으로 따로 거른다.
        //
        // 자릿수가 너무 많아 `Int` 범위를 넘는 경우도 nil 이 되는데, 그건 *잘못 친 값* 이 아니라 *너무 큰 값* 이다.
        // 무효로 되돌리면 20자리를 친 사용자만 상한 조정을 못 받는 앞뒤 안 맞는 동작이 된다.
        guard let value = Int(trimmed) else {
            let isHugeNumber = !trimmed.isEmpty && trimmed.allSatisfy { $0.isASCII && $0.isNumber }
            guard isHugeNumber else {
                Logger.ui.debug("HistoryLimit reject — 무효 입력")
                return .invalid
            }
            return resolveCapped(Constants.maxUnpinnedClipsMax, currentUnpinnedCount: currentUnpinnedCount)
        }
        guard value >= Constants.maxUnpinnedClipsMin else {
            Logger.ui.debug("HistoryLimit reject — 하한 미만 입력")
            return .invalid
        }
        return resolveCapped(min(value, Constants.maxUnpinnedClipsMax), currentUnpinnedCount: currentUnpinnedCount)
    }

    /// 상한까지 맞춰진 값을 현재 보관 개수와 대조해 최종 판정한다.
    private static func resolveCapped(_ capped: Int, currentUnpinnedCount: Int) -> Outcome {
        let floorCount = currentFloor(currentUnpinnedCount)
        if capped < floorCount {
            Logger.ui.info("HistoryLimit reject — 현재 개수 미달 입력=\(capped, privacy: .public) 현재=\(floorCount, privacy: .public)")
            return .belowCurrentCount(floorCount)
        }
        Logger.ui.info("HistoryLimit accept — \(capped, privacy: .public)")
        return .accepted(capped)
    }

    /// 증감 버튼 1회 이동 결과. 허용 범위 밖으로는 나가지 않는다 —
    /// 경계에서 막히는 것을 토스트로 알리지 않는 이유는 연타 시 같은 토스트가 그대로 쌓이기 때문이다.
    static func step(from current: Int, delta: Int, currentUnpinnedCount: Int) -> Int {
        let lower = max(Constants.maxUnpinnedClipsMin, currentFloor(currentUnpinnedCount))
        return min(max(current + delta, lower), Constants.maxUnpinnedClipsMax)
    }

    /// 설정값이 아직 없을 때 기록할 초기값.
    ///
    /// 그냥 기본값을 쓰지 않는 이유는 **한도가 200 고정이던 시절의 사용자** 때문이다. 기본값 50 을 그대로
    /// 적용하면 앱을 업데이트한 뒤 다음 복사 한 번에 150 개가 사라진다. 보관 중인 만큼은 지켜준다.
    static func initialValue(currentUnpinnedCount: Int) -> Int {
        max(Constants.maxUnpinnedClipsDefault, currentFloor(currentUnpinnedCount))
    }

    /// 설정값이 아직 없으면 초기값을 1회 기록한다. 이미 있으면 아무것도 하지 않는다.
    ///
    /// 존재 판정을 `object(forKey:)` 로 하는 이유 — `integer(forKey:)` 는 키 부재와 값 0 을 구분하지 못한다.
    /// - Returns: 이번에 기록한 값. 이미 설정돼 있었으면 `nil`.
    @discardableResult
    static func initializeStoredLimitIfNeeded(
        currentUnpinnedCount: Int,
        defaults: UserDefaults = .standard
    ) -> Int? {
        let key = Constants.UserDefaultsKeys.maxUnpinnedClips
        guard defaults.object(forKey: key) == nil else { return nil }
        let value = initialValue(currentUnpinnedCount: currentUnpinnedCount)
        defaults.set(value, forKey: key)
        Logger.appLifecycle.info("HistoryLimit 첫 실행 초기화 — 보관=\(currentUnpinnedCount, privacy: .public) 한도=\(value, privacy: .public)")
        return value
    }

    /// 저장된 raw 값을 실제로 쓸 한도로 바꾼다. `Constants.maxUnpinnedClips` 의 본체다.
    ///
    /// `UserDefaults.integer(forKey:)` 는 키 부재와 비정수 값을 모두 0 으로 준다. 0 은 유효한 한도가 아니라
    /// *미설정* 이라는 뜻이므로 기본값으로 떨어뜨린다. 범위를 벗어난 저장값(직접 편집 등)은 조용히 clamp 한다.
    static func storedLimit(raw: Int) -> Int {
        guard raw > 0 else { return Constants.maxUnpinnedClipsDefault }
        return min(max(raw, Constants.maxUnpinnedClipsMin), Constants.maxUnpinnedClipsMax)
    }

    /// 판정에 쓰는 현재 개수. 음수는 있을 수 없고, 상한을 넘는 개수는 상한으로 본다 —
    /// 그렇지 않으면 하한이 상한을 넘어서 고를 수 있는 값이 하나도 없는 상태가 된다.
    private static func currentFloor(_ count: Int) -> Int {
        min(max(count, 0), Constants.maxUnpinnedClipsMax)
    }
}
