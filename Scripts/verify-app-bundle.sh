#!/bin/bash
# 앱 묶음 배포판 검사 (TASK-112) — dmg판과 App Store판이 섞여 나가지 않게 막는다.
#
# 사용: Scripts/verify-app-bundle.sh <dmg|appstore> <Stash.app 경로>
#   dmg      = Sparkle 프레임워크가 묶음에 있고, 실행 파일이 Sparkle 에 연결되고, Info.plist 에 Sparkle 설정 키(SU…)가 있어야 한다
#   appstore = 위 세 가지가 하나도 없어야 한다 (가이드라인 2.4.5(vii) — 업데이트는 App Store 만 맡는다)
#
# 두 타깃의 빌드 마지막 단계(project.yml postBuildScripts)에서 불린다. 개발 빌드·코드 테스트·배포 아카이브가
# 모두 이 검사를 거치므로, 어긋나면 그 자리에서 빌드가 실패한다.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "사용: $0 <dmg|appstore> <Stash.app 경로>" >&2
  exit 2
fi

FLAVOR="$1"
APP="$2"
INFO="${APP}/Contents/Info.plist"

if [ ! -f "$INFO" ]; then
  echo "error: 앱 묶음을 찾지 못했습니다: ${APP}" >&2
  exit 1
fi

EXEC_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO")
EXEC="${APP}/Contents/MacOS/${EXEC_NAME}"

# 세 가지 흔적을 각각 있음(1)/없음(0)으로 읽는다.
HAS_FRAMEWORK=0
[ -d "${APP}/Contents/Frameworks/Sparkle.framework" ] && HAS_FRAMEWORK=1

# 출력을 먼저 받아 두고 대조한다. 파이프로 바로 grep -q 하면 grep 이 먼저 끝나 앞 명령이 SIGPIPE 로 실패하고,
# pipefail 때문에 *있는데 없다* 로 읽힐 수 있다.
# Debug 빌드는 실행 파일이 껍데기이고 실제 코드는 옆의 <이름>.debug.dylib 에 있어 연결도 그쪽에 걸린다. 둘 다 본다.
LINKS=$(otool -L "$EXEC")
if [ -f "${EXEC}.debug.dylib" ]; then
  LINKS+=$'\n'$(otool -L "${EXEC}.debug.dylib")
fi
HAS_LINK=0
grep -q "Sparkle.framework" <<<"$LINKS" && HAS_LINK=1

# Sparkle 설정 키는 모두 SU 로 시작한다 (SUFeedURL · SUPublicEDKey · SUEnableAutomaticChecks …).
PLIST_DUMP=$(/usr/libexec/PlistBuddy -c "Print" "$INFO")
HAS_KEYS=0
grep -qE '^    SU[A-Za-z]+ = ' <<<"$PLIST_DUMP" && HAS_KEYS=1

report() {
  echo "  Sparkle 프레임워크 포함: ${HAS_FRAMEWORK} / 실행 파일 연결: ${HAS_LINK} / Info.plist 설정 키: ${HAS_KEYS}" >&2
}

case "$FLAVOR" in
  dmg)
    if [ "$HAS_FRAMEWORK$HAS_LINK$HAS_KEYS" != "111" ]; then
      echo "error: dmg판 묶음에 자동 업데이트(Sparkle) 구성이 빠졌습니다: ${APP}" >&2
      report
      exit 1
    fi
    ;;
  appstore)
    if [ "$HAS_FRAMEWORK$HAS_LINK$HAS_KEYS" != "000" ]; then
      echo "error: App Store판 묶음에 자동 업데이트(Sparkle) 구성이 섞였습니다: ${APP}" >&2
      report
      exit 1
    fi
    ;;
  *)
    echo "error: 배포판은 dmg 또는 appstore 여야 합니다: ${FLAVOR}" >&2
    exit 2
    ;;
esac

echo "✓ ${FLAVOR}판 묶음 검사 통과: ${APP}"
