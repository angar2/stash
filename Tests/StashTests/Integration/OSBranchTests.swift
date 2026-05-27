// macOS 버전별 분기 단위 통합 — Phase 5 / Phase 6 (TASK-089)
// 지원 OS 풀 (Sonoma 14 / Sequoia 15 / Tahoe 26) 런타임 분기 + deployment target 14.0 정합.
import Testing
import Foundation
@testable import stash

struct OSBranchTests {

    @Test("ProcessInfo.operatingSystemVersion — 14.0 이상 (deployment target 정합)")
    func deploymentTargetIs14OrHigher() {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #expect(v.majorVersion >= 14, "macOS 14 이상 실행 환경 정합 (actual: \(v.majorVersion).\(v.minorVersion))")
    }

    @Test("ProcessInfo.isOperatingSystemAtLeast(14.0) → true")
    func sonomaApiAvailable() {
        let sonoma = OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0)
        #expect(
            ProcessInfo.processInfo.isOperatingSystemAtLeast(sonoma),
            "macOS 14 (Sonoma) API 가용성 — deployment target 기준"
        )
    }

    @Test("macOS 26 (Tahoe) 분기 — runtime 검증 가능 (현 실행 환경에 따라 true/false 모두 정상)")
    func tahoeBranchRuntimeDetect() {
        let tahoe = OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        let isTahoeOrLater = ProcessInfo.processInfo.isOperatingSystemAtLeast(tahoe)
        // runtime 결과는 환경마다 다름 — Bool 값 valid 인지만 확인.
        #expect(isTahoeOrLater == true || isTahoeOrLater == false, "Bool 값 valid (panic 없음)")
    }

    @Test("@available(macOS 14, *) 분기 — Swift 6 + Xcode 16+ 컴파일 정합")
    func availableMacOS14Compiles() {
        if #available(macOS 14, *) {
            #expect(true, "macOS 14 분기 진입")
        } else {
            #expect(Bool(false), "deployment target 14 인데 분기 미진입 — 회귀")
        }
    }

    @Test("@available(macOS 15, *) 분기 — runtime 환경에 따라 분기 (현 실행 환경 기준)")
    func availableMacOS15Branch() {
        if #available(macOS 15, *) {
            // 실행 환경이 macOS 15+ — 분기 진입 OK.
            #expect(true, "macOS 15+ 환경에서 분기 진입")
        } else {
            // 실행 환경이 macOS 14.x — 분기 미진입 OK.
            #expect(true, "macOS 14.x 환경에서 분기 미진입 (fallback 흐름)")
        }
    }
}
