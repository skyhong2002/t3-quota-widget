#!/bin/zsh
set -e
TASK_WIDGET_ROOT="$(cd -- "$(dirname -- "$0")" && pwd)"
TASK_LSREGISTER='/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'
TASK_INSTALLED='/Applications/T3 帳號額度 Widget.app'
# Only this application's extension is stopped. No global database/cache reset.
/usr/bin/pkill -TERM -x T3Widget || true
for TASK_BUNDLE in "$TASK_WIDGET_ROOT/build/T3 帳號額度 Widget.app" "$TASK_INSTALLED"; do
  /usr/bin/pluginkit -r "$TASK_BUNDLE/Contents/PlugIns/T3Widget.appex" || true
  "$TASK_LSREGISTER" -u "$TASK_BUNDLE" || true
done
"$TASK_LSREGISTER" -f "$TASK_INSTALLED"
/usr/bin/pluginkit -a "$TASK_INSTALLED/Contents/PlugIns/T3Widget.appex"
/usr/bin/pluginkit -e use -i tw.skyhong.t3usage.widget
/bin/launchctl kickstart -k "gui/$(/usr/bin/id -u)/tw.skyhong.t3usage"
printf '已重登錄這個 Widget。請檢查桌面畫面。\n'
printf '按 Enter 關閉。'
read -r TASK_REPAIR_DONE
