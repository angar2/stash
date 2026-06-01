#!/usr/bin/env bash
# Stash dmg 설치 흔적 완전 삭제 — 앱 본체 / 사용자 데이터 / 설정 / 캐시 / 권한 / 크래시 리포트
# 주의: 앱 본체·데이터는 번들 ID(com.angar2.stash)·고유 파일로 검증 후 삭제 (동명 앱 보호).
#       크래시 리포트만 이름 기반이라, 동명의 다른 'Stash' 앱이 있으면 함께 지워질 수 있음 (README 경고 참조).

echo "== Removing app bundle (verifying bundle ID) =="
if [ "$(defaults read /Applications/Stash.app/Contents/Info CFBundleIdentifier 2>/dev/null)" = "com.angar2.stash" ]; then
  rm -rf /Applications/Stash.app
fi

echo "== Removing user data (verifying DB file) =="
if [ -f ~/Library/Application\ Support/stash/clips.sqlite ]; then
  rm -rf ~/Library/Application\ Support/stash/
fi

echo "== Removing preferences (UserDefaults) =="
defaults delete com.angar2.stash 2>/dev/null
rm -f ~/Library/Preferences/com.angar2.stash.plist

echo "== Removing caches =="
rm -rf ~/Library/Saved\ Application\ State/com.angar2.stash.savedState/
rm -rf ~/Library/Caches/com.angar2.stash/

echo "== Resetting permissions (TCC) =="
tccutil reset Accessibility com.angar2.stash 2>/dev/null
tccutil reset Notifications com.angar2.stash 2>/dev/null

echo "== Removing crash reports =="
rm -f ~/Library/Logs/DiagnosticReports/[Ss]tash-*.ips
rm -f ~/Library/Application\ Support/CrashReporter/[Ss]tash_*.plist

echo ""
echo "Done. If a login item remains, check System Settings > General > Login Items."
