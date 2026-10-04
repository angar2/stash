#!/bin/bash
# stash .dmg 배포 산출물 빌드 스크립트 — Release 빌드 → .app 추출(Developer ID 서명) → .dmg 패키징 → 공증 → 티켓 부착

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

# Developer ID 서명·공증 자격 (TASK-108)
#   인증서와 공증 자격은 이 맥의 로그인 키체인에 있다. 암호는 스크립트·리포에 두지 않는다.
#   SIGN_IDENTITY = dmg 서명에 쓰는 인증서 이름 (앱 서명은 project.yml Release 구성 + ExportOptions.plist 가 맡는다)
#   NOTARY_PROFILE = xcrun notarytool store-credentials 로 저장해 둔 키체인 프로필 이름
TEAM_ID="L7J8SQ9T5F"
SIGN_IDENTITY="Developer ID Application: Kwanyong Eom (${TEAM_ID})"
NOTARY_PROFILE="stash-notary"

# 아카이브(수 분)를 돌리기 전에 서명·공증 자격부터 확인한다. 없으면 끝까지 가서야 실패한다.
if ! security find-identity -v -p codesigning | grep -qF "\"${SIGN_IDENTITY}\""; then
  echo "✗ 서명 인증서가 키체인에 없습니다: ${SIGN_IDENTITY}" >&2
  echo "  키체인 접근에서 Developer ID Application 인증서(.p12)를 로그인 키체인으로 가져온 뒤 다시 실행하세요." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "✗ 공증 프로필을 쓸 수 없습니다: ${NOTARY_PROFILE}" >&2
  echo "  xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" 로 다시 저장한 뒤 다시 실행하세요." >&2
  exit 1
fi

# 같은 이름의 볼륨이 이미 마운트돼 있으면 Finder 가 창 설정(.DS_Store)을 *조용히* 기록하지 않는다(실측).
# 새 이미지는 /Volumes/Stash 2 같은 다른 경로에 붙지만, Finder 는 이름으로 볼륨을 식별해 먼저 붙어 있는
# 읽기전용 볼륨 쪽을 보고 쓰기를 포기한다. 결과는 "빌드는 성공, 창은 예전 모양" 이다.
# 아카이브(수 분)를 돌리기 전에 여기서 끊는다. 사용자가 열어둔 볼륨을 임의로 꺼내지 않고 안내만 한다.
MOUNTED_CONFLICTS=$(ls -1 /Volumes 2>/dev/null | grep -E "^${APP_NAME}( [0-9]+)?$" || true)
if [ -n "$MOUNTED_CONFLICTS" ]; then
  echo "✗ 같은 이름의 볼륨이 이미 마운트돼 있습니다 — 이 상태로는 설치 창 설정이 기록되지 않습니다." >&2
  echo "$MOUNTED_CONFLICTS" | sed 's|^|    /Volumes/|' >&2
  echo "  아래 명령으로 꺼낸 뒤 다시 실행하세요:" >&2
  echo "$MOUNTED_CONFLICTS" | sed "s|.*|    hdiutil detach '/Volumes/&'|" >&2
  exit 1
fi

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
#     → method=developer-id. 앱과 내장 Sparkle 도구(실행 파일·XPC 서비스·Updater.app)를 모두
#       Developer ID 인증서 + Hardened Runtime + 보안 타임스탬프로 다시 서명한다. 공증의 전제 조건이다.
xcodebuild \
  -exportArchive \
  -archivePath "build/${APP_NAME}.xcarchive" \
  -exportPath "build/export" \
  -exportOptionsPlist ExportOptions.plist

# ── 4. .app → .dmg 패키징 ────────────────────────────────

# 작업 폴더를 build/ 가 아니라 중립 임시 경로에 둔다.
#   Finder 가 기록하는 .DS_Store 의 배경 이미지 alias 에는 *임시 dmg 를 만든 경로*가 함께 박히고,
#   그 dmg 는 그대로 배포된다. build/ 에 만들면 빌드 머신의 사용자 이름·폴더 구조가 공개 산출물에 남는다.
#   최종 산출물 경로(build/<이름>.dmg)는 그대로다.
WORK_DIR=$(mktemp -d /tmp/stash-dmg-XXXXXX)
TEMP_DMG="${WORK_DIR}/temp.dmg"

# 4-1. 임시 read-write .dmg 생성 (마운트 후 내용 수정 가능한 형태)
#   -size 200m  = 여유 공간 (앱 + 심볼릭 링크 + 배경/볼륨 아이콘 들어갈 만큼)
#   -volname    = 마운트 시 Finder 에 표시되는 볼륨 이름
#   -srcfolder  = .dmg 안에 들어갈 폴더 (앱 번들)
#   -ov         = 기존 파일 덮어쓰기
#   -format UDRW = read-write 형식 (다음 단계에서 구성 파일 추가 위해 필요)
hdiutil create \
  -size 200m \
  -volname "$APP_NAME" \
  -srcfolder "build/export/${APP_NAME}.app" \
  -ov \
  -format UDRW \
  "$TEMP_DMG"

# 4-2. 설치 창 구성 재료 준비 (배경 이미지 + 볼륨 아이콘)
swift Scripts/make-dmg-background.swift "${WORK_DIR}/background"

#   볼륨 아이콘 = 앱 아이콘. 원본은 Icon Composer 파일(AppIcon.icon) 하나이고 크기별 PNG 는 저장소에 두지 않는다 (TASK-106).
#   Xcode 에 함께 들어 있는 ictool 로 기본(라이트) 모습을 크기별로 렌더해 .iconset 을 만든다.
#   ictool 렌더는 둥근 사각형이 캔버스를 꽉 채운다. macOS 아이콘 규격(1024 캔버스에 824 본체)대로
#   본체를 줄여 렌더한 뒤 투명 여백을 둘러야 Finder 에서 다른 아이콘과 같은 크기로 보인다.
#   본체 크기는 여백이 좌우 같게 짝수 차이로 맞춘다.
ICTOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [ ! -x "$ICTOOL" ]; then
  echo "✗ ictool 을 찾지 못했습니다 — Xcode 26 이상이 필요합니다: $ICTOOL" >&2
  exit 1
fi
ICONSET_DIR="${WORK_DIR}/${APP_NAME}.iconset"
mkdir -p "$ICONSET_DIR"
for BASE in 16 32 128 256 512; do
  for SCALE in 1 2; do
    PX=$((BASE * SCALE))
    BODY=$(( (PX * 824 / 1024 + 1) / 2 * 2 ))
    NAME="icon_${BASE}x${BASE}"
    [ "$SCALE" = 2 ] && NAME="${NAME}@2x"
    "$ICTOOL" Sources/Resources/AppIcon.icon --export-image --output-file "${ICONSET_DIR}/${NAME}.png" \
      --platform macOS --rendition Default --width "$BODY" --height "$BODY" --scale 1 >/dev/null
    sips -p "$PX" "$PX" "${ICONSET_DIR}/${NAME}.png" >/dev/null
  done
done
iconutil -c icns "$ICONSET_DIR" -o "${WORK_DIR}/VolumeIcon.icns"

# 4-3. 임시 .dmg 마운트 → 구성 파일 배치
#   마운트 지점을 /Volumes/<앱이름> 으로 *고정* 하면, 다른 Stash dmg 가 이미 그 자리에 붙어 있을 때
#   새 이미지가 겹쳐 마운트되고 detach 가 엉뚱한 디스크를 지목해 실패한다
#   (2026-07-27 v1.1.0 빌드에서 실제 발생 — 6월에 열어둔 1.0.1 dmg 가 자리를 물고 있었다).
#   → 지점을 지정하지 않고 hdiutil 이 정해준 곳을 그대로 받아 쓴다. 이름이 겹치면 hdiutil 이
#     알아서 다른 경로(/Volumes/Stash 1)를 잡아주고, detach 는 경로가 아니라 디바이스로 지목한다.
#   /Volumes 밖(임시 폴더 등)에 마운트하면 Finder 가 .DS_Store 를 아예 기록하지 않는다 —
#   설정은 적용된 것처럼 보이지만 디스크에 남지 않아 예전 모양 그대로인 dmg 가 나온다. 지정 금지.
#   -nobrowse   = 빌드 중 Finder 사이드바·바탕화면에 볼륨이 뜨지 않게 (사용자 방해 X)
#   -noautoopen = 마운트 직후 Finder 창이 저절로 뜨지 않게 (창은 아래에서 우리가 직접 연다)
ATTACH_OUTPUT=$(hdiutil attach "$TEMP_DMG" -nobrowse -noautoopen)
DEV=$(echo "$ATTACH_OUTPUT" | awk '/GUID_partition_scheme/ { print $1; exit }')
MOUNT_POINT=$(echo "$ATTACH_OUTPUT" | awk -F'\t' '/\/Volumes\// { print $NF; exit }')
# attach 는 성공했는데 디바이스를 못 뽑으면 이후 detach 가 조용히 빗나간다 → 즉시 중단
if [ -z "$DEV" ] || [ -z "$MOUNT_POINT" ]; then
  echo "✗ dmg 마운트 결과를 해석하지 못했습니다 (hdiutil attach 출력 형식 확인 필요)" >&2
  echo "$ATTACH_OUTPUT" >&2
  exit 1
fi

#   Applications 심볼릭 링크 = "앱을 Applications 로 끌어다 놓는" 설치 방식의 대상 (macOS 배포 관행)
ln -s /Applications "$MOUNT_POINT/Applications"

#   배경 폴더를 *일부러 다른 이름*(.bgsrc)으로 두고 Finder 작업 후 .background 로 되돌린다.
#   Finder 는 창 설정을 기록할 때 그 시점에 볼륨에 있던 항목마다 아이콘 좌표를 함께 적는데,
#   숨김 파일 표시를 켠 사용자 화면에서는 *좌표가 적힌 숨김 항목만* 그려진다.
#   그대로 두면 배경 폴더가 창 좌상단에 아이콘으로 뜬다(실측). 이름을 바꾸면 좌표는 존재하지 않는
#   이름(.bgsrc)에 남고 실제 폴더에는 좌표가 없어 그려지지 않는다 — 배경 참조는 그대로 유효하다.
mkdir "$MOUNT_POINT/.bgsrc"
cp "${WORK_DIR}/background/background.png" "$MOUNT_POINT/.bgsrc/"

# 4-4. Finder 에 창 모양 지시 → 볼륨 루트에 .DS_Store 생성
#   창 크기·아이콘 크기·아이콘 좌표·배경 이미지는 Finder 만 기록할 수 있다(공개 도구들도 동일한 방식).
#   좌표는 좌상단 원점이며 Scripts/make-dmg-background.swift 의 값과 한 쌍이다 — 한쪽만 바꾸면 화살표가 어긋난다.
osascript - "$MOUNT_POINT" "$MOUNT_POINT/.bgsrc/background.png" <<'APPLESCRIPT'
on run argv
  tell application "Finder"
    set volFolder to POSIX file (item 1 of argv) as alias
    open volFolder
    set win to container window of volFolder
    set current view of win to icon view
    set toolbar visible of win to false
    set statusbar visible of win to false
    -- {왼쪽, 위, 오른쪽, 아래} = 654×444 창
    set the bounds of win to {100, 100, 754, 544}
    set opts to the icon view options of win
    set arrangement of opts to not arranged
    set icon size of opts to 140
    set text size of opts to 12
    set label position of opts to bottom
    set shows item info of opts to false
    set background picture of opts to (POSIX file (item 2 of argv) as alias)
    set position of item "Stash.app" of win to {197, 195}
    set position of item "Applications" of win to {473, 195}
    update volFolder without registering applications
    delay 2
    close win
  end tell
end run
APPLESCRIPT

#   Finder 자동화 권한이 없으면 위 스크립트는 *에러 없이 무시* 된다 → .DS_Store 자체가 안 생긴다.
#   여기서 잡지 않으면 "빌드 성공 + 예전 모양" dmg 가 그대로 배포된다.
if [ ! -f "$MOUNT_POINT/.DS_Store" ]; then
  echo "✗ 창 설정(.DS_Store)이 기록되지 않았습니다." >&2
  echo "  시스템 설정 > 개인정보 보호 및 보안 > 자동화 에서 이 터미널의 Finder 제어를 허용한 뒤 다시 실행하세요." >&2
  hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
  exit 1
fi

# 4-5. 배경 폴더 이름 되돌리기 — Finder 가 적어둔 좌표를 실제 폴더에서 떼어낸다 (4-3 주석 참조)
mv "$MOUNT_POINT/.bgsrc" "$MOUNT_POINT/.background"

# 4-6. 볼륨 아이콘 — 반드시 Finder 단계 *뒤* 여야 한다
#   Finder 는 창 설정을 기록하면서 볼륨 루트를 다시 쓰는데, 이때 미리 넣어둔 .VolumeIcon.icns 를 지우고
#   커스텀 아이콘 플래그도 되돌린다(실측 확인). 앞에 두면 파일째 사라져 기본 디스크 아이콘으로 뜬다.
#   플래그가 없으면 .VolumeIcon.icns 가 있어도 아이콘이 바뀌지 않으므로 둘은 한 쌍이다.
cp "${WORK_DIR}/VolumeIcon.icns" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

# Spotlight indexing / Finder 자동 열기 등으로 detach 실패 가능 → 잠시 대기 후 해제.
#   -force 를 *먼저* 쓰지 않는다. 강제 해제는 /Volumes 에 같은 이름의 빈 유령 볼륨을 남기는데,
#   그러면 다음 빌드에서 이름이 선점돼 Finder 가 창 설정을 기록하지 않는다(실측으로 재현).
#   정상 해제를 먼저 시도하고, 그래도 안 되면 그때 강제한다.
sync
sleep 2
hdiutil detach "$DEV" || hdiutil detach "$DEV" -force

# 4-7. read-write .dmg → 압축 read-only .dmg 변환
#   -format UDZO = zlib 압축 read-only (배포용 표준 형식 + 파일 크기 감소)
hdiutil convert "$TEMP_DMG" \
  -format UDZO \
  -o "build/${DMG_NAME}"

# 임시 작업 폴더 정리 — 최종 산출물만 남김
rm -rf "$WORK_DIR"

# ── 5. dmg 서명 → 공증 → 티켓 부착 (TASK-108) ─────────────
# 5-1. dmg 자체 서명. 앱은 3단계에서 서명됐고, 여기서는 그것을 감싼 디스크 이미지에 서명한다.
#   서명이 없는 dmg 는 Gatekeeper 판정에서 출처를 확인할 수 없다.
codesign --sign "$SIGN_IDENTITY" --timestamp "build/${DMG_NAME}"

# 5-2. Apple 공증 제출. dmg 하나만 제출하면 안쪽 앱의 해시까지 함께 등록된다.
#   --wait 는 결과가 나올 때까지 기다린다(보통 수 분). 결과 판정은 종료 코드가 아니라 상태 값으로 한다.
#   Invalid(검사 불합격)여도 제출 자체는 성공이라 종료 코드만 보면 놓칠 수 있다.
echo "공증 제출 중, 결과가 나올 때까지 수 분 걸립니다"
NOTARY_JSON=$(xcrun notarytool submit "build/${DMG_NAME}" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait --timeout 30m \
  --output-format json) || true
NOTARY_STATUS=$(echo "$NOTARY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)
NOTARY_ID=$(echo "$NOTARY_JSON" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)
# 시간 초과는 실패가 아니다. Apple 은 제출본 검사를 계속하므로 dmg 를 다시 만들지 말고 결과를 기다려 이어 간다.
#   새 개발자 계정의 첫 제출은 1시간 가까이 걸린 적이 있다(TASK-108 실측, 2026-10-04). 이후 제출은 보통 수 분이다.
if [ -z "$NOTARY_STATUS" ] && echo "$NOTARY_JSON" | grep -q "Timeout"; then
  echo "✗ 공증 대기 시간 초과. Apple 은 검사를 계속하고 있습니다 (제출 ID: ${NOTARY_ID})" >&2
  echo "  dmg 를 다시 빌드하지 말고, 아래로 결과를 확인해 Accepted 가 되면 이어서 실행하세요:" >&2
  echo "    xcrun notarytool info ${NOTARY_ID} --keychain-profile ${NOTARY_PROFILE}" >&2
  echo "    xcrun stapler staple build/${DMG_NAME} && Scripts/verify-dmg.sh build/${DMG_NAME}" >&2
  exit 1
fi
if [ "$NOTARY_STATUS" != "Accepted" ]; then
  echo "✗ 공증 실패 (상태: ${NOTARY_STATUS:-응답 없음})" >&2
  echo "$NOTARY_JSON" >&2
  # 불합격 사유(어느 파일이 왜 거부됐는지)는 제출 기록 로그에만 있다.
  if [ -n "$NOTARY_ID" ]; then
    xcrun notarytool log "$NOTARY_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
  fi
  exit 1
fi
echo "✓ 공증 통과 (제출 ID: ${NOTARY_ID})"

# 5-3. 공증 티켓을 dmg 에 부착한다(staple). 부착하지 않으면 사용자 맥이 처음 열 때
#   Apple 서버에 티켓을 조회해야 하고, 오프라인이면 확인하지 못한다.
#   부착은 dmg 파일 내용을 바꾸므로 Sparkle EdDSA 서명(release.sh)은 반드시 이 뒤에 만든다.
xcrun stapler staple "build/${DMG_NAME}"

# ── 6. 산출물 검증 게이트 ─────────────────────────────────
# 창 설정과 서명·공증이 실제로 산출물에 담겼는지 대조. 어긋나면 여기서 빌드가 실패한다.
Scripts/verify-dmg.sh "build/${DMG_NAME}"

# ── 완료 ─────────────────────────────────────────────────
echo ""
echo "✓ build/${DMG_NAME}"
echo "  버전: ${VERSION} (build ${BUILD_NUMBER})"
echo "  크기: $(du -h "build/${DMG_NAME}" | cut -f1)"
