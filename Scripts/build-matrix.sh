#!/usr/bin/env bash
# 지원 OS 풀 (Sonoma 14 / Sequoia 15 / Tahoe 26) deployment target 별 빌드 매트릭스 검증 (TASK-089 Phase 6)
# 각 deployment target 빌드 통과 확인 → 외부 출시 prereq 3 OS 분기 정합 검증.
# 실기 .dmg 설치 후 일상 동작 확인은 Stage 5 작업 5.3 위임 (본 스크립트 비범위).

set -euo pipefail

cd "$(dirname "$0")/.."

SCHEME="stash"
DESTINATION="platform=macOS,arch=arm64"
TARGETS=("14.0" "15.0" "26.0")

echo "===== build-matrix.sh — 지원 OS 풀 빌드 검증 ====="
echo "타겟: ${TARGETS[*]}"
echo ""

FAILURES=0

for target in "${TARGETS[@]}"; do
    echo "----- MACOSX_DEPLOYMENT_TARGET=${target} 빌드 시작 -----"
    if xcodebuild \
        -scheme "${SCHEME}" \
        -destination "${DESTINATION}" \
        MACOSX_DEPLOYMENT_TARGET="${target}" \
        build 2>&1 | tail -5 | grep -q "BUILD SUCCEEDED"; then
        echo "[PASS] MACOSX_DEPLOYMENT_TARGET=${target}"
    else
        echo "[FAIL] MACOSX_DEPLOYMENT_TARGET=${target}"
        FAILURES=$((FAILURES + 1))
    fi
    echo ""
done

echo "===== 빌드 매트릭스 결과 ====="
echo "총 ${#TARGETS[@]} 타겟 / 실패 ${FAILURES} 건"

if [ "${FAILURES}" -gt 0 ]; then
    exit 1
fi
echo "모든 deployment target 빌드 PASS"
