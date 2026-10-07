#!/bin/bash
# stash App Store판 배포 산출물 빌드 스크립트 (TASK-116)
#   Release 아카이브 → App Store Connect 내보내기(자동 서명) → 산출물 검사 → (--upload) App Store Connect 업로드
#
# 사용:
#   Scripts/build-appstore.sh            # build/appstore/export/Stash.pkg 를 만들고 검사만 한다
#   Scripts/build-appstore.sh --upload   # 검사를 통과하면 App Store Connect 에 올린다 (TestFlight·심사 빌드 목록에 나타난다)
#
# 인증: 기본은 이 맥의 Xcode 에 로그인한 개발자 계정(Xcode > Settings > Accounts)이다.
#   App Store Connect API 키를 쓰려면 아래 세 환경 변수를 준다. 키 파일(.p8)은 리포 밖에 둔다.
#     ASC_KEY_ID      = 키 ID (예: ABCD123456)
#     ASC_ISSUER_ID   = 발급자 ID (UUID)
#     ASC_KEY_PATH    = 키 파일 경로 (생략하면 ~/.appstoreconnect/private_keys/AuthKey_<키 ID>.p8)
#
# 이 스크립트는 업로드만 한다. 심사 제출·외부 테스트 제출·등록 정보 변경은 하지 않는다.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

UPLOAD=0
case "${1:-}" in
  "") ;;
  --upload) UPLOAD=1 ;;
  *) echo "사용: $0 [--upload]" >&2; exit 2 ;;
esac

# ── 0. 값 ────────────────────────────────────────────────
VERSION=$(plutil -extract CFBundleShortVersionString raw Sources/Resources/Info.plist)
# 빌드 번호 = git 커밋 수. dmg판(build-dmg.sh)과 같은 규칙이라 같은 커밋에서 만든 두 판은 빌드 번호가 같다.
# App Store Connect 는 업로드마다 더 큰 빌드 번호를 요구한다. 커밋 수는 줄지 않으므로 같은 커밋을 두 번 올릴 때만 걸린다.
# 그때(태스크 중 커밋 전에 확인 빌드를 다시 올릴 때)만 BUILD_NUMBER 환경 변수로 직접 준다. 심사 빌드는 지정하지 않는다.
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}"

TEAM_ID="L7J8SQ9T5F"
BUNDLE_ID="com.angar2.stash"
SCHEME="StashAppStore"
OUT="build/appstore"
ARCHIVE="${OUT}/Stash.xcarchive"
EXPORT_DIR="${OUT}/export"
PKG="${EXPORT_DIR}/Stash.pkg"

# 커밋하지 않은 변경이 있으면 알린다. 심사 빌드는 /release 커밋(작업 트리 깨끗함)에서 만든다.
# 태스크 중 TestFlight 확인 빌드는 커밋 전에 올릴 수 있어 막지는 않는다. 그 빌드 번호는 이후 커밋으로 커지는
# 커밋 수보다 작아 심사 빌드 번호와 겹치지 않는다.
if [ -n "$(git status --porcelain)" ]; then
  echo "⚠ 커밋하지 않은 변경이 있는 작업 트리로 빌드합니다 (기준 커밋 $(git rev-parse --short HEAD), build ${BUILD_NUMBER}). 심사 빌드라면 멈추고 커밋부터 하세요."
fi

AUTH_ARGS=()
if [ -n "${ASC_KEY_ID:-}" ] || [ -n "${ASC_ISSUER_ID:-}" ]; then
  ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-}.p8}"
  if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ ! -f "$ASC_KEY_PATH" ]; then
    echo "✗ API 키 설정이 불완전합니다. ASC_KEY_ID · ASC_ISSUER_ID 와 키 파일이 모두 있어야 합니다." >&2
    exit 1
  fi
  AUTH_ARGS=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
  echo "인증: App Store Connect API 키 (${ASC_KEY_ID})"
else
  echo "인증: Xcode 에 로그인한 개발자 계정"
fi

# ── 1. 이전 산출물 정리 ───────────────────────────────────
rm -rf "$OUT"
mkdir -p "$OUT"

# ── 2. Release 아카이브 ──────────────────────────────────
# project.yml StashAppStore Release = 자동 서명(팀 L7J8SQ9T5F). -allowProvisioningUpdates 로 Xcode 가
# App ID 확인·프로파일 생성·인증서 선택을 알아서 한다. 빌드 마지막 단계에서 묶음 검사(Sparkle 없음)가 돈다.
# 산출 폴더를 dmg판과 가른다 (두 타깃 모두 Release 제품 이름이 Stash 다).
xcodebuild \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath DerivedData/AppStoreRelease \
  -clonedSourcePackagesDirPath DerivedData/SourcePackages \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates "${AUTH_ARGS[@]}" \
  archive

# ── 3. App Store Connect 내보내기 ─────────────────────────
# 배포 인증서(Apple Distribution)로 앱을, Mac Installer 인증서로 설치 패키지를 서명한다.
# 이 맥에 인증서가 없으면 Apple 이 보관하는 클라우드 관리 인증서로 서명한다.
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist ExportOptions-AppStore.plist \
  -allowProvisioningUpdates "${AUTH_ARGS[@]}"

# ── 4. 산출물 검사 ───────────────────────────────────────
# 업로드한 뒤에야 거절 메일로 알게 되는 것들을 여기서 먼저 막는다.
if [ ! -f "$PKG" ]; then
  echo "✗ 설치 패키지가 없습니다: ${PKG}" >&2
  ls -la "$EXPORT_DIR" >&2 || true
  exit 1
fi

CHECK_DIR=$(mktemp -d /tmp/stash-appstore-check-XXXXXX)
trap 'rm -rf "$CHECK_DIR"' EXIT
pkgutil --expand-full "$PKG" "${CHECK_DIR}/pkg"
APP=$(find "${CHECK_DIR}/pkg" -maxdepth 4 -name "Stash.app" -type d | head -1)
if [ -z "$APP" ]; then
  echo "✗ 설치 패키지 안에서 Stash.app 을 찾지 못했습니다" >&2
  exit 1
fi

FAILED=0
pass() { echo "  ✓ $1"; }
fail() { echo "  ✗ $1" >&2; FAILED=1; }

echo "산출물 검사: ${PKG}"

# 4-1. 설치 패키지 서명 = Mac Installer 배포 인증서
PKG_SIG=$(pkgutil --check-signature "$PKG" 2>&1 || true)
if grep -qE "(3rd Party Mac Developer Installer|Mac Installer Distribution): .*\(${TEAM_ID}\)" <<<"$PKG_SIG"; then
  pass "설치 패키지 서명: $(grep -oE '(3rd Party Mac Developer Installer|Mac Installer Distribution): [^)]*\)' <<<"$PKG_SIG" | head -1)"
else
  fail "설치 패키지가 Mac Installer 배포 인증서로 서명되지 않았습니다"
  echo "$PKG_SIG" >&2
fi

# 4-2. 앱 서명 = Apple Distribution
APP_SIG=$(codesign -dvv "$APP" 2>&1 || true)
if grep -qE "^Authority=(Apple Distribution|3rd Party Mac Developer Application): .*\(${TEAM_ID}\)" <<<"$APP_SIG"; then
  pass "앱 서명: $(grep -m1 '^Authority=' <<<"$APP_SIG" | sed 's/^Authority=//')"
else
  fail "앱이 배포 인증서로 서명되지 않았습니다"
  grep '^Authority=' <<<"$APP_SIG" >&2 || echo "$APP_SIG" >&2
fi
if codesign --verify --deep --strict "$APP" 2>/dev/null; then
  pass "서명 무결성"
else
  fail "서명 무결성 검사 실패 (codesign --verify --deep --strict)"
fi

# 4-3. 프로비저닝 프로파일 = 이 앱의 App Store 프로파일 (없으면 TestFlight 가 ITMS-90889 로 거절한다)
PROFILE="${APP}/Contents/embedded.provisionprofile"
if [ -f "$PROFILE" ]; then
  security cms -D -i "$PROFILE" > "${CHECK_DIR}/profile.plist" 2>/dev/null
  PROFILE_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "${CHECK_DIR}/profile.plist" 2>/dev/null || true)
  PROFILE_NAME=$(/usr/libexec/PlistBuddy -c "Print :Name" "${CHECK_DIR}/profile.plist" 2>/dev/null || true)
  HAS_DEVICES=0
  /usr/libexec/PlistBuddy -c "Print :ProvisionedDevices" "${CHECK_DIR}/profile.plist" >/dev/null 2>&1 && HAS_DEVICES=1
  if [ "$PROFILE_APP_ID" = "${TEAM_ID}.${BUNDLE_ID}" ] && [ "$HAS_DEVICES" = 0 ]; then
    pass "프로비저닝 프로파일: ${PROFILE_NAME} (${PROFILE_APP_ID}, 기기 제한 없음)"
  else
    fail "프로파일이 이 앱의 App Store 프로파일이 아닙니다 (앱 ID ${PROFILE_APP_ID:-없음}, 기기 목록 ${HAS_DEVICES})"
  fi
else
  fail "앱 묶음에 embedded.provisionprofile 이 없습니다"
fi

# 4-4. entitlements = 샌드박스 + 앱 범위 북마크 (심사 노트와 같아야 한다), 번들 ID 는 실제 ID
ENT=$(codesign -d --entitlements :- "$APP" 2>/dev/null || true)
echo "$ENT" > "${CHECK_DIR}/ent.plist"
ent_true() { [ "$(/usr/libexec/PlistBuddy -c "Print :$1" "${CHECK_DIR}/ent.plist" 2>/dev/null)" = "true" ]; }
if ent_true com.apple.security.app-sandbox && ent_true com.apple.security.files.bookmarks.app-scope; then
  pass "entitlements: App Sandbox + 앱 범위 북마크"
else
  fail "entitlements 에 App Sandbox 또는 앱 범위 북마크가 없습니다"
fi
ENT_APP_ID=$(/usr/libexec/PlistBuddy -c "Print :com.apple.application-identifier" "${CHECK_DIR}/ent.plist" 2>/dev/null || true)
if [ "$ENT_APP_ID" = "${TEAM_ID}.${BUNDLE_ID}" ]; then
  pass "앱 ID: ${ENT_APP_ID}"
else
  fail "서명된 앱 ID 가 ${TEAM_ID}.${BUNDLE_ID} 가 아닙니다 (${ENT_APP_ID:-없음})"
fi

# 4-5. Info.plist = 번들 ID · 버전 · 빌드 번호 · 업로드 필수 키
INFO="${APP}/Contents/Info.plist"
read_info() { plutil -extract "$1" raw "$INFO" 2>/dev/null || true; }
[ "$(read_info CFBundleIdentifier)" = "$BUNDLE_ID" ] && pass "번들 ID: ${BUNDLE_ID}" || fail "번들 ID 가 ${BUNDLE_ID} 가 아닙니다 ($(read_info CFBundleIdentifier))"
[ "$(read_info CFBundleShortVersionString)" = "$VERSION" ] && [ "$(read_info CFBundleVersion)" = "$BUILD_NUMBER" ] \
  && pass "버전: ${VERSION} (build ${BUILD_NUMBER})" \
  || fail "버전 표기가 다릅니다 ($(read_info CFBundleShortVersionString) build $(read_info CFBundleVersion))"
[ "$(read_info LSApplicationCategoryType)" = "public.app-category.productivity" ] && pass "카테고리: public.app-category.productivity" || fail "LSApplicationCategoryType 이 없거나 다릅니다"
[ "$(read_info ITSAppUsesNonExemptEncryption)" = "false" ] && pass "수출 규정: ITSAppUsesNonExemptEncryption = NO" || fail "ITSAppUsesNonExemptEncryption 이 NO 가 아닙니다"

# 4-6. 자동 업데이트(Sparkle)가 섞이지 않았는지 — 빌드 단계 검사를 서명된 최종 묶음에 한 번 더
if Scripts/verify-app-bundle.sh appstore "$APP" >/dev/null 2>&1; then
  pass "Sparkle 없음 (verify-app-bundle.sh appstore)"
else
  fail "App Store판 묶음에 Sparkle 구성이 섞였습니다"
  Scripts/verify-app-bundle.sh appstore "$APP" >&2 || true
fi

if [ "$FAILED" = 1 ]; then
  echo "✗ 산출물 검사 실패. 업로드하지 않습니다." >&2
  exit 1
fi
echo "✓ 산출물 검사 통과"

# ── 5. 업로드 (--upload) ─────────────────────────────────
if [ "$UPLOAD" = 1 ]; then
  echo "App Store Connect 업로드 중 (수 분)"
  if [ ${#AUTH_ARGS[@]} -gt 0 ]; then
    # API 키: 검사를 통과한 그 설치 패키지를 그대로 올린다.
    #   --wait = App Store Connect 처리(수십 분)가 끝날 때까지 기다려 처리 결과까지 알린다.
    xcrun altool --upload-package "$PKG" \
      --api-key "$ASC_KEY_ID" --api-issuer "$ASC_ISSUER_ID" \
      --p8-file-path "$ASC_KEY_PATH" \
      --show-progress --wait
  else
    # Xcode 계정: 같은 아카이브를 업로드 대상으로 다시 내보낸다(서명 내용은 4절에서 검사한 것과 같다).
    UPLOAD_PLIST="${OUT}/ExportOptions-upload.plist"
    cp ExportOptions-AppStore.plist "$UPLOAD_PLIST"
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$UPLOAD_PLIST"
    xcodebuild \
      -exportArchive \
      -archivePath "$ARCHIVE" \
      -exportPath "${OUT}/upload" \
      -exportOptionsPlist "$UPLOAD_PLIST" \
      -allowProvisioningUpdates
  fi
  echo "✓ 업로드 완료. App Store Connect 처리(수십 분)가 끝나면 TestFlight 빌드 목록에 ${VERSION} (${BUILD_NUMBER}) 이 나타납니다."
fi

echo ""
echo "✓ ${PKG}"
echo "  버전: ${VERSION} (build ${BUILD_NUMBER})"
echo "  크기: $(du -h "$PKG" | cut -f1)"
