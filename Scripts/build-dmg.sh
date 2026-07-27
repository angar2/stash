#!/bin/bash
# stash .dmg 배포 산출물 빌드 스크립트 — Release 빌드 → .app 추출 → .dmg 패키징

# 한 줄이라도 실패하면 즉시 중단 (-e) / 미정의 변수 사용 차단 (-u) / 파이프 중간 실패 전파 (-o pipefail)
# 안 박으면 중간 명령 실패해도 다음 명령이 계속 실행돼 *반쪽짜리 dmg* 가 나옴
set -euo pipefail

# ── 0. 사전 조건 ─────────────────────────────────────────
# 스크립트가 어느 위치에서 호출되든 프로젝트 루트 기준으로 동작하도록 cd
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

# Info.plist 안 CFBundleShortVersionString 추출 → dmg 파일명에 사용
# plutil = macOS 기본 plist 도구 (Xcode 설치 시 자동 포함)
# raw 옵션 = 따옴표 없이 값만 (예: 1.0.0)
VERSION=$(plutil -extract CFBundleShortVersionString raw Sources/Resources/Info.plist)

# build 번호 = git 커밋 수 (TASK-096)
# Info.plist CFBundleVersion 은 $(CURRENT_PROJECT_VERSION) 변수 참조 → 아래 archive 인자로 주입
# 누적 단조 증가 (마케팅 버전 무관) — 매 릴리스 시점 커밋 수가 산출물 .app 에 박힘
BUILD_NUMBER=$(git rev-list --count HEAD)

APP_NAME="Stash"
SCHEME="Stash"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

# ── 1. 이전 산출물 정리 ───────────────────────────────────
# build/ 폴더 통째 삭제 = 멱등 빌드 보장
# (재호출 시 항상 깨끗한 상태에서 시작 — 이전 빌드 캐시가 새 빌드에 섞이는 버그 차단)
rm -rf build/

# ── 2. Release 빌드 → .xcarchive ─────────────────────────
# xcodebuild archive = Release 구성으로 빌드 + 배포용 .xcarchive 번들 생성
#   -scheme         = Xcode 스킴 이름 (project.yml 정합)
#   -configuration  = Release (최적화 빌드 — Debug 와 분리)
#   -archivePath    = .xcarchive 출력 위치
#   CURRENT_PROJECT_VERSION = 커맨드라인 오버라이드. project 기본값(1)을 덮어 git 커밋 수 주입
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "build/${APP_NAME}.xcarchive" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive

# ── 3. .xcarchive → .app 추출 ────────────────────────────
# exportArchive = .xcarchive 안 .app 번들을 export 폴더로 꺼냄
# .xcarchive 자체는 디버그 심볼·메타데이터까지 포함한 *번들* 이라 dmg 안에는 .app 만 들어가야 함
#   -exportOptionsPlist = export 방법 설정 (루트의 ExportOptions.plist 인용)
#     → 이 plist 안 method=mac-application 박혀 있어 사인 없는 단순 추출
xcodebuild \
  -exportArchive \
  -archivePath "build/${APP_NAME}.xcarchive" \
  -exportPath "build/export" \
  -exportOptionsPlist ExportOptions.plist

# ── 4. .app → .dmg 패키징 (3 단계) ───────────────────────

# 4-1. 임시 read-write .dmg 생성 (마운트 후 내용 수정 가능한 형태)
#   -size 200m  = 여유 공간 (앱 + 심볼릭 링크 들어갈 만큼)
#   -volname    = 마운트 시 Finder 에 표시되는 볼륨 이름
#   -srcfolder  = .dmg 안에 들어갈 폴더 (앱 번들)
#   -ov         = 기존 파일 덮어쓰기
#   -format UDRW = read-write 형식 (다음 단계에서 심볼릭 링크 추가 위해 필요)
hdiutil create \
  -size 200m \
  -volname "$APP_NAME" \
  -srcfolder "build/export/${APP_NAME}.app" \
  -ov \
  -format UDRW \
  build/temp.dmg

# 4-2. 임시 .dmg 마운트 → Applications 폴더로의 심볼릭 링크 추가
#   사용자가 .dmg 더블클릭 시 "stash.app 을 Applications 로 드래그" UX 자연 (macOS 배포 관행)
#   마운트 지점을 /Volumes/<앱이름> 으로 고정하면, *다른 Stash dmg 가 이미 그 자리에 붙어 있을 때*
#   새 이미지가 같은 경로에 겹쳐 마운트되고 detach 가 엉뚱한 디스크를 지목해 실패한다
#   (2026-07-27 v1.1.0 빌드에서 실제 발생 — 6월에 열어둔 1.0.1 dmg 가 자리를 물고 있었다).
#   → 매번 빈 임시 경로를 새로 만들어 쓰고, detach 는 경로가 아니라 attach 가 돌려준 디바이스로 지목한다.
#   -nobrowse = 빌드 중 Finder 사이드바·바탕화면에 볼륨이 뜨지 않게 (사용자 방해 X)
MOUNT_ROOT=$(mktemp -d /tmp/stash-dmg-XXXXXX)
MOUNT_POINT="${MOUNT_ROOT}/${APP_NAME}"
DEV=$(hdiutil attach build/temp.dmg -mountpoint "$MOUNT_POINT" -nobrowse \
  | awk '/GUID_partition_scheme/ { print $1; exit }')
# attach 는 성공했는데 디바이스를 못 뽑으면 이후 detach 가 조용히 빗나간다 → 즉시 중단
if [ -z "$DEV" ]; then
  echo "✗ dmg 마운트 디바이스를 찾지 못했습니다 (hdiutil attach 출력 형식 확인 필요)" >&2
  exit 1
fi
ln -s /Applications "$MOUNT_POINT/Applications"
# Spotlight indexing / Finder 자동 열기 등으로 detach 실패 가능 → 잠시 대기 후 -force 박음
sync
sleep 2
hdiutil detach "$DEV" -force
rmdir "$MOUNT_POINT" "$MOUNT_ROOT" 2>/dev/null || true

# 4-3. read-write .dmg → 압축 read-only .dmg 변환
#   -format UDZO = zlib 압축 read-only (배포용 표준 형식 + 파일 크기 감소)
hdiutil convert build/temp.dmg \
  -format UDZO \
  -o "build/${DMG_NAME}"

# 임시 read-write .dmg 정리 — 최종 산출물만 남김
rm build/temp.dmg

# ── 완료 ─────────────────────────────────────────────────
echo ""
echo "✓ build/${DMG_NAME}"
echo "  버전: ${VERSION} (build ${BUILD_NUMBER})"
echo "  크기: $(du -h "build/${DMG_NAME}" | cut -f1)"
