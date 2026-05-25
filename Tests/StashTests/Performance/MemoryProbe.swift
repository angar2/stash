// mach task_info wrap — 단위 테스트 메모리 측정 진입점 (TASK-082 Phase 1)
import Darwin
import Foundation

/// 단위 테스트 환경에서 현재 프로세스의 *physical footprint* 측정 helper.
/// Activity Monitor 의 "Memory" 컬럼과 동일 path — macOS 표준 resident memory 지표.
/// `task_vm_info_data_t.phys_footprint` 추출. 측정 실패 시 0 반환.
///
/// 후속 Phase (3 / 4 / 7 / 8 / 10) 끝마다 `MemorySnapshotTests` 가 본 helper 호출로
/// 베이스라인 대비 delta 산출 → 캐시 / 인덱스 적용 효과 정량 입증.
enum MemoryProbe {
    /// 현재 프로세스 physical footprint (bytes). 실패 시 0.
    static func residentBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        return UInt64(info.phys_footprint)
    }

    /// MB 단위 — 콘솔 출력 가독성.
    static func residentMB() -> Double {
        Double(residentBytes()) / 1_048_576
    }
}
