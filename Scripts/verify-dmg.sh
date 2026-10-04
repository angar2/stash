#!/bin/bash
# 완성된 .dmg 의 설치 창 설정과 서명·공증이 실제로 담겼는지 대조하는 검증 스크립트 — build-dmg.sh 말미 게이트 겸 단독 실행용

# 검사 항목을 끝까지 훑어 어긋난 것을 *모두* 보여줘야 하므로 -e 는 쓰지 않는다.
set -uo pipefail

# ── 기대값 ───────────────────────────────────────────────
# Scripts/build-dmg.sh 의 Finder 창 설정 + Scripts/make-dmg-background.swift 의 캔버스 크기와 한 쌍.
# 세 곳 중 하나만 바꾸면 여기서 잡힌다.
APP_NAME="Stash"
EXPECT_WINDOW_WIDTH=654
EXPECT_WINDOW_HEIGHT=444
EXPECT_ICON_SIZE=140
EXPECT_APP_POS="197,195"
EXPECT_APPLICATIONS_POS="473,195"
EXPECT_BG_WIDTH=654
EXPECT_BG_HEIGHT=422
# 서명 기대값 (TASK-108). project.yml Release 구성 + ExportOptions.plist + build-dmg.sh 와 한 쌍.
EXPECT_BUNDLE_ID="com.angar2.stash"
EXPECT_TEAM_ID="L7J8SQ9T5F"

DMG_PATH="${1:-}"
if [ -z "$DMG_PATH" ]; then
  echo "사용법: Scripts/verify-dmg.sh <dmg 경로>" >&2
  exit 64
fi
if [ ! -f "$DMG_PATH" ]; then
  echo "✗ dmg 파일을 찾을 수 없습니다: $DMG_PATH" >&2
  exit 1
fi

FAILURES=0
ok()  { echo "  ✓ $1"; }
ng()  { echo "  ✗ $1" >&2; FAILURES=$((FAILURES + 1)); }

# ── 마운트 ───────────────────────────────────────────────
# 검사는 파일 읽기만 하므로 Finder 가 필요 없다 → /Volumes 대신 임시 경로에 붙여
# 다른 dmg 와 이름이 겹치는 상황을 피한다. (기록 단계와 달리 여기서는 /Volumes 제약이 없다.)
MOUNT_ROOT=$(mktemp -d /tmp/stash-verify-XXXXXX)
MOUNT_POINT="${MOUNT_ROOT}/vol"
ATTACH_OUTPUT=$(hdiutil attach "$DMG_PATH" -readonly -nobrowse -noautoopen -mountpoint "$MOUNT_POINT" 2>&1)
DEV=$(echo "$ATTACH_OUTPUT" | awk '/GUID_partition_scheme/ { print $1; exit }')
if [ -z "$DEV" ]; then
  echo "✗ dmg 마운트 실패: $DMG_PATH" >&2
  echo "$ATTACH_OUTPUT" >&2
  rmdir "$MOUNT_ROOT" 2>/dev/null || true
  exit 1
fi
cleanup() {
  hdiutil detach "$DEV" -force >/dev/null 2>&1 || true
  rm -rf "$MOUNT_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

echo "dmg 설치 창 설정·서명 검증 — $DMG_PATH"

# ── 1. 구성 파일 ─────────────────────────────────────────
[ -d "$MOUNT_POINT/${APP_NAME}.app" ] && ok "${APP_NAME}.app 존재" || ng "${APP_NAME}.app 없음"

if [ -L "$MOUNT_POINT/Applications" ]; then
  LINK_TARGET=$(readlink "$MOUNT_POINT/Applications")
  [ "$LINK_TARGET" = "/Applications" ] \
    && ok "Applications 심볼릭 링크 → /Applications" \
    || ng "Applications 링크 대상이 다름: $LINK_TARGET"
else
  ng "Applications 심볼릭 링크 없음"
fi

BG_FILE="$MOUNT_POINT/.background/background.png"
[ -f "$BG_FILE" ] && ok "배경 이미지 존재 (.background/background.png)" || ng "배경 이미지 없음"

[ -f "$MOUNT_POINT/.VolumeIcon.icns" ] && ok "볼륨 아이콘 존재 (.VolumeIcon.icns)" || ng "볼륨 아이콘 없음"

# 볼륨에 커스텀 아이콘 플래그가 없으면 .VolumeIcon.icns 가 있어도 기본 디스크 아이콘으로 뜬다
if [ "$(GetFileInfo -aC "$MOUNT_POINT" 2>/dev/null)" = "1" ]; then
  ok "볼륨 커스텀 아이콘 플래그 설정됨"
else
  ng "볼륨 커스텀 아이콘 플래그 없음 (SetFile -a C 누락)"
fi

# ── 2. 배경 이미지 크기 ───────────────────────────────────
# 창 콘텐츠 크기와 정확히 같아야 한다. 크면 Finder 가 축소하지 않고 좌상단 조각만 그려
# 화살표가 창 밖으로 밀려난다(2x 이미지를 넣었을 때 실제로 발생).
if [ -f "$BG_FILE" ]; then
  BG_DIMS=$(sips -g pixelWidth -g pixelHeight "$BG_FILE" 2>/dev/null \
    | awk '/pixelWidth/ { w=$2 } /pixelHeight/ { h=$2 } END { print w "x" h }')
  EXPECT_DIMS="${EXPECT_BG_WIDTH}x${EXPECT_BG_HEIGHT}"
  [ "$BG_DIMS" = "$EXPECT_DIMS" ] \
    && ok "배경 이미지 크기 $BG_DIMS" \
    || ng "배경 이미지 크기가 다름: $BG_DIMS (기대 $EXPECT_DIMS)"
fi

# ── 3. 창 설정 (.DS_Store) ───────────────────────────────
# .DS_Store 는 Finder 전용 바이너리다. 아이콘 좌표(Iloc) / 아이콘뷰 설정(icvp) / 창 설정(bwsp) 세 항목만 꺼내 대조한다.
if [ ! -f "$MOUNT_POINT/.DS_Store" ]; then
  ng ".DS_Store 없음 — 창 설정이 기록되지 않았습니다 (Finder 자동화 권한 확인 필요)"
else
  DS_RESULT=$(python3 - "$MOUNT_POINT/.DS_Store" <<PYTHON
import plistlib, re, struct, sys

APP_NAME = "${APP_NAME}"
EXPECT = {
    "window": (${EXPECT_WINDOW_WIDTH}, ${EXPECT_WINDOW_HEIGHT}),
    "iconSize": ${EXPECT_ICON_SIZE},
    "appPos": tuple(int(v) for v in "${EXPECT_APP_POS}".split(",")),
    "applicationsPos": tuple(int(v) for v in "${EXPECT_APPLICATIONS_POS}".split(",")),
}

data = open(sys.argv[1], "rb").read()
failures = 0


def report(is_ok, message):
    global failures
    print(("  ✓ " if is_ok else "  ✗ ") + message)
    if not is_ok:
        failures += 1


def blob_at(key):
    """레코드 키(4바이트) 뒤에 [타입 4바이트][길이 4바이트][본문] 이 오는 구조에서 본문만 꺼낸다."""
    i = data.find(key)
    if i < 0:
        return None
    length = struct.unpack(">I", data[i + 8:i + 12])[0]
    return data[i + 12:i + 12 + length]


def icon_positions():
    """Iloc 레코드 앞에 붙은 UTF-16BE 파일명을 역으로 짚어 {이름: (x, y)} 로 모은다."""
    positions = {}
    i = 0
    while True:
        i = data.find(b"Iloc", i)
        if i < 0:
            return positions
        length = struct.unpack(">I", data[i + 8:i + 12])[0]
        x, y = struct.unpack(">II", data[i + 12:i + 20])
        for back in range(2, 120, 2):
            offset = i - back - 4
            if offset < 0:
                break
            if struct.unpack(">I", data[offset:offset + 4])[0] * 2 == back:
                positions[data[offset + 4:i].decode("utf-16-be", "replace")] = (x, y)
                break
        i += 4


positions = icon_positions()
for label, name, expected in (
    ("앱 아이콘", APP_NAME + ".app", EXPECT["appPos"]),
    ("Applications", "Applications", EXPECT["applicationsPos"]),
):
    actual = positions.get(name)
    report(actual == expected, "%s 좌표 %s (기대 %s)" % (label, actual, expected))

# 배경 폴더에 좌표가 적혀 있으면, 숨김 파일 표시를 켠 사용자 화면에 폴더 아이콘이 그대로 뜬다.
# build-dmg.sh 가 Finder 작업 뒤 이름을 되돌려 떼어내므로 여기서는 없어야 정상이다.
report(".background" not in positions,
       "배경 폴더 좌표 없음 (있으면 숨김 표시 사용자 화면에 폴더가 뜬다)")

icvp = blob_at(b"icvp")
if icvp is None:
    report(False, "아이콘뷰 설정(icvp) 없음")
else:
    view = plistlib.loads(icvp)
    report(view.get("iconSize") == EXPECT["iconSize"],
           "아이콘 크기 %s (기대 %s)" % (view.get("iconSize"), EXPECT["iconSize"]))
    report(view.get("arrangeBy") == "none", "자동 정렬 %s (기대 none)" % view.get("arrangeBy"))
    report(view.get("backgroundType") == 2, "배경 종류 %s (기대 2=이미지)" % view.get("backgroundType"))
    report(bool(view.get("labelOnBottom")), "라벨 위치 아래")

bwsp = blob_at(b"bwsp")
if bwsp is None:
    report(False, "창 설정(bwsp) 없음")
else:
    window = plistlib.loads(bwsp)
    bounds = window.get("WindowBounds", "")
    numbers = [int(n) for n in re.findall(r"-?\\d+", bounds)]
    size = tuple(numbers[2:4]) if len(numbers) >= 4 else None
    report(size == EXPECT["window"], "창 크기 %s (기대 %s)" % (size, EXPECT["window"]))
    report(window.get("ShowToolbar") is False, "툴바 숨김")
    report(window.get("ShowStatusBar") is False, "상태바 숨김")

sys.exit(failures)
PYTHON
)
  DS_FAILURES=$?
  echo "$DS_RESULT"
  FAILURES=$((FAILURES + DS_FAILURES))
fi

# ── 4. 서명·공증 (TASK-108) ──────────────────────────────
APP_PATH="$MOUNT_POINT/${APP_NAME}.app"
if [ -d "$APP_PATH" ]; then
  codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
    && ok "앱 서명 유효 (내장 코드 포함)" \
    || ng "앱 서명 검증 실패 (codesign --verify --deep --strict)"

  # 서명 요건이 번들 ID + 팀 ID 로 고정돼야 업데이트 뒤에도 손쉬운 사용 권한이 유지된다.
  # ad-hoc 서명은 요건이 빌드마다 바뀌는 해시(cdhash)라 업데이트마다 권한이 풀린다.
  REQUIREMENT=$(codesign -d -r- "$APP_PATH" 2>&1)
  if echo "$REQUIREMENT" | grep -qF "identifier \"${EXPECT_BUNDLE_ID}\"" \
    && echo "$REQUIREMENT" | grep -qF "anchor apple generic" \
    && echo "$REQUIREMENT" | grep -qF "certificate leaf[subject.OU] = ${EXPECT_TEAM_ID}"; then
    ok "서명 요건 = 번들 ID ${EXPECT_BUNDLE_ID} + 팀 ID ${EXPECT_TEAM_ID}"
  else
    ng "서명 요건이 번들 ID + 팀 ID 고정이 아님: $(echo "$REQUIREMENT" | grep designated)"
  fi

  # 앱 본체와 내장 프레임워크·도구가 모두 같은 팀 + Hardened Runtime 이어야 공증이 유지된다.
  #   Sparkle 은 실행 파일(Autoupdate)·Updater.app·XPC 서비스를 프레임워크 안에 품고 있다.
  #   Versions/Current 는 심볼릭 링크라 find 가 따라가지 않아 같은 코드를 두 번 세지 않는다.
  NESTED_CODE=$( { echo "$APP_PATH"
    find "$APP_PATH/Contents/Frameworks" -type d \( -name "*.framework" -o -name "*.app" -o -name "*.xpc" \) 2>/dev/null
    find "$APP_PATH/Contents/Frameworks" -type f -name "Autoupdate" 2>/dev/null; } )
  while IFS= read -r CODE; do
    [ -z "$CODE" ] && continue
    LABEL="${CODE#"$MOUNT_POINT/"}"
    INFO=$(codesign -dv "$CODE" 2>&1)
    TEAM=$(echo "$INFO" | awk -F= '/^TeamIdentifier=/ { print $2 }')
    if [ "$TEAM" = "$EXPECT_TEAM_ID" ] && echo "$INFO" | grep -q "flags=.*runtime"; then
      ok "팀 ${EXPECT_TEAM_ID} + Hardened Runtime: $LABEL"
    else
      ng "팀 ID(${TEAM:-없음}) 또는 Hardened Runtime 불일치: $LABEL"
    fi
  done <<< "$NESTED_CODE"

  # Gatekeeper 판정. 사용자 맥이 처음 열 때 내리는 판정과 같다.
  APP_ASSESS=$(spctl --assess --type execute -vv "$APP_PATH" 2>&1)
  echo "$APP_ASSESS" | grep -q ": accepted" && echo "$APP_ASSESS" | grep -q "source=Notarized Developer ID" \
    && ok "앱 Gatekeeper 판정: 허용 (Notarized Developer ID)" \
    || ng "앱 Gatekeeper 판정 실패: $(echo "$APP_ASSESS" | tr '\n' ' ')"
fi

DMG_ASSESS=$(spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH" 2>&1)
echo "$DMG_ASSESS" | grep -q ": accepted" && echo "$DMG_ASSESS" | grep -q "source=Notarized Developer ID" \
  && ok "dmg Gatekeeper 판정: 허용 (Notarized Developer ID)" \
  || ng "dmg Gatekeeper 판정 실패: $(echo "$DMG_ASSESS" | tr '\n' ' ')"

xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1 \
  && ok "dmg 공증 티켓 부착됨" \
  || ng "dmg 공증 티켓 없음 (xcrun stapler staple 누락)"

# ── 결과 ─────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "✓ dmg 설치 창 설정·서명 검증 통과"
  exit 0
fi
echo "✗ dmg 설치 창 설정·서명 검증 실패 — 어긋난 항목 ${FAILURES}개" >&2
exit 1
